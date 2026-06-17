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
                // Fixed white square (slight corner) for every theme — the icon/progress is
                // accent-tinted on top, like a small app-icon badge.
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(.white)

                if authenticating {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color(rgb: env.theme.active.accent))
                } else {
                    Image(systemName: BiometricAuth.systemImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(Color(rgb: env.theme.active.accent))
                }
            }
            .frame(width: side, height: side)
            .elevation(.level2)
        }
        .buttonStyle(.plain)
        .disabled(authenticating)
        .animation(.easeInOut(duration: 0.2), value: authenticating)
        .accessibilityLabel(Text("Unlock with \(BiometricAuth.displayName)"))
    }
}
