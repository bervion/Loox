import Foundation

/// Coarse password-strength classification driven by an entropy estimate.
nonisolated enum PasswordStrength: Int, Sendable, Comparable, CaseIterable {
    case weak, medium, strong

    static func < (lhs: PasswordStrength, rhs: PasswordStrength) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: LocalizedStringResource {
        let base: LocalizedStringResource = switch self {
        case .weak: "Weak"
        case .medium: "Fair"
        case .strong: "Strong"
        }
        return base.inAppLocalized
    }

    /// 0…1 fraction for progress bars.
    var fraction: Double {
        switch self {
        case .weak: return 0.33
        case .medium: return 0.66
        case .strong: return 1.0
        }
    }

    /// Estimate entropy (bits) from character-class diversity and length, with a
    /// discount for heavy repetition. Classified <50 weak / 50–100 medium / >100 strong.
    static func entropyBits(_ password: String) -> Double {
        guard !password.isEmpty else { return 0 }
        let chars = Set(password)
        var pool = 0
        if chars.contains(where: \.isLowercase) { pool += 26 }
        if chars.contains(where: \.isUppercase) { pool += 26 }
        if chars.contains(where: \.isNumber) { pool += 10 }
        if chars.contains(where: { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }) { pool += 33 }
        if chars.contains(where: \.isWhitespace) { pool += 1 }
        let repetitionFactor = Double(chars.count) / Double(password.count)
        let base = Double(password.count) * log2(Double(max(pool, 1)))
        return base * (0.55 + 0.45 * repetitionFactor)
    }

    static func evaluate(_ password: String) -> PasswordStrength {
        let bits = entropyBits(password)
        if bits < 50 { return .weak }
        if bits < 100 { return .medium }
        return .strong
    }
}
