import SwiftUI

/// Drives the first-run sequence: welcome → master password → Emergency Kit →
/// biometrics → done. `createVault` unlocks the session; the app stays in the
/// onboarding route until `settings.onboardingCompleted` flips at the end.
struct OnboardingFlow: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .welcome
    @State private var recoveryKey = ""
    /// Set when generating the recovery key fails. Without it an empty key parked the
    /// Emergency Kit step on a spinner forever: the step has no back control and its CTA
    /// is disabled while the key is empty, so the run was unescapable.
    @State private var recoveryKeyError: String?
    /// Bumped by "Try again" to re-drive the generation task.
    @State private var recoveryKeyAttempt = 0
    /// Captured at the name step so the Emergency Kit PDF can print "Created for {name}"
    /// and remind which iCloud account holds the synced vault.
    @State private var userName = ""
    @State private var userEmail = ""
    /// Restore chooser (bottom sheet) presentation + the method it resolves to.
    @State private var showRestoreSheet = false
    @State private var restoreMethod: JoinVaultFlow.Method = .qr

    /// Id of the default "My Space" Space seeded in `createVault`, threaded into the
    /// item seeds so they get a home (otherwise they'd land in Unfiled).
    @State private var defaultFolderId: String?

    enum Step: Equatable { case welcome, join, create, name, emergencyKit, theme, biometric, done }

    /// `.task(id:)` identity for recovery-key generation: the step plus the retry count,
    /// so tapping "Try again" restarts the task without leaving and re-entering the step.
    private struct TaskKey: Equatable { let step: Step; let attempt: Int }

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
                        .platformNavigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .platformTopBarLeading) {
                                Button { step = .welcome } label: {
                                    VaultIcon(Icons.chevronLeft, size: Metric.iconInline)
                                }
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
                    step = .emergencyKit
                }
            case .emergencyKit:
                // No back: the identity seeds ran when the name step completed.
                EmergencyKitView(recoveryKey: recoveryKey,
                                 ownerName: userName,
                                 iCloudAccount: userEmail,
                                 keyError: recoveryKeyError,
                                 onRetryKey: { recoveryKeyAttempt += 1 }) { step = .theme }
            case .theme:
                navStep(back: { step = .emergencyKit }) {
                    ChooseThemeView(selection: Binding(
                        get: { env.theme.appearanceMode },
                        set: { newMode in
                            env.theme.appearanceMode = newMode
                            // Live from the moment of the tap (see `ThemeStore.forceLight`):
                            // Light stays light, Dark/System take over immediately.
                            env.markAppearanceChosen()
                        }
                    )) {
                        // Commit whatever is currently shown (Light, unless the user
                        // already tapped a card) as the explicit choice before leaving.
                        // Without this, an untouched pick would only release the gate
                        // later (onboarding completion) and could resolve to a
                        // different appearance (e.g. system-dark) right then — the
                        // same kind of flip this gate exists to prevent.
                        env.theme.appearanceMode = env.theme.appearanceMode
                        env.markAppearanceChosen()
                        step = BiometricAuth.isAvailable ? .biometric : .done
                    }
                }
            case .biometric:
                EnableBiometricView(onEnable: enableBiometric, onSkip: { step = .done })
            case .done:
                OnboardingDoneStep {
                    AnalyticsEngine.shared.log(.tutorialComplete)
                    env.settings.onboardingCompleted = true
                }
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
        // Keyed on the retry counter too, so "Try again" re-runs generation.
        .task(id: TaskKey(step: step, attempt: recoveryKeyAttempt)) {
            guard step == .emergencyKit, recoveryKey.isEmpty else { return }
            recoveryKeyError = nil
            do {
                recoveryKey = try await env.session.generateRecoveryKit()
            } catch {
                // Real handling, not `try?`: the kit step cannot be left or skipped, so a
                // swallowed failure was a dead end rather than a degraded state. Nothing
                // is pushed to iCloud here — the envelope upload is the consent step's
                // job, and it awaits its own result (see `EmergencyKitView`).
                recoveryKeyError = appString("Couldn’t create your recovery key. Please try again.")
            }
        }
        // Grouped-gray canvas so the white cards/fields of the form steps read
        // (Apple grouped style). Welcome and Done paint their own white page
        // over this, so only the form steps show the gray.
        .themedWallpaper(env.theme.wallpaper, fallback: Color(rgb: env.theme.active.groupedBackground))
        .onAppear { AnalyticsEngine.shared.log(.tutorialBegin) }
    }

    /// Wraps a step in native nav chrome with a standard iOS back control.
    /// (The name step has no back: the vault already exists at that point.)
    private func navStep<Content: View>(back: @escaping () -> Void,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        NavigationStack {
            content()
                .platformNavigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .platformTopBarLeading) {
                        Button(action: back) { VaultIcon(Icons.chevronLeft, size: Metric.iconInline) }
                            .accessibilityLabel(Text("Back"))
                    }
                }
        }
        .tint(Color.primary)
    }

    private func createVault(_ password: String) async -> String? {
        do {
            try await env.session.createVault(masterPassword: password)
            AnalyticsEngine.shared.log(.vaultCreated)
            // iCloud sync stays OFF here. Creating a vault is not consent to upload it, and
            // the seeds below post `.vaultLocalMutation`, which arms `SyncCoordinator`'s
            // three-second debounce — turning the flag on at this point put the first
            // CloudKit write on the name step, before any choice was offered. The question
            // is asked on the Emergency Kit step, which owns the recovery story.

            // Seed a default Space ("My Space") so new items have a home; the user
            // can rename it or add more later. Best-effort — never block setup.
            // Keep the id so the item seeds file into it (else they'd be Unfiled).
            // The stored name must be one of `SeedSpaceName.historical` or the
            // seed dedupe pass stops recognising it.
            defaultFolderId = try? env.repository.addFolder(name: SeedSpaceName.current, icon: IconCatalog.seedSpaceIcon, color: .blue)
            step = .name
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Seed the mandatory default identity from the onboarding display name. Best-effort,
    /// like the "My Space" folder seed. Skips if an identity already exists (e.g. re-running
    /// onboarding after a recovery reset), so it never creates a duplicate default.
    private func seedIdentity(_ displayName: String, email: String, tag: String) {
        guard env.repository.activeIdentities.isEmpty else { return }
        let note = appString("Welcome to Loox. This is your identity. It autofills your name, email, and details into forms. Everything stays encrypted on this device; edit or add more anytime.")
        var identity = IdentitySeed.make(
            displayName: displayName, email: email, fallback: appString("Me"),
            note: note, tag: tag)
        // File the seed into the seeded Space (matches the editor's default) so it isn't Unfiled.
        identity.folderId = defaultFolderId ?? env.repository.primarySpaceId
        // Seeded, not user-created — keep it out of the item_created stream.
        AnalyticsEngine.shared.runSuppressed { try? env.repository.add(identity) }
    }

    /// Advances only on a real enrolment. Swallowing the error and moving on left the
    /// user believing Face ID was armed when the key was never stored, so the next launch
    /// asked for the master password with no explanation.
    private func enableBiometric() async -> String? {
        do {
            try await env.session.enableBiometricUnlock()
            step = .done
            return nil
        } catch {
            return error.localizedDescription
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
            Color.platformBackground.ignoresSafeArea()
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
            // Same pinned capsule as every other onboarding step; it steps aside
            // with the rest of the content when the launch burst starts.
            BrandCapsuleCTA(title: "Open Loox", enabled: launch.phase == .idle, action: press)
                .opacity(contentHidden ? 0 : 1)
        }
    }

    /// Welcome-style launch choreography: the burst blooms over the screen and
    /// the app crossfades in behind the flood.
    private func press() {
        guard launch.phase == .idle else { return }
        // Reduce Motion asked for no choreography, so there is nothing to wait for —
        // the old quarter-second timer was a delay with no animation behind it.
        if reduceMotion {
            onFinish()
            return
        }
        launch.press()
        withAnimation(.easeOut(duration: 0.25).delay(0.35)) { contentHidden = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { onFinish() }
    }
}
