import XCTest
@testable import Vaultify

/// Core audit engine: fingerprint stability, rule behavior parity with the
/// legacy `PasswordAudit.analyze`, coordinator cancellation and fail-soft
/// network handling.
final class AuditEngineCoreTests: XCTestCase {

    // MARK: - Fixtures

    private func login(id: String, title: String, password: String? = nil,
                       url: String? = nil, totp: String? = nil,
                       trashed: Bool = false) -> VaultItem {
        var fields: [DynamicField] = []
        if let password { fields.append(DynamicField(label: "Password", kind: .password, value: password)) }
        if let url { fields.append(DynamicField(label: "Website", kind: .url, value: url)) }
        if let totp { fields.append(DynamicField(label: "One-time Code", kind: .totp, value: totp)) }
        return VaultItem(id: id, category: .login, title: title, fields: fields,
                         trashedAt: trashed ? .now : nil)
    }

    private func snapshot(_ items: [VaultItem]) -> VaultAuditSnapshot {
        VaultAuditSnapshot.make(items: items)
    }

    private func run(_ rule: any AuditRule, _ items: [VaultItem]) async throws -> [AuditFinding] {
        try await rule.evaluate(snapshot(items), context: AuditContext())
    }

    // MARK: - Fingerprint

    func testFingerprintIsStableAcrossRuns() {
        let a = AuditFingerprint.make(ruleID: "reuse.exact", version: 1, itemIDs: ["b", "a"], marker: "m")
        let b = AuditFingerprint.make(ruleID: "reuse.exact", version: 1, itemIDs: ["a", "b"], marker: "m")
        XCTAssertEqual(a, b, "item order must not change the fingerprint")
    }

    func testFingerprintChangesWithInputs() {
        let base = AuditFingerprint.make(ruleID: "r", version: 1, itemIDs: ["a"])
        XCTAssertNotEqual(base, AuditFingerprint.make(ruleID: "r", version: 2, itemIDs: ["a"]))
        XCTAssertNotEqual(base, AuditFingerprint.make(ruleID: "r", version: 1, itemIDs: ["a", "b"]))
        XCTAssertNotEqual(base, AuditFingerprint.make(ruleID: "r", version: 1, itemIDs: ["a"], marker: "x"))
    }

    func testSecretMarkerNeverEchoesSecret() {
        let marker = AuditFingerprint.secretMarker("hunter2")
        XCTAssertFalse(marker.contains("hunter2"))
        XCTAssertEqual(marker.count, 64)
    }

    // MARK: - Reuse rule

    func testReuseGroupsProduceOneFindingPerGroup() async throws {
        let items = [
            login(id: "a", title: "A", password: "shared-pass-123"),
            login(id: "b", title: "B", password: "shared-pass-123"),
            login(id: "c", title: "C", password: "shared-pass-123"),
            login(id: "d", title: "D", password: "unique-pass-456"),
        ]
        let findings = try await run(PasswordReuseRule(), items)
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings[0].affectedItemIDs, ["a", "b", "c"])
        XCTAssertEqual(findings[0].severity, .high)
    }

    func testReusePairIsMediumSeverity() async throws {
        let items = [
            login(id: "a", title: "A", password: "pair-pass"),
            login(id: "b", title: "B", password: "pair-pass"),
        ]
        let findings = try await run(PasswordReuseRule(), items)
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings[0].severity, .medium)
    }

    func testReuseIgnoresTrashedAndEmpty() async throws {
        let items = [
            login(id: "a", title: "A", password: "pass-x"),
            login(id: "b", title: "B", password: "pass-x", trashed: true),
            login(id: "c", title: "C", password: ""),
        ]
        let findings = try await run(PasswordReuseRule(), items)
        XCTAssertTrue(findings.isEmpty)
    }

    func testReuseFingerprintFollowsThePassword() async throws {
        let before = try await run(PasswordReuseRule(), [
            login(id: "a", title: "A", password: "old-shared"),
            login(id: "b", title: "B", password: "old-shared"),
        ])
        let after = try await run(PasswordReuseRule(), [
            login(id: "a", title: "A", password: "new-shared"),
            login(id: "b", title: "B", password: "new-shared"),
        ])
        XCTAssertNotEqual(before[0].fingerprint, after[0].fingerprint,
                          "changing the shared password must resolve the old finding")
    }

    // MARK: - Strength rule (parity with legacy analyze)

    func testWeakRuleMatchesLegacyWeakDetection() async throws {
        let items = [
            login(id: "a", title: "A", password: "abc"),                       // weak
            login(id: "b", title: "B", password: "kR9#mPz$vL2@qXw7!nT4"),      // strong
            login(id: "c", title: "C"),                                        // no password
        ]
        let findings = try await run(PasswordStrengthRule(), items)
        let legacy = PasswordAudit.analyze(items)
        XCTAssertEqual(Set(findings.flatMap(\.affectedItemIDs)),
                       Set(legacy.weak.map(\.itemID)))
    }

    // MARK: - 2FA rule (parity with legacy analyze)

    func testTwoFactorRuleMatchesLegacyMissing2FA() async throws {
        let items = [
            login(id: "a", title: "GitHub", password: "x", url: "https://github.com"),
            login(id: "b", title: "GitHub", password: "x", url: "https://github.com",
                  totp: "JBSWY3DPEHPK3PXP"),
            login(id: "c", title: "Unknown Service", password: "x", url: "https://example-nowhere.test"),
        ]
        let findings = try await run(TwoFactorRule(), items)
        let legacy = PasswordAudit.analyze(items)
        XCTAssertEqual(Set(findings.flatMap(\.affectedItemIDs)),
                       Set(legacy.missing2FA.map(\.itemID)))
        XCTAssertEqual(findings.flatMap(\.affectedItemIDs), ["a"])
    }

    func testCatalogMultiURLMatchesAnyHost() {
        XCTAssertTrue(TwoFactorCatalog.supports2FA(
            urls: ["https://internal.test", "https://github.com/login"], title: "Work"))
        XCTAssertFalse(TwoFactorCatalog.supports2FA(
            urls: ["https://notgithub.com"], title: "github"),
            "title fallback must not fire when URLs are present")
    }

    // MARK: - Coordinator

    private struct FailingNetworkRule: nonisolated AuditRule {
        let id = "test.failing-network"
        let version = 1
        let category = AuditCategory.exposure
        let requiresNetwork = true
        func evaluate(_ snapshot: VaultAuditSnapshot, context: AuditContext) async throws -> [AuditFinding] {
            throw URLError(.notConnectedToInternet)
        }
    }

    private struct HangingRule: nonisolated AuditRule {
        let id = "test.hanging"
        let version = 1
        let category = AuditCategory.quality
        func evaluate(_ snapshot: VaultAuditSnapshot, context: AuditContext) async throws -> [AuditFinding] {
            try await Task.sleep(nanoseconds: 10_000_000_000)
            return []
        }
    }

    func testNetworkRuleFailureKeepsLocalFindings() async throws {
        let coordinator = AuditCoordinator(rules: AuditRuleRegistry.localRules() + [FailingNetworkRule()])
        let items = [login(id: "a", title: "A", password: "abc"),
                     login(id: "b", title: "B", password: "abc")]
        let result = try await coordinator.run(snapshot: snapshot(items),
                                               context: AuditContext(onlineChecksEnabled: true))
        XCTAssertFalse(result.onlineChecksCompleted)
        XCTAssertTrue(result.findings.contains { $0.ruleID == "reuse.exact" })
        XCTAssertTrue(result.findings.contains { $0.ruleID == "quality.weak" })
    }

    func testOfflineSkipsNetworkRulesAndFlagsPartial() async throws {
        let coordinator = AuditCoordinator(rules: AuditRuleRegistry.localRules() + [FailingNetworkRule()])
        let result = try await coordinator.run(snapshot: snapshot([login(id: "a", title: "A", password: "abc")]),
                                               context: AuditContext(onlineChecksEnabled: false))
        XCTAssertFalse(result.onlineChecksCompleted)
        XCTAssertNil(result.ruleVersions["test.failing-network"])
    }

    func testCancellationThrowsWithoutResult() async throws {
        let coordinator = AuditCoordinator(rules: [HangingRule()])
        let snap = snapshot([login(id: "a", title: "A", password: "abc")])
        let task = Task {
            try await coordinator.run(snapshot: snap, context: AuditContext())
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("cancelled audit must throw, never return a result")
        } catch {}
    }

    func testCoordinatorReportsProgress() async throws {
        let coordinator = AuditCoordinator(rules: AuditRuleRegistry.localRules())
        nonisolated(unsafe) var seen: [AuditProgress] = []
        let lock = NSLock()
        _ = try await coordinator.run(snapshot: snapshot([login(id: "a", title: "A", password: "abc")]),
                                      context: AuditContext()) { p in
            lock.lock(); seen.append(p); lock.unlock()
        }
        XCTAssertEqual(seen.count, AuditRuleRegistry.localRules().count)
        XCTAssertEqual(seen.last?.completedRules, seen.last?.totalRules)
    }
}
