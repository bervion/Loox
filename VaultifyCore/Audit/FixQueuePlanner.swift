import Foundation

/// A finding normalized for the fix queue — buildable from a live
/// `AuditFinding` or a persisted `FindingDigest` so the queue works after a
/// cold open too.
nonisolated struct QueuedFinding: Identifiable, Sendable, Equatable {
    let fingerprint: String
    let ruleID: String
    let severity: AuditSeverity
    let itemIDs: [String]
    var id: String { fingerprint }

    init(_ finding: AuditFinding) {
        fingerprint = finding.fingerprint
        ruleID = finding.ruleID
        severity = finding.severity
        itemIDs = finding.affectedItemIDs
    }

    init(_ digest: FindingDigest) {
        fingerprint = digest.fingerprint
        ruleID = digest.ruleID
        severity = digest.severity
        itemIDs = digest.affectedItemIDs
    }
}

/// Deterministic remediation order (proposal §14): highest-risk first, always
/// the same sequence for the same findings — the user walks a queue, not a maze.
nonisolated enum FixQueuePlanner {

    /// Lower = fix earlier.
    static func priority(of finding: QueuedFinding) -> Int {
        switch (finding.ruleID, finding.severity) {
        case ("exposure.leaked", .critical): return 0    // leaked + reused
        case ("exposure.leaked", _): return 1            // leaked
        case ("quality.weak", .critical): return 2      // very weak
        case ("quality.contains-context", _): return 3
        case ("integrity.duplicate-conflict", _): return 4
        case ("quality.weak", _): return 5               // weak
        case ("reuse.exact", _): return 6
        case ("integrity.otp-invalid", _): return 7
        case ("auth.totp-missing", _), ("auth.passkey-available", _): return 8
        default: return 9                                 // cleanup
        }
    }

    /// Queue = open findings sorted by priority, then blast radius (bigger
    /// groups first), then fingerprint (total order → stable across runs).
    static func queue(findings: [QueuedFinding], dismissed: Set<String>) -> [QueuedFinding] {
        findings
            .filter { !dismissed.contains($0.fingerprint) }
            .sorted {
                let l = (priority(of: $0), -$0.itemIDs.count, $0.fingerprint)
                let r = (priority(of: $1), -$1.itemIDs.count, $1.fingerprint)
                return l < r
            }
    }
}
