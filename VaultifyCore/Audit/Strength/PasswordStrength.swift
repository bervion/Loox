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

    /// Delegates to the pattern-aware engine so "Password1!" no longer scores
    /// high on character classes alone. The legacy 3-tier API stays for UI
    /// consumers; audit rules use `PasswordGrade` directly for finer severity.
    static func evaluate(_ password: String) -> PasswordStrength {
        switch PasswordStrengthEngine.evaluate(password).grade {
        case .veryWeak, .weak: return .weak
        case .fair: return .medium
        case .strong, .excellent: return .strong
        }
    }
}

extension VaultItem {
    /// True only when the item has a real (non-empty) password that scores weak.
    /// An empty or absent password is NOT weak — there's nothing to strengthen yet, so
    /// it must not raise a "weak password" flag on Home / Watchtower. (`evaluate("")`
    /// returns `.weak` for zero entropy, hence the explicit empty check here.)
    nonisolated var hasWeakPassword: Bool {
        guard let value = passwordField?.value, !value.isEmpty else { return false }
        return PasswordStrength.evaluate(value) == .weak
    }
}
