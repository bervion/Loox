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
    /// How many analyzed passwords landed in each 5-step grade — the strength
    /// bar's distribution. Grades absent from the vault are absent from the map.
    var grades: [PasswordGrade: Int] = [:]

    static let empty = VaultHealth()
    var issueCount: Int { weak.count + reused.count + pwned.count + missing2FA.count }
}

/// Local (offline) password analysis: weak, reused, 2FA-missing detection; health
/// score and overall strength.
nonisolated enum PasswordAudit {
    static func analyze(_ items: [VaultItem]) -> VaultHealth {
        let withPasswords: [(VaultItem, String)] = items.compactMap { item in
            // Resolver-scoped pool: developer tokens and other non-auditable
            // secrets never enter grading or breach hashing. Extra-protected
            // passwords are sealed ciphertext — grading or breach-hashing the
            // payload would produce nonsense results.
            guard ItemCapabilityResolver.capabilities(for: item).passwordAudit,
                  let field = item.passwordField, !field.value.isEmpty, !field.isExtraProtected
            else { return nil }
            return (item, field.value)
        }

        // 2FA analysis runs across all (non-trashed) hygiene-eligible items
        // regardless of password
        let missing2FA = items
            .filter { !$0.isTrashed && $0.totpField == nil
                && ItemCapabilityResolver.capabilities(for: $0).loginHygieneAudit }
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
        var grades: [PasswordGrade: Int] = [:]
        var strengthSum: Double = 0

        for (item, password) in withPasswords {
            // One engine pass per password: the 5-step grade feeds the strength
            // bar's distribution, and the legacy 3-tier mapping below is exactly
            // `PasswordStrength.evaluate`, so weak/score semantics are unchanged.
            let grade = PasswordStrengthEngine.evaluate(password).grade
            grades[grade, default: 0] += 1
            let strength: PasswordStrength = switch grade {
            case .veryWeak, .weak: .weak
            case .fair: .medium
            case .strong, .excellent: .strong
            }
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
            overallStrength: overallStrength,
            grades: grades
        )
    }

    static func issue(_ item: VaultItem, kind: VaultIssue.Kind, detail: String? = nil) -> VaultIssue {
        VaultIssue(itemID: item.id,
                   itemTitle: item.title.isEmpty ? appString("Untitled") : item.title,
                   category: item.category, kind: kind, detail: detail)
    }
}
