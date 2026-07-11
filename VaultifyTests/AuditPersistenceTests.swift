import XCTest
@testable import Vaultify

/// Audit persistence: payload sealing, retention pruning, finding-state
/// lifecycle (bump-on-change, snooze expiry, rule-version recheck), and the
/// LWW merge rules for both new record types.
@MainActor
final class AuditPersistenceTests: XCTestCase {

    private var store: VaultStore!
    private var reports: AuditReportStore!
    private let key = SecureBytes(Array(repeating: 7, count: 32))

    override func setUp() {
        super.setUp()
        store = VaultStore(inMemory: true)
        reports = AuditReportStore(store: store)
    }

    private func makeReport(score: Int, findings: [AuditFinding] = [],
                            completedAt: Date = .now) -> AuditReport {
        AuditReport(score: score,
                    pillars: AuditPillar.allCases.map { PillarScore(pillar: $0, earned: 0) },
                    findings: findings, analyzedItemCount: 3, uniquePasswordCount: 3,
                    domainCount: 2, confidenceLimited: false,
                    startedAt: completedAt, completedAt: completedAt,
                    onlineChecksCompleted: true, ruleVersions: ["quality.weak": 1])
    }

    private func finding(ruleID: String = "quality.weak", version: Int = 1,
                         itemIDs: [String] = ["item-1"]) -> AuditFinding {
        AuditFinding(ruleID: ruleID, ruleVersion: version, severity: .high, category: .quality,
                     affectedItemIDs: itemIDs,
                     fingerprint: AuditFingerprint.make(ruleID: ruleID, version: version,
                                                        itemIDs: itemIDs),
                     titleKey: "t", detail: nil, remediation: .changePassword,
                     estimatedFixSeconds: 120, detectedAt: .now)
    }

    // MARK: - Payload roundtrip + hygiene

    func testReportPayloadSealsAndReopens() throws {
        let f = finding()
        try reports.save(report: makeReport(score: 842, findings: [f]), personaID: "p1", key: key)
        let loaded = reports.latest(personaID: "p1", key: key)
        XCTAssertEqual(loaded?.score, 842)
        XCTAssertEqual(loaded?.findings.first?.fingerprint, f.fingerprint)
        XCTAssertNil(reports.latest(personaID: "other", key: key), "persona partitioned")
    }

    func testPayloadJSONCarriesNoFindingContent() throws {
        let payload = AuditReportPayload(makeReport(score: 900, findings: [finding()]))
        let json = String(data: try JSONEncoder().encode(payload), encoding: .utf8)!
        XCTAssertFalse(json.contains("title"), "payload must not persist finding text")
        XCTAssertFalse(json.contains("detail"))
    }

    func testWrongKeyYieldsNilNotCrash() throws {
        try reports.save(report: makeReport(score: 800), personaID: nil, key: key)
        let wrong = SecureBytes(Array(repeating: 9, count: 32))
        XCTAssertNil(reports.latest(personaID: nil, key: wrong))
    }

    // MARK: - Retention

    func testRetentionTombstonesBeyondCap() throws {
        for i in 0..<(VaultStore.auditReportRetention + 5) {
            try reports.save(report: makeReport(score: i,
                                                completedAt: Date(timeIntervalSinceNow: Double(i))),
                             personaID: "p1", key: key)
        }
        let live = store.auditReports(personaID: "p1")
        XCTAssertEqual(live.count, VaultStore.auditReportRetention)
        let tombstoned = store.allAuditReportRecords().filter { $0.deletedAt != nil }
        XCTAssertEqual(tombstoned.count, 5)
        XCTAssertTrue(tombstoned.allSatisfy(\.dirty), "tombstones must sync")
    }

    // MARK: - Finding state lifecycle

    func testSetStateBumpsUpdatedAtAndDirty() throws {
        let f = finding()
        try reports.setState(.ignored, reason: "not-account-password", for: f,
                             personaID: "p1", key: key)
        let record = store.findingStateRecord(id: f.fingerprint)!
        XCTAssertTrue(record.dirty)
        XCTAssertEqual(record.status, FindingStatus.ignored.rawValue)
        XCTAssertEqual(reports.effectiveStatus(of: f, personaID: "p1", key: key), .ignored)
    }

    func testRuleVersionBumpResurfacesIgnoredFinding() throws {
        let v1 = finding(version: 1)
        try reports.setState(.ignored, for: v1, personaID: nil, key: key)
        // Same underlying issue, rule logic upgraded. The stored decision was
        // made under v1 — the v2 finding must come back for review.
        var v2 = finding(version: 2)
        // v2 has a different fingerprint (version participates) → open by absence.
        XCTAssertEqual(reports.effectiveStatus(of: v2, personaID: nil, key: key), .open)
        // A state stored under an OLDER version for the same fingerprint →
        // needsRecheck (simulate by writing v1 payload at v2's fingerprint).
        v2 = finding(version: 2)
        try reports.setState(.ignored, for: AuditFinding(
            ruleID: v2.ruleID, ruleVersion: 1, severity: v2.severity, category: v2.category,
            affectedItemIDs: v2.affectedItemIDs, fingerprint: v2.fingerprint,
            titleKey: v2.titleKey, detail: nil, remediation: v2.remediation,
            estimatedFixSeconds: v2.estimatedFixSeconds, detectedAt: v2.detectedAt),
            personaID: nil, key: key)
        XCTAssertEqual(reports.effectiveStatus(of: v2, personaID: nil, key: key), .needsRecheck)
    }

    func testExpiredSnoozeReopens() throws {
        let f = finding()
        try reports.setState(.ignored, snoozedUntil: Date(timeIntervalSinceNow: -60),
                             for: f, personaID: nil, key: key)
        XCTAssertEqual(reports.effectiveStatus(of: f, personaID: nil, key: key), .open)
        try reports.setState(.ignored, snoozedUntil: Date(timeIntervalSinceNow: 3600),
                             for: f, personaID: nil, key: key)
        XCTAssertEqual(reports.effectiveStatus(of: f, personaID: nil, key: key), .ignored)
    }

    func testDisappearedFindingDerivation() {
        let digest = FindingDigest(finding(itemIDs: ["a", "b"]))
        XCTAssertEqual(AuditReportStore.disappearedStatus(previous: digest,
                                                          currentItemIDs: ["a", "x"]),
                       .resolved)
        XCTAssertEqual(AuditReportStore.disappearedStatus(previous: digest,
                                                          currentItemIDs: ["x"]),
                       .noLongerMonitored)
    }

    // MARK: - LWW merge

    func testRemoteNewerWinsOlderRedirties() {
        let sealed = Data([1])
        store.upsertFindingStateFromRemote(id: "fp", personaID: nil, sealed: sealed,
                                           status: "ignored", deletedAt: nil,
                                           createdAt: .now, updatedAt: .now, changeTag: "t1")
        let record = store.findingStateRecord(id: "fp")!
        XCTAssertFalse(record.dirty)

        // Older remote revision with a different tag → local wins, re-dirty.
        store.upsertFindingStateFromRemote(id: "fp", personaID: nil, sealed: Data([2]),
                                           status: "acceptedRisk", deletedAt: nil,
                                           createdAt: .now,
                                           updatedAt: Date(timeIntervalSinceNow: -100),
                                           changeTag: "t0")
        XCTAssertEqual(record.status, "ignored", "older remote must not overwrite")
        XCTAssertTrue(record.dirty, "local winner must re-push")

        // Same tag replay → no-op.
        record.dirty = false
        store.upsertFindingStateFromRemote(id: "fp", personaID: nil, sealed: Data([3]),
                                           status: "open", deletedAt: nil,
                                           createdAt: .now, updatedAt: .distantFuture,
                                           changeTag: "t1")
        XCTAssertEqual(record.status, "ignored")
        XCTAssertFalse(record.dirty)
    }

    func testEraseAllClearsAuditRecords() throws {
        try reports.save(report: makeReport(score: 700), personaID: nil, key: key)
        try reports.setState(.acceptedRisk, for: finding(), personaID: nil, key: key)
        try store.eraseAll()
        XCTAssertTrue(store.allAuditReportRecords().isEmpty)
        XCTAssertTrue(store.allFindingStateRecords().isEmpty)
    }
}
