import Foundation

/// Five-tier pattern-aware grade (replaces the coarse weak/medium/strong for
/// audit purposes; the legacy `PasswordStrength` maps onto this).
nonisolated enum PasswordGrade: Int, Sendable, Comparable, CaseIterable, Codable {
    case veryWeak, weak, fair, strong, excellent

    static func < (lhs: PasswordGrade, rhs: PasswordGrade) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: LocalizedStringResource {
        let base: LocalizedStringResource = switch self {
        case .veryWeak: "Very weak"
        case .weak: "Weak"
        case .fair: "Fair"
        case .strong: "Strong"
        case .excellent: "Excellent"
        }
        return base.inAppLocalized
    }

    /// 0…1 fraction for strength bars.
    var fraction: Double {
        switch self {
        case .veryWeak: return 0.2
        case .weak: return 0.4
        case .fair: return 0.6
        case .strong: return 0.8
        case .excellent: return 1.0
        }
    }
}

/// Vault-local personal context an attacker targeting THIS user would try
/// first. Only data already inside the vault item — never collected elsewhere.
nonisolated struct StrengthContext: Sendable {
    var usernames: [String] = []
    var emailLocalParts: [String] = []
    var domains: [String] = []
    var itemTitle: String? = nil

    static let empty = StrengthContext()

    /// Lowercased terms (length ≥ 3) a context-aware matcher should treat as known.
    var terms: [String] {
        var raw = usernames + emailLocalParts + domains
        if let itemTitle { raw.append(itemTitle) }
        var out: Set<String> = []
        for value in raw {
            let lower = value.lowercased()
            // Whole value, plus alphanumeric tokens ("john.doe" → john, doe;
            // "github.com" → github).
            out.insert(lower)
            for token in lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                out.insert(String(token))
            }
        }
        // URL plumbing noise must not become "personal context".
        let stopwords: Set<String> = ["www", "com", "net", "org", "http", "https", "accounts"]
        return out.filter { $0.count >= 3 && !stopwords.contains($0) }
    }
}

nonisolated struct StrengthResult: Sendable {
    let grade: PasswordGrade
    /// Total attack cost estimate, log10(guesses).
    let log10Guesses: Double
    /// Labels of the pattern segments on the cheapest attack path
    /// ("dictionary", "sequence", "context", …) — for detail UI and tests.
    let matchedPatterns: [String]
}

/// One candidate pattern segment found by a matcher, over `chars[start...end]`.
nonisolated struct StrengthMatch: Sendable {
    let start: Int
    let end: Int      // inclusive
    let log10Guesses: Double
    let label: String
}
