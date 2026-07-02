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
        // Onboarding has no MainTabView, so it hosts its own copy-toast overlay
        // (Emergency Kit's Copy button would otherwise give only a haptic).
        .overlay(alignment: .bottom) { CopyToastOverlay() }
        .animation(.spring(duration: 0.3), value: env.clipboard.recentCopyLabel)
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
            _ = try? env.repository.addFolder(name: appString("My Vault"), icon: Icons.lockFill, color: .blue)
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
            // The brand mark used on splash/lock, so the first-run screen opens
            // with the same Loox identity instead of a generic glyph.
            BrandLogoMark(size: 92, shadowRadius: 14, shadowY: 7)
            OnboardingStepHeader(
                "Loox Password",
                subtitle: "A zero-backend password manager. Your secrets are encrypted on-device and never leave it unencrypted.")

            VStack(spacing: 0) {
                FeatureRow(icon: Icons.lockFill, title: "End-to-end encryption",
                           detail: "Argon2id + AES-256-GCM, keys held only on this device.")
                Divider().padding(.leading, 64)
                FeatureRow(icon: Icons.key, title: "Logins, cards, notes & more",
                           detail: "Strong generator, one-time codes, and security checks.")
                Divider().padding(.leading, 64)
                FeatureRow(icon: Icons.person, title: "Unlock with Face ID / Touch ID",
                           detail: "Fast biometric access backed by the Secure Enclave.")
            }
            .background(VaultColors.surface)
            .vaultCornerRadius(Radius.lg)
            .padding(.top, Space.s8)
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
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            PolarisIcon(icon, size: 18)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color(rgb: env.theme.active.accentSoft),
                            in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title.inAppLocalized).font(.headline)
                Text(detail.inAppLocalized).font(.subheadline).themedForeground(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.s3)
    }
}

private struct OnboardingDoneStep: View {
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            PolarisIcon(Icons.checkCircle, size: 72).foregroundStyle(VaultColors.strengthStrong)
            OnboardingStepHeader(
                "You’re all set",
                subtitle: "Your vault is ready. Add your first item to get started.")
            Spacer()
            Button(action: onFinish) {
                Text("Open Loox").frame(maxWidth: .infinity)
            }
            .buttonStyle(.themedProminent).controlSize(.large)
            .padding(.horizontal, Space.s6).padding(.bottom, Space.s6)
        }
    }
}
