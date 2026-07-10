import SwiftUI

/// Drives the first-run sequence: welcome → master password → Emergency Kit →
/// biometrics → done. `createVault` unlocks the session; the app stays in the
/// onboarding route until `settings.onboardingCompleted` flips at the end.
struct OnboardingFlow: View {
    @Environment(AppEnvironment.self) private var env
    @State private var step: Step = .welcome
    @State private var recoveryKey = ""
    /// Captured at the name step so the Emergency Kit PDF can print "Created for {name}"
    /// and remind which iCloud account holds the synced vault.
    @State private var userName = ""
    @State private var userEmail = ""

    /// Id of the default "My Vault" Space seeded in `createVault`, threaded into the
    /// item seeds so they get a home (otherwise they'd land in Unfiled).
    @State private var defaultFolderId: String?

    enum Step: Equatable { case welcome, join, create, name, emergencyKit, theme, biometric, done }

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                WelcomeStep(onContinue: { step = .create },
                            onJoin: CloudSyncService.isConfigured ? { step = .join } : nil)
            case .join:
                JoinVaultFlow(onCancel: { step = .welcome })
            case .create:
                CreateMasterPasswordView(onSubmit: createVault)
            case .name:
                NameStepView { name, email in
                    userName = name
                    userEmail = email
                    let starterTag = appString("Starter Kit")
                    seedIdentity(name, email: email, tag: starterTag)
                    seedLooxAccount(name: name, email: email, tag: starterTag)
                    step = .emergencyKit
                }
            case .emergencyKit:
                EmergencyKitView(recoveryKey: recoveryKey,
                                 ownerName: userName,
                                 iCloudAccount: userEmail) { step = .theme }
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
            // Turn on iCloud sync by default for new vaults — the Emergency Kit / recovery
            // path restores from the synced copy, so a fresh user gets multi-device recovery
            // without hunting through Settings. No-op unless the build is iCloud-configured
            // (`CloudSyncService.isConfigured`), so it never touches an unprovisioned container.
            env.settings.iCloudSyncEnabled = true
            // Seed a default Space ("My Vault") so new items have a home; the user
            // can rename it or add more later. Best-effort — never block setup.
            // Keep the id so the item seeds file into it (else they'd be Unfiled).
            defaultFolderId = try? env.repository.addFolder(name: appString("My Vault"), icon: Icons.lockFill, color: .blue)
            step = .name
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Seed the mandatory default identity from the onboarding display name. Best-effort,
    /// like the "My Vault" folder seed. Skips if an identity already exists (e.g. re-running
    /// onboarding after a recovery reset), so it never creates a duplicate default.
    private func seedIdentity(_ displayName: String, email: String, tag: String) {
        guard env.repository.activeIdentities.isEmpty else { return }
        let note = appString("Welcome to Loox. This is your identity. It autofills your name, email, and details into forms. Everything stays encrypted on this device; edit or add more anytime.")
        var identity = IdentitySeed.make(
            displayName: displayName, email: email, fallback: appString("Me"),
            note: note, tag: tag)
        // File the seed into "My Vault" (matches the editor's default) so it isn't Unfiled.
        identity.folderId = defaultFolderId ?? env.repository.primarySpaceId
        try? env.repository.add(identity)
    }

    /// Seed a "Loox Account (Name)" login holding the user's email + an importance note.
    /// No website — its title carries "Loox", which the row avatar renders as the app icon.
    /// Best-effort; the email field is added only when one was entered.
    private func seedLooxAccount(name: String, email: String, tag: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty ? appString("Me") : trimmedName
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        var fields: [DynamicField] = []
        if !trimmedEmail.isEmpty {
            fields.append(DynamicField(label: "Email", kind: .email, value: trimmedEmail))
        }
        fields.append(DynamicField(
            label: "Note", kind: .multiline,
            value: appString("This is your Loox account, the identity for this vault. Keep the email safe; you may need it to set up sync or recover access.")))

        let item = VaultItem(category: .login,
                             title: "\(appString("Loox Account")) (\(displayName))",
                             folderId: defaultFolderId ?? env.repository.primarySpaceId,
                             fields: fields, tags: [tag])
        try? env.repository.add(item)
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
    /// Present when this build can join an existing vault over iCloud (sync configured).
    var onJoin: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Center the hero on tall phones, but let it scroll on short screens /
            // large Dynamic Type so the CTA never clips (minHeight fills the viewport;
            // the flanking Spacers center when it fits and collapse when it doesn't).
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: Space.s8)
                        // The brand mark used on splash/lock, so the first-run screen
                        // opens with the same Loox identity instead of a generic glyph.
                        BrandLogoMark.hero
                        OnboardingStepHeader(
                            "Password Manager",
                            subtitle: "A private, zero-backend vault. Your secrets stay encrypted on-device and never leave unprotected.",
                            // Content-heavy hero (logo + 3 cards): the compact ramp
                            // (screenTitle + subhead) reads cleaner than the largeTitle hero.
                            style: .compact)

                        VStack(spacing: Space.s3) {
                            FeatureCard(icon: .polaris(Icons.lockFill), title: "End-to-end encryption",
                                        detail: "Argon2id + AES-256-GCM, keys stay only on this device.")
                            FeatureCard(icon: .polaris(Icons.creditCard), title: "Passwords, cards, notes & more",
                                        detail: "Store essentials, generate strong passwords, and use one-time codes.")
                            FeatureCard(icon: .system("faceid"), title: "Unlock with Face ID / Touch ID",
                                        detail: "Fast biometric access protected by the Secure Enclave.")
                        }
                        .padding(.top, Space.s7)
                        .padding(.horizontal, Space.s6)
                        Spacer(minLength: Space.s6)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            VStack(spacing: Space.s3) {
                Button(action: onContinue) {
                    Text("Get Started").frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedProminent)
                .controlSize(.large)

                if let onJoin {
                    Button(action: onJoin) {
                        Text("Sync from another device").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, Space.s6)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s6)
        }
        .background(alignment: .top) { WelcomeBackdrop() }
    }
}

/// Icon source for a `FeatureCard`. Polaris SVG is the house set; `.system` is a
/// deliberate SF Symbol exception for glyphs Polaris doesn't ship — currently only
/// Apple's `faceid` mark, the platform-authentic cue for biometric unlock.
private enum FeatureIcon {
    case polaris(String)
    case system(String)
}

/// One feature presented as a standalone card: an accent-tinted icon tile beside a
/// title + supporting line. Cards stack with a gap (vs. a single divided list) for a
/// lighter, more premium first-run hero.
private struct FeatureCard: View {
    let icon: FeatureIcon
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        HStack(alignment: .center, spacing: Space.s4) {
            iconView
                // True accent (stays blue in dark mode, unlike the global control tint).
                .foregroundStyle(VaultColors.accent)
                .frame(width: Metric.controlLarge, height: Metric.controlLarge)
                .background(Color(rgb: env.theme.active.accentSoft),
                            in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(title.inAppLocalized).vaultType(.callout).fontWeight(.semibold)
                Text(detail.inAppLocalized).vaultType(.subhead).themedForeground(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        // Borderless white card lifted by a soft ambient shadow only — the light
        // theme's surface matches the page (both 0xFFFFFF), so the shadow (not a
        // hairline) does the separation; dark themes separate by surface contrast.
        .background(VaultColors.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .elevation(.level2)
    }

    @ViewBuilder private var iconView: some View {
        switch icon {
        case .polaris(let name):
            PolarisIcon(name, size: Metric.iconUtility)
        case .system(let name):
            // Decorative — the card title carries the accessibility label (matches PolarisIcon).
            Image(systemName: name)
                .font(.system(size: Metric.iconUtility))
                .accessibilityHidden(true)
        }
    }
}

/// Subtle brand halo behind the hero: a soft accent tint at the top that fades to
/// clear. A per-screen accent (kept legible in light + dark), not the decorative
/// wallpaper engine — which stays gated off.
private struct WelcomeBackdrop: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        LinearGradient(
            colors: [Color(rgb: env.theme.active.accent, opacity: 0.10), .clear],
            startPoint: .top,
            endPoint: .center)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct OnboardingDoneStep: View {
    let onFinish: () -> Void
    @Environment(AppEnvironment.self) private var env

    /// Recap what onboarding actually set up — mention biometrics only when the
    /// user turned them on, so the "Not now" path stays truthful.
    private var recap: LocalizedStringKey {
        env.settings.biometricUnlockEnabled
            ? "Vault created, Emergency Kit saved, \(BiometricAuth.displayName) on. Add your first item to get started."
            : "Vault created and Emergency Kit saved. Add your first item to get started."
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            PolarisIcon(Icons.checkCircle, size: 72).foregroundStyle(VaultColors.strengthStrong)
            OnboardingStepHeader(
                "You’re all set",
                subtitle: recap)
            Spacer()
            Button(action: onFinish) {
                Text("Open Loox").frame(maxWidth: .infinity)
            }
            .buttonStyle(.themedProminent).controlSize(.large)
            .padding(.horizontal, Space.s6).padding(.bottom, Space.s6)
        }
    }
}
