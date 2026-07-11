import XCTest
@testable import Vaultify

/// Scoring engine contract: bounds, determinism, monotonic improvement, and
/// golden fixtures that lock the behavior of every pillar formula.
final class ScoringEngineTests: XCTestCase {

    private let strongPasswords = [
        "kR9#mPz$vL2@qXw7!nT4", "x7Qw!2zR8pL#mN5vY3&j", "F4$dGh8@kL1!pQz6W9^m",
        "u2%R7tYx!4Kq@9ZpL$w3", "N8@fV3#sT6!bJq1$Xz5m",
    ]

    private func login(id: String, title: String = "Site", password: String?,
                       url: String = "https://example.org", username: String = "user",
                       totp: String? = nil) -> VaultItem {
        var fields = [DynamicField(label: "Username", kind: .username, value: username),
                      DynamicField(label: "Website", kind: .url, value: url)]
        if let password { fields.append(DynamicField(label: "Password", kind: .password, value: password)) }
        if let totp { fields.append(DynamicField(label: "One-time Code", kind: .totp, value: totp)) }
        return VaultItem(id: id, category: .login, title: title, fields: fields)
    }

    private func report(_ items: [VaultItem],
                        extraFindings: [AuditFinding] = [],
                        daysSinceLastAudit: Int? = nil) async throws -> AuditReport {
        let snapshot = VaultAuditSnapshot.make(items: items)
        let coordinator = AuditCoordinator(rules: AuditRuleRegistry.localRules())
        let run = try await coordinator.run(snapshot: snapshot, context: AuditContext())
        let merged = AuditRunResult(findings: run.findings + extraFindings,
                                    startedAt: run.startedAt, completedAt: run.completedAt,
                                    onlineChecksCompleted: run.onlineChecksCompleted,
                                    ruleVersions: run.ruleVersions)
        return ScoringEngine.report(snapshot: snapshot, run: merged,
                                    daysSinceLastCompletedAudit: daysSinceLastAudit)
    }

    private func leakedFinding(itemID: String, password: String) -> AuditFinding {
        AuditFinding(ruleID: "exposure.leaked", ruleVersion: 1, severity: .high,
                     category: .exposure, affectedItemIDs: [itemID],
                     fingerprint: AuditFingerprint.make(ruleID: "exposure.leaked", version: 1,
                                                        itemIDs: [itemID],
                                                        marker: AuditFingerprint.secretMarker(password)),
                     titleKey: "finding.exposure.leaked.title", detail: nil,
                     remediation: .changePassword, estimatedFixSeconds: 120, detectedAt: .now)
    }

    // MARK: - Invariants

    func testEmptyVaultScoresFullAndUnlimitedConfidence() async throws {
        let r = try await report([])
        XCTAssertEqual(r.score, 1000)
        XCTAssertFalse(r.confidenceLimited)
    }

    func testCleanVaultScoresFull() async throws {
        let items = strongPasswords.enumerated().map {
            login(id: "i\($0.offset)", password: $0.element, url: "https://site\($0.offset).test")
        }
        let r = try await report(items)
        XCTAssertEqual(r.score, 1000, "5 strong unique passwords, no findings → full score")
        XCTAssertFalse(r.confidenceLimited)
    }

    func testScoreIsSumOfPillarsAndBounded() async throws {
        let items = [login(id: "a", password: "password"),
                     login(id: "b", password: "password"),
                     login(id: "c", password: nil)]
        let r = try await report(items)
        XCTAssertEqual(r.score, r.pillars.reduce(0) { $0 + $1.earned })
        XCTAssertTrue((0...1000).contains(r.score))
        XCTAssertTrue(r.pillars.allSatisfy { (0...$0.max).contains($0.earned) })
    }

    func testDeterministic() async throws {
        let items = [login(id: "a", password: "Summer2026"),
                     login(id: "b", password: "Summer2026")]
        let first = try await report(items)
        let second = try await report(items)
        XCTAssertEqual(first.score, second.score)
        XCTAssertEqual(first.pillars, second.pillars)
    }

    func testFixingAnIssueNeverLowersTheScore() async throws {
        let broken = [login(id: "a", password: "password"),
                      login(id: "b", password: "password")] +
            strongPasswords.dropFirst().enumerated().map {
                login(id: "s\($0.offset)", password: $0.element, url: "https://s\($0.offset).test")
            }
        let fixed = [login(id: "a", password: strongPasswords[0]),
                     login(id: "b", password: "uQ5!wR8#zT2@nM6$pK9x")] +
            strongPasswords.dropFirst().enumerated().map {
                login(id: "s\($0.offset)", password: $0.element, url: "https://s\($0.offset).test")
            }
        let before = try await report(broken)
        let after = try await report(fixed)
        XCTAssertGreaterThan(after.score, before.score)
    }

    // MARK: - Pillars

    func testLeakedPenaltyIsGroupBasedAndSkipsQualityDoubleBilling() async throws {
        let items = [login(id: "a", password: "leaked-pass-1"),
                     login(id: "b", password: "leaked-pass-1"),
                     login(id: "c", password: strongPasswords[0])]
        let findings = [leakedFinding(itemID: "a", password: "leaked-pass-1"),
                        leakedFinding(itemID: "b", password: "leaked-pass-1")]
        let r = try await report(items, extraFindings: findings)
        // One unique leaked password shared by 2 items: 300 - 60 - 20 = 220.
        XCTAssertEqual(r.earned[.exposure], 220)
        // Quality scores only the non-leaked item (strong): full pillar.
        XCTAssertEqual(r.earned[.quality], 220)
    }

    func testReusePenaltyWeighsSensitiveCategories() async throws {
        func vault(_ url: String) -> [VaultItem] {
            [login(id: "a", password: "shared-pw-99", url: url),
             login(id: "b", password: "shared-pw-99", url: "https://forum.test")]
        }
        let email = try await report(vault("https://gmail.com"))
        let fun = try await report(vault("https://netflix.com"))
        XCTAssertLessThan(email.earned[.reuseIsolation]!, fun.earned[.reuseIsolation]!,
                          "reuse touching primary email must cost more than entertainment")
    }

    func testAuthOpportunitiesArePenalizedGently() async throws {
        // GitHub login without TOTP: an opportunity, never a heavy hit.
        let r = try await report([login(id: "a", password: strongPasswords[0],
                                        url: "https://github.com")])
        XCTAssertGreaterThanOrEqual(r.earned[.authReadiness]!, 105, "≥75% floor")
        XCTAssertLessThan(r.earned[.authReadiness]!, 140)

        let covered = try await report([login(id: "a", password: strongPasswords[0],
                                              url: "https://github.com", totp: "JBSWY3DPEHPK3PXP")])
        XCTAssertEqual(covered.earned[.authReadiness], 140)
    }

    func testConflictHitsIntegrityHarderThanExactDuplicate() async throws {
        let conflict = [login(id: "a", password: "pass-one-1!", url: "https://site.test"),
                        login(id: "b", password: "pass-two-2!", url: "https://site.test")]
        let dup = [login(id: "a", title: "Same", password: strongPasswords[0], url: "https://site.test"),
                   login(id: "b", title: "Same", password: strongPasswords[0], url: "https://site.test")]
        let conflictReport = try await report(conflict)
        let dupReport = try await report(dup)
        XCTAssertLessThan(conflictReport.earned[.integrity]!, dupReport.earned[.integrity]!)
    }

    func testMaintenancePenalizesOverdueAudit() async throws {
        let items = [login(id: "a", password: strongPasswords[0])]
        let fresh = try await report(items, daysSinceLastAudit: 10)
        let overdue = try await report(items, daysSinceLastAudit: 120)
        XCTAssertEqual(fresh.earned[.maintenance], 60)
        XCTAssertEqual(overdue.earned[.maintenance], 40)
    }

    // MARK: - Safeguards

    func testSmallVaultIsFlaggedLowConfidenceNotScaled() async throws {
        let r = try await report([login(id: "a", password: "password"),
                                  login(id: "b", password: strongPasswords[0])])
        XCTAssertTrue(r.confidenceLimited)
        XCTAssertTrue((0...1000).contains(r.score))
    }

    func testStatsAreReported() async throws {
        let items = [login(id: "a", password: "password", url: "https://one.test"),
                     login(id: "b", password: "password", url: "https://two.test")]
        let r = try await report(items)
        XCTAssertEqual(r.analyzedItemCount, 2)
        XCTAssertEqual(r.uniquePasswordCount, 1)
        XCTAssertEqual(r.domainCount, 2)
    }
}
