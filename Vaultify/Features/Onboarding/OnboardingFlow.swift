import SwiftUI

/// Drives the first-run sequence: welcome → master password → Emergency Kit →
/// biometrics → done. `createVault` unlocks the session; the app stays in the
/// onboarding route until `settings.onboardingCompleted` flips at the end.
struct OnboardingFlow: View {
    @Environment(AppEnvironment.self) private var env
    @State private var step: Step = .welcome
    @State private var recoveryKey = ""

    enum Step: Equatable { case welcome, create, name, emergencyKit, theme, biometric, done }

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                WelcomeStep { step = .create }
            case .create:
                CreateMasterPasswordView(onSubmit: createVault)
            case .name:
                NameStepView { displayName in
                    seedIdentity(displayName)
                    step = .emergencyKit
                }
            case .emergencyKit:
                EmergencyKitView(recoveryKey: recoveryKey) { step = .theme }
            case .theme:
                ChooseThemeView(selection: Binding(get: { env.theme.appearanceMode }, set: { env.theme.appearanceMode = $0 })) {
                    step = BiometricAuth.isAvailable ? .biometric : .done
                }
            case .biometric:
                EnableBiometricView(onEnable: enableBiometric) { step = .done }
            case .done:
                OnboardingDoneStep { env.settings.onboardingCompleted = true }
            }
        }
        .animation(.smooth(duration: 0.35), value: step)
        .task(id: step) {
            if step == .emergencyKit, recoveryKey.isEmpty {
                recoveryKey = (try? await env.session.generateRecoveryKit()) ?? ""
            }
        }
        .themedWallpaper(env.theme.wallpaper, fallback: Color(rgb: env.theme.active.background))
    }

    private func createVault(_ password: String) async -> String? {
        do {
            try await env.session.createVault(masterPassword: password)
            // Seed a default Space ("My Vault") so new items have a home; the user
            // can rename it or add more later. Best-effort — never block setup.
            try? env.repository.addFolder(name: appString("My Vault"), icon: Icons.lockFill, color: .blue)
            step = .name
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Seed the mandatory default identity from the onboarding display name. Best-effort,
    /// like the "My Vault" folder seed. Skips if an identity already exists (e.g. re-running
    /// onboarding after a recovery reset), so it never creates a duplicate default.
    private func seedIdentity(_ displayName: String) {
        guard env.repository.activeIdentities.isEmpty else { return }
        try? env.repository.add(IdentitySeed.make(displayName: displayName, fallback: appString("Me")))
    }

    private func enableBiometric() {
        Task {
            try? await env.session.enableBiometricUnlock()
            step = .done
        }
    }
}

private struct WelcomeStep: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            PolarisIcon(Icons.shield, size: 72)
                .foregroundStyle(Color.accentColor)
            Text("Vaultify")
                .font(.largeTitle.bold())
                .padding(.top, Space.gutter)
            Text("A zero-backend password manager. Your secrets are encrypted on-device and never leave it unencrypted.")
                .font(.body)
                .themedForeground(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.s8)
                .padding(.top, Space.s2)

            VStack(alignment: .leading, spacing: 18) {
                FeatureRow(icon: Icons.lockFill, title: "End-to-end encryption",
                           detail: "Argon2id + AES-256-GCM, keys held only on this device.")
                FeatureRow(icon: Icons.key, title: "Logins, cards, notes & more",
                           detail: "Strong generator, one-time codes, and security checks.")
                FeatureRow(icon: Icons.person, title: "Unlock with Face ID / Touch ID",
                           detail: "Fast biometric access backed by the Secure Enclave.")
            }
            .padding(.top, 36)
            .padding(.horizontal, Space.s6)

            Spacer()
            Button(action: onContinue) {
                Text("Get Started").frame(maxWidth: .infinity)
            }
            .buttonStyle(.themedProminent)
            .controlSize(.large)
            .padding(.horizontal, Space.s6)
            .padding(.bottom, Space.s6)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PolarisIcon(icon, size: Metric.iconUtility).foregroundStyle(Color.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.inAppLocalized).font(.headline)
                Text(detail.inAppLocalized).font(.subheadline).themedForeground(.secondary)
            }
        }
    }
}

private struct OnboardingDoneStep: View {
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            PolarisIcon(Icons.checkCircle, size: 72).foregroundStyle(VaultColors.strengthStrong)
            Text("You’re all set")
                .font(.largeTitle.bold())
                .padding(.top, Space.gutter)
            Text("Your vault is ready. Add your first item to get started.")
                .font(.body).themedForeground(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, Space.s8).padding(.top, Space.s2)
            Spacer()
            Button(action: onFinish) {
                Text("Open Vaultify").frame(maxWidth: .infinity)
            }
            .buttonStyle(.themedProminent).controlSize(.large)
            .padding(.horizontal, Space.s6).padding(.bottom, Space.s6)
        }
    }
}
