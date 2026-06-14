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
            Text("Enable \(BiometricAuth.displayName)")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .padding(.top, 16)
            Text("Unlock your vault quickly with \(BiometricAuth.displayName). Your master password still works anytime.")
                .font(.body)
                .themedForeground(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 8)
            Spacer()
            VStack(spacing: 12) {
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
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}
