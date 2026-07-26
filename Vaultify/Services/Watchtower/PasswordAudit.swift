import Foundation

/// A security finding about a specific item.
nonisolated struct VaultIssue: Identifiable, Sendable {
    enum Kind: Sendable { case weak, reused, pwned, missing2FA }
    let id = UUID()
    let itemID: String
    let itemTitle: String
    let category: ItemCategory
    let kind: Kind
    var detail: String?
}

/// Aggregated vault health returned by `PasswordAudit.analyze`.
///
/// Two distinct scores:
/// - `score`: health score (0-100), penalises weak + reused passwords.
/// - `overallStrength`: mean normalised per-item password strength (0-100),
///    computed from entropy independent of duplication penalties.
///   These are intentionally separate — an item can have a strong unique password
///   (high strength, no health penalty) vs. a strong but reused one (high strength,
///   health penalty applied).
nonisolated struct VaultHealth: Sendable {
    var analyzedCount: Int = 0
    var weak: [VaultIssue] = []
    var reused: [VaultIssue] = []
    var pwned: [VaultIssue] = []
    /// Items matched to 2FA-capable services that have no TOTP field.
    var missing2FA: [VaultIssue] = []
    /// Health score 0-100: penalises weak + reused items.
    var score: Int = 100
    /// Mean per-item password strength 0-100 (entropy-based, ignores duplicates).
    var overallStrength: Int = 100

    static let empty = VaultHealth()
    var issueCount: Int { weak.count + reused.count + pwned.count + missing2FA.count }
}

/// Local (offline) password analysis: weak, reused, 2FA-missing detection; health
/// score and overall strength.
nonisolated enum PasswordAudit {
    static func analyze(_ items: [VaultItem]) -> VaultHealth {
        let withPasswords: [(VaultItem, String)] = items.compactMap { item in
            // Extra-protected passwords are sealed ciphertext — grading or breach-
            // hashing the payload would produce nonsense results.
            guard let field = item.passwordField, !field.value.isEmpty, !field.isExtraProtected
            else { return nil }
            return (item, field.value)
        }

        // 2FA analysis runs across all (non-trashed) login items regardless of password
        let missing2FA = items
            .filter { !$0.isTrashed && $0.category == .login && $0.totpField == nil }
            .filter { TwoFactorCatalog.supports2FA($0) }
            .map { issue($0, kind: .missing2FA) }

        guard !withPasswords.isEmpty else {
            return VaultHealth(analyzedCount: 0, missing2FA: missing2FA,
                               score: 100, overallStrength: 100)
        }

        var counts: [String: Int] = [:]
        for (_, password) in withPasswords { counts[password, default: 0] += 1 }

        var weak: [VaultIssue] = []
        var reused: [VaultIssue] = []
        var strengthSum: Double = 0

        for (item, password) in withPasswords {
            let strength = PasswordStrength.evaluate(password)
            // Normalise: weak→33, medium→66, strong→100 (matches fraction * 100)
            strengthSum += strength.fraction * 100

            if strength == .weak {
                weak.append(issue(item, kind: .weak))
            }
            if counts[password, default: 0] > 1 {
                reused.append(issue(item, kind: .reused, detail: appString("Used by \(counts[password]!) items")))
            }
        }

        let penalty = Double(weak.count + reused.count) / Double(withPasswords.count)
        let score = max(0, Int((1 - min(penalty, 1)) * 100))
        let overallStrength = max(0, min(100, Int(strengthSum / Double(withPasswords.count))))

        return VaultHealth(
            analyzedCount: withPasswords.count,
            weak: weak,
            reused: reused,
            pwned: [],
            missing2FA: missing2FA,
            score: score,
            overallStrength: overallStrength
        )
    }

    static func issue(_ item: VaultItem, kind: VaultIssue.Kind, detail: String? = nil) -> VaultIssue {
        VaultIssue(itemID: item.id,
                   itemTitle: item.title.isEmpty ? "Untitled" : item.title,
                   category: item.category, kind: kind, detail: detail)
    }
}
