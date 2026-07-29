import SwiftUI

/// Animated strength bar + label + entropy estimate.
struct PasswordStrengthMeter: View {
    let password: String
    /// Label shown before any input (call sites reword it, e.g. "Choose a strong password").
    var emptyLabel: LocalizedStringKey = "Enter a master password"
    @Environment(AppEnvironment.self) private var env

    private var result: StrengthResult { PasswordStrengthEngine.evaluate(password) }
    /// The meter's BAR and LABEL stay on the coarse three-step scale on purpose — this view is
    /// feedback while typing, where a label that keeps changing is noise. Only the colour is
    /// shared with the graded read-out so the two can never disagree about red vs green.
    private var strength: PasswordStrength {
        switch result.grade {
        case .veryWeak, .weak: return .weak
        case .fair: return .medium
        case .strong, .excellent: return .strong
        }
    }
    /// Bits from the SAME estimate that drives the label (log2 of guesses) —
    /// the old character-class entropy would contradict the pattern-aware grade.
    private var bits: Int { Int(result.log10Guesses * 3.3219) }
    private var color: Color { VaultColors.strength(grade: result.grade) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(VaultColors.fill)
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * (password.isEmpty ? 0 : strength.fraction))
                }
            }
            .frame(height: 6)
            .animation(.smooth, value: strength)

            HStack {
                Group {
                    if password.isEmpty {
                        Text(emptyLabel)
                    } else {
                        Text(String(localized: strength.title))
                    }
                }
                .vaultType(.caption)
                .foregroundStyle(password.isEmpty ? env.theme.active.color(.secondary) : color)
                Spacer()
                if !password.isEmpty {
                    Text("\(bits) bits")
                        .vaultType(.caption)
                        .monospacedDigit()
                        .themedForeground(.secondary)
                }
            }
        }
    }
}
