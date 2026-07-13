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
                VStack(spacing: Space.s3) {
                    Button(action: onEnable) {
                        Text("Enable \(BiometricAuth.displayName)").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.themedProminent)
                    .controlSize(.large)

                    Button(action: onSkip) {
                        Text("Not now").frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                }
                .padding(.horizontal, Space.s6)
                .padding(.bottom, Space.s6)
            }
        }
        // No form fields or grouped cards on this step — plain white canvas
        // per the design convention (gray is reserved for form screens).
        .background(Color(rgb: env.theme.active.background).ignoresSafeArea())
    }
}
