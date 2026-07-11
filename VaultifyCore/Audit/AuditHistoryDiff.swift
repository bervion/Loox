import Foundation

/// Pure diff between two audit reports for the history screen: which findings
/// were resolved (or stopped being monitored) and which are new. Works on
/// sealed payload digests only — no sensitive values are ever compared.
nonisolated enum AuditHistoryDiff {

    struct RuleCount: Identifiable, Sendable, Equatable {
        let ruleID: String
        let count: Int
        var id: String { ruleID }
    }

    struct Diff: Sendable, Equatable {
        let resolved: [RuleCount]
        let noLongerMonitored: [RuleCount]
        let new: [RuleCount]
        var isEmpty: Bool { resolved.isEmpty && noLongerMonitored.isEmpty && new.isEmpty }
    }

    /// - Parameter currentItemIDs: live vault item IDs, used to tell a real fix
    ///   from a deleted item ("No longer monitored", never "fixed").
    static func diff(previous: AuditReportPayload, current: AuditReportPayload,
                     currentItemIDs: Set<String>) -> Diff {
        let currentFPs = Set(current.findings.map(\.fingerprint))
        let previousFPs = Set(previous.findings.map(\.fingerprint))

        var resolved: [String: Int] = [:]
        var unmonitored: [String: Int] = [:]
        for digest in previous.findings where !currentFPs.contains(digest.fingerprint) {
            let gone = digest.affectedItemIDs.allSatisfy { !currentItemIDs.contains($0) }
            if gone { unmonitored[digest.ruleID, default: 0] += 1 }
            else { resolved[digest.ruleID, default: 0] += 1 }
        }
        var added: [String: Int] = [:]
        for digest in current.findings where !previousFPs.contains(digest.fingerprint) {
            added[digest.ruleID, default: 0] += 1
        }

        func rows(_ dict: [String: Int]) -> [RuleCount] {
            dict.map { RuleCount(ruleID: $0.key, count: $0.value) }
                .sorted { $0.count > $1.count }
        }
        return Diff(resolved: rows(resolved), noLongerMonitored: rows(unmonitored),
                    new: rows(added))
    }
}
