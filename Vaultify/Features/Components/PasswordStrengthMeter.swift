import SwiftUI

/// Animated strength bar + label + entropy estimate.
struct PasswordStrengthMeter: View {
    let password: String
    /// Label shown before any input (call sites reword it, e.g. "Choose a strong password").
    var emptyLabel: LocalizedStringKey = "Enter a master password"
    @Environment(AppEnvironment.self) private var env

    private var strength: PasswordStrength { PasswordStrength.evaluate(password) }
    private var bits: Int { Int(PasswordStrength.entropyBits(password)) }
    private var color: Color { VaultColors.strength(strength) }

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
