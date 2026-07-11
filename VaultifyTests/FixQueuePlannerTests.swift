import XCTest
@testable import Vaultify

/// Fix queue ordering contract: highest risk first, deterministic, dismissed
/// findings excluded.
final class FixQueuePlannerTests: XCTestCase {

    private func queued(rule: String, severity: AuditSeverity,
                        items: [String] = ["i"], fp: String = UUID().uuidString) -> QueuedFinding {
        QueuedFinding(AuditFinding(ruleID: rule, ruleVersion: 1, severity: severity,
                                   category: .quality, affectedItemIDs: items, fingerprint: fp,
                                   titleKey: "", detail: nil, remediation: .reviewItem,
                                   estimatedFixSeconds: 0, detectedAt: .now))
    }

    func testDeterministicPriorityOrder() {
        let findings = [
            queued(rule: "maintenance.stale", severity: .info),
            queued(rule: "auth.passkey-available", severity: .low),
            queued(rule: "reuse.exact", severity: .high),
            queued(rule: "quality.weak", severity: .high),
            queued(rule: "integrity.duplicate-conflict", severity: .high),
            queued(rule: "quality.weak", severity: .critical),
            queued(rule: "exposure.leaked", severity: .high),
            queued(rule: "exposure.leaked", severity: .critical),
        ]
        let order = FixQueuePlanner.queue(findings: findings.shuffled(), dismissed: [])
            .map(\.ruleID)
        XCTAssertEqual(order, ["exposure.leaked",              // leaked+reused (critical)
                               "exposure.leaked",              // leaked
                               "quality.weak",                 // very weak (critical)
                               "integrity.duplicate-conflict",
                               "quality.weak",                 // weak
                               "reuse.exact",
                               "auth.passkey-available",
                               "maintenance.stale"])
    }

    func testBiggerBlastRadiusFirstWithinSamePriority() {
        let small = queued(rule: "reuse.exact", severity: .high, items: ["a", "b"], fp: "fp-small")
        let big = queued(rule: "reuse.exact", severity: .high,
                         items: ["a", "b", "c", "d"], fp: "fp-big")
        let order = FixQueuePlanner.queue(findings: [small, big], dismissed: [])
        XCTAssertEqual(order.map(\.fingerprint), ["fp-big", "fp-small"])
    }

    func testDismissedAreExcludedAndOrderIsStable() {
        let a = queued(rule: "quality.weak", severity: .high, fp: "fp-a")
        let b = queued(rule: "quality.weak", severity: .high, fp: "fp-b")
        let withDismissal = FixQueuePlanner.queue(findings: [b, a], dismissed: ["fp-a"])
        XCTAssertEqual(withDismissal.map(\.fingerprint), ["fp-b"])
        // Same inputs → same order, regardless of input shuffle.
        XCTAssertEqual(FixQueuePlanner.queue(findings: [a, b], dismissed: []),
                       FixQueuePlanner.queue(findings: [b, a], dismissed: []))
    }
}
