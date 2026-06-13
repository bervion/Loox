import Foundation

/// A security finding about a specific item.
nonisolated struct VaultIssue: Identifiable, Sendable {
    enum Kind: Sendable { case weak, reused, pwned }
    let id = UUID()
    let itemID: String
    let itemTitle: String
    let category: ItemCategory
    let kind: Kind
    var detail: String?
}

/// Aggregated vault health.
nonisolated struct VaultHealth: Sendable {
    var analyzedCount: Int = 0
    var weak: [VaultIssue] = []
    var reused: [VaultIssue] = []
    var pwned: [VaultIssue] = []
    var score: Int = 100

    static let empty = VaultHealth()
    var issueCount: Int { weak.count + reused.count + pwned.count }
}

/// Local (offline) password analysis: weak + reused detection and a health score.
nonisolated enum PasswordAudit {
    static func analyze(_ items: [VaultItem]) -> VaultHealth {
        let withPasswords: [(VaultItem, String)] = items.compactMap { item in
            guard let value = item.passwordField?.value, !value.isEmpty else { return nil }
            return (item, value)
        }
        guard !withPasswords.isEmpty else { return VaultHealth(analyzedCount: 0, score: 100) }

        var counts: [String: Int] = [:]
        for (_, password) in withPasswords { counts[password, default: 0] += 1 }

        var weak: [VaultIssue] = []
        var reused: [VaultIssue] = []
        for (item, password) in withPasswords {
            if PasswordStrength.evaluate(password) == .weak {
                weak.append(issue(item, kind: .weak))
            }
            if counts[password, default: 0] > 1 {
                reused.append(issue(item, kind: .reused, detail: "Used by \(counts[password]!) items"))
            }
        }

        let penalty = Double(weak.count + reused.count) / Double(withPasswords.count)
        let score = max(0, Int((1 - min(penalty, 1)) * 100))
        return VaultHealth(analyzedCount: withPasswords.count, weak: weak, reused: reused, pwned: [], score: score)
    }

    static func issue(_ item: VaultItem, kind: VaultIssue.Kind, detail: String? = nil) -> VaultIssue {
        VaultIssue(itemID: item.id,
                   itemTitle: item.title.isEmpty ? "Untitled" : item.title,
                   category: item.category, kind: kind, detail: detail)
    }
}
