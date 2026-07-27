import SwiftUI

/// Optional step offering biometric unlock when the device supports it.
struct EnableBiometricView: View {
    let onEnable: () -> Void
    let onSkip: () -> Void
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        // Scroll-safe: a fixed Spacer-centered VStack clips at large Dynamic Type /
        // on SE, since neither header ever scrolls (see OnboardingScrollingStep).
        OnboardingScrollingStep {
            VStack(spacing: 0) {
                Spacer(minLength: Space.s8)
                // Brand dots mark looping the spark against the system biometry
                // glyph (Face ID / Touch ID), like the profile avatar invitation.
                LooxDotsAvatar(size: 120, animatesCamera: true,
                               loopSystemGlyph: BiometricAuth.systemImage)
                    .padding(.bottom, Space.s4)
                OnboardingStepHeader(
                    "Enable \(BiometricAuth.displayName)",
                    subtitle: "Unlock your vault quickly with \(BiometricAuth.displayName). Your master password still works anytime.")
                Spacer(minLength: Space.s6)
                // Action hierarchy: ONE filled primary, and a quiet text-only
                // secondary. `BrandCapsuleCTA` carries its own horizontal /
                // bottom padding, so its bottom inset is the gap to "Not now".
                VStack(spacing: 0) {
                    BrandCapsuleCTA(title: "Enable \(BiometricAuth.displayName)",
                                    action: onEnable)

                    // Deliberately unfilled: skipping is the low-emphasis path,
                    // so it reads as a text button, not a second capsule. It still
                    // takes the TEXT-LINK colour, not `.secondary` — this is the
                    // only way past a step that has no back and no toolbar skip,
                    // and grey body copy does not read as something you can tap.
                    // The explicit frame keeps the 44pt hit target a bare `Button`
                    // label would not guarantee.
                    Button(action: onSkip) {
                        Text("Not now")
                            .vaultType(.body).fontWeight(.medium)
                            .themedForeground(.accentText)
                            .frame(maxWidth: .infinity, minHeight: Metric.hitMin)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Space.s6)
                }
                .padding(.bottom, Space.s6)
            }
        }
        // No form fields or grouped cards on this step — plain white canvas
        // per the design convention (gray is reserved for form screens).
        .background(Color(rgb: env.theme.active.background).ignoresSafeArea())
    }
}
