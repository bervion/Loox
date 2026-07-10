import SwiftUI

/// Accent-tinted biometric badge for the lock screen, sitting at the logo's bottom-right
/// corner. Shows the biometric glyph (Face ID / Touch ID) when idle and a circular progress
/// while authenticating; reverts to the glyph on failure. Tapping retries authentication.
///
/// Uses the system biometric SF Symbol (the recognised affordance) — Polaris ships no
/// biometric glyph, so this is a deliberate exception to the Polaris-only icon rule.
struct BiometricBadge: View {
    let authenticating: Bool
    let action: () -> Void

    @Environment(AppEnvironment.self) private var env

    private let side: CGFloat = 40

    var body: some View {
        Button(action: action) {
            ZStack {
                // App-icon-style badge: an elevated surface (white in light, dark in dark) with
                // the glyph/progress in the control tint (accent in light, white in dark) so it
                // stays legible without a glaring white square on dark.
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(VaultColors.surface)

                if authenticating {
                    ProgressView()
                        .controlSize(.small)
                        .tint(env.theme.uiTint)
                } else {
                    Image(systemName: BiometricAuth.systemImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(env.theme.uiTint)
                }
            }
            .frame(width: side, height: side)
            // Invisible padded hit area to the 44pt minimum — the visual badge stays
            // sized to match the logo's corner (same technique as `RevealableSecureField`).
            .contentShape(Rectangle().inset(by: -(Metric.hitMin - side) / 2))
            .elevation(.level2)
        }
        .buttonStyle(.plain)
        .disabled(authenticating)
        .animation(.easeInOut(duration: 0.2), value: authenticating)
        .accessibilityLabel(Text("Unlock with \(BiometricAuth.displayName)"))
    }
}
