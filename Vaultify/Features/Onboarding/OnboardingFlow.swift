import SwiftUI

/// Drives the first-run sequence: welcome → master password → Emergency Kit →
/// biometrics → done. `createVault` unlocks the session; the app stays in the
/// onboarding route until `settings.onboardingCompleted` flips at the end.
struct OnboardingFlow: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .welcome
    @State private var recoveryKey = ""
    /// Captured at the name step so the Emergency Kit PDF can print "Created for {name}"
    /// and remind which iCloud account holds the synced vault.
    @State private var userName = ""
    @State private var userEmail = ""
    /// Restore chooser (bottom sheet) presentation + the method it resolves to.
    @State private var showRestoreSheet = false
    @State private var restoreMethod: JoinVaultFlow.Method = .qr

    /// Id of the default "My Vault" Space seeded in `createVault`, threaded into the
    /// item seeds so they get a home (otherwise they'd land in Unfiled).
    @State private var defaultFolderId: String?

    enum Step: Equatable { case welcome, join, create, name, emergencyKit, theme, biometric, done }

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                WelcomeLandingView(onContinue: { step = .create },
                                   onRestore: CloudSyncService.isConfigured ? { showRestoreSheet = true } : nil)
            case .join:
                JoinVaultFlow(method: restoreMethod, onCancel: { step = .welcome })
            case .create:
                // Native nav chrome for the standard iOS back (to welcome).
                NavigationStack {
                    CreateMasterPasswordView(onSubmit: createVault)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button { step = .welcome } label: { Image(systemName: "chevron.backward") }
                                    .accessibilityLabel(Text("Back"))
                            }
                        }
                }
                .tint(Color.primary)
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
                navStep(back: { step = .name }) {
                    EmergencyKitView(recoveryKey: recoveryKey,
                                     ownerName: userName,
                                     iCloudAccount: userEmail) { step = .theme }
                }
            case .theme:
                navStep(back: { step = .emergencyKit }) {
                    ChooseThemeView(selection: Binding(get: { env.theme.appearanceMode }, set: { env.theme.appearanceMode = $0 })) {
                        step = BiometricAuth.isAvailable ? .biometric : .done
                    }
                }
            case .biometric:
                EnableBiometricView(onEnable: enableBiometric) { step = .done }
            case .done:
                OnboardingDoneStep { env.settings.onboardingCompleted = true }
            }
        }
        .animation(.vault(.smooth(duration: 0.35), reduceMotion: reduceMotion), value: step)
        // Restore chooser: a bottom sheet over the welcome screen. Picking a method
        // dismisses it and advances to the join flow at that method.
        .sheet(isPresented: $showRestoreSheet) {
            RestoreMethodSheet(
                onQR: { restoreMethod = .qr; showRestoreSheet = false; step = .join },
                onRecovery: { restoreMethod = .recovery; showRestoreSheet = false; step = .join },
                onStartFresh: { showRestoreSheet = false; step = .create })
        }
        // Onboarding has no MainTabView, so it hosts its own copy-toast overlay
        // (Emergency Kit's Copy button would otherwise give only a haptic).
        .overlay(alignment: .bottom) { CopyToastOverlay() }
        .animation(.vault(.spring(duration: 0.3), reduceMotion: reduceMotion), value: env.clipboard.recentCopyLabel)
        .task(id: step) {
            if step == .emergencyKit, recoveryKey.isEmpty {
                recoveryKey = (try? await env.session.generateRecoveryKit()) ?? ""
            }
        }
        // Grouped-gray canvas so the white cards/fields of the form steps read
        // (Apple grouped style). Welcome and Done paint their own white page
        // over this, so only the form steps show the gray.
        .themedWallpaper(env.theme.wallpaper, fallback: Color(rgb: env.theme.active.groupedBackground))
    }

    /// Wraps a step in native nav chrome with a standard iOS back control.
    /// (The name step has no back: the vault already exists at that point.)
    private func navStep<Content: View>(back: @escaping () -> Void,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        NavigationStack {
            content()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: back) { Image(systemName: "chevron.backward") }
                            .accessibilityLabel(Text("Back"))
                    }
                }
        }
        .tint(Color.primary)
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

private struct OnboardingDoneStep: View {
    let onFinish: () -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var launch = LooxLaunchController()
    /// Text and CTA step aside for the launch burst; the animation stays.
    @State private var contentHidden = false

    /// Recap what onboarding actually set up — mention biometrics only when the
    /// user turned them on, so the "Not now" path stays truthful.
    private var recap: LocalizedStringKey {
        env.settings.biometricUnlockEnabled
            ? "Vault created, Emergency Kit saved, \(BiometricAuth.displayName) on. Add your first item to get started."
            : "Vault created and Emergency Kit saved. Add your first item to get started."
    }

    var body: some View {
        ZStack {
            // The color the launch bloom floods, so the hand-off is seamless.
            Color(.systemBackground).ignoresSafeArea()
            OnboardingScrollingStep {
                VStack(spacing: 0) {
                    Spacer(minLength: Space.s8)
                    // Same brand animation as the welcome landing; its circle-burst
                    // launch plays when the user opens the app.
                    LooxCloudAnimationView(controller: launch)
                        .frame(width: 220, height: 220 * 0.82)
                    OnboardingStepHeader(
                        "You’re all set",
                        subtitle: recap)
                    .opacity(contentHidden ? 0 : 1)
                    Spacer(minLength: Space.s6)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: press) {
                Text("Open Loox").frame(maxWidth: .infinity)
            }
            .buttonStyle(.themedProminent).controlSize(.large)
            .disabled(launch.phase != .idle)
            .opacity(contentHidden ? 0 : 1)
            .padding(.horizontal, Space.s6).padding(.bottom, Space.gutter)
        }
    }

    /// Welcome-style launch choreography: the burst blooms over the screen and
    /// the app crossfades in behind the flood.
    private func press() {
        guard launch.phase == .idle else { return }
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.25)) { contentHidden = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { onFinish() }
            return
        }
        launch.press()
        withAnimation(.easeOut(duration: 0.25).delay(0.35)) { contentHidden = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { onFinish() }
    }
}
