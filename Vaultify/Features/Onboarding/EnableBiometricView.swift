import SwiftUI

/// Optional step offering biometric unlock when the device supports it.
struct EnableBiometricView: View {
    let onEnable: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            PolarisIcon(BiometricAuth.iconAsset, size: 72)
                .foregroundStyle(Color.accentColor)
            OnboardingStepHeader(
                "Enable \(BiometricAuth.displayName)",
                subtitle: "Unlock your vault quickly with \(BiometricAuth.displayName). Your master password still works anytime.")
            Spacer()
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
