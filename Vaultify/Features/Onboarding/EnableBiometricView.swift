import SwiftUI

/// Optional step offering biometric unlock when the device supports it.
struct EnableBiometricView: View {
    let onEnable: () -> Void
    let onSkip: () -> Void

    var body: some View {
        // Scroll-safe: a fixed Spacer-centered VStack clips at large Dynamic Type /
        // on SE, since neither header ever scrolls (see OnboardingScrollingStep).
        OnboardingScrollingStep {
            VStack(spacing: 0) {
                Spacer(minLength: Space.s8)
                PolarisIcon(BiometricAuth.iconAsset, size: 72)
                    // True accent (live theme preset) — `Color.accentColor` reads the
                    // static asset-catalog tint and would ignore the user's chosen preset.
                    .foregroundStyle(VaultColors.accent)
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
    }
}
