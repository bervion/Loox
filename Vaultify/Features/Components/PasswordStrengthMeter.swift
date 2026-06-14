import SwiftUI

/// Animated strength bar + label + entropy estimate.
struct PasswordStrengthMeter: View {
    let password: String

    private var strength: PasswordStrength { PasswordStrength.evaluate(password) }
    private var bits: Int { Int(PasswordStrength.entropyBits(password)) }
    private var color: Color { VaultColors.strength(strength) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * (password.isEmpty ? 0 : strength.fraction))
                }
            }
            .frame(height: 6)
            .animation(.smooth, value: strength)

            HStack {
                Text(password.isEmpty ? "Enter a master password" : String(localized: strength.title))
                    .font(.caption)
                    .foregroundStyle(password.isEmpty ? .secondary : color)
                Spacer()
                if !password.isEmpty {
                    Text("\(bits) bits")
                        .font(.caption2.monospacedDigit())
                        .themedForeground(.secondary)
                }
            }
        }
    }
}
