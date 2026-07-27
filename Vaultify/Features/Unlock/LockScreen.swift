import SwiftUI

/// Master-password / biometric unlock gate shown whenever the vault is locked.
///
/// Choreography — the logo is the single continuous element between the launch
/// screen, the privacy shield, this gate, and the unlock wink:
/// - **Arrival** — the mark starts at the exact screen centre (where the launch
///   screen and privacy shield leave it) and runs up into its resting spot as the
///   title/subtitle fade in underneath.
/// - **Biometric** — the Face ID / Touch ID glyph sits at the mark's heart (the
///   sparkle's spot); tapping the mark retries. After repeated failures the
///   password field animates in below.
/// - **Password success** — the chrome (title, subtitle, field) is absorbed into
///   the mark while it glides back to centre, handing off to the wink seamlessly.
struct LockScreen: View {
    /// Fired on a successful unlock (biometric or password) so the parent can
    /// play the memoji success wink before the vault appears. `fromCenter` is
    /// true when the absorb choreography already returned the logo to the
    /// screen centre (manual password path), so the wink starts there.
    var onUnlockSuccess: (_ fromCenter: Bool) -> Void = { _ in }
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Mode { case biometric, password }
    @State private var mode: Mode = .biometric
    @State private var bioAuthenticating = false
    @State private var bioFailCount = 0
    /// Set once a biometric prompt has been dismissed (or could not run).
    /// Dismissing costs no attempt, so the badge stays — but the password field
    /// comes along with it, or the badge would be the only affordance left on
    /// screen and a user who cancels would have no way in.
    @State private var bioDismissed = false
    /// True once the app has actually gone to `.background` — so we only auto-prompt Face ID on
    /// a real return to the foreground, not on the `.inactive → .active` bounce the Face ID
    /// system sheet itself produces (which previously spammed prompts).
    @State private var didBackground = false
    /// Whether we've auto-prompted Face ID yet for this lock-screen appearance. Lets the first
    /// `.active` (cold launch — `onAppear` often fires before the scene is active) prompt once,
    /// while still ignoring the `.inactive → .active` bounce the Face ID sheet itself causes.
    @State private var didAutoPrompt = false
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showRecovery = false
    @FocusState private var passwordFocused: Bool

    // MARK: Choreography state

    /// False while the mark rests at the screen centre (launch/privacy pose);
    /// flips true to run it up into the resting spot as the chrome fades in.
    /// Reset on every background so the return replays the arrival.
    @State private var entered = false
    /// Password-success absorb: the chrome collapses into the mark while the
    /// group returns to centre, then the session flips underneath the wink.
    @State private var absorbed = false
    /// Measured height of everything below the logo — offsetting the group by
    /// half of it puts the mark at the exact centre without hardcoding text
    /// heights (Dynamic Type / locale safe).
    @State private var chromeHeight: CGFloat = 0
    @State private var chromeMeasured = false

    private var chromeCollapsed: Bool { !entered || absorbed }

    /// Biometric attempts (auto-prompt + taps) before falling back to the password field.
    private let maxBioAttempts = 3

    /// Set once the user slides to confirm after a deliberate lock (shake or Lock Now).
    @State private var slideConfirmed = false

    private var canUseBiometrics: Bool {
        env.session.biometricEnrolled && env.settings.biometricUnlockEnabled && BiometricAuth.isAvailable
    }

    /// After a deliberate lock (panic shake or Settings "Lock Now"), gate Face ID behind a
    /// slide so the vault can't be instantly re-opened by the owner's face still being in
    /// front of the camera the moment they chose to lock it.
    private var requireSlide: Bool { env.session.deliberatelyLocked && !slideConfirmed }

    /// The biometric glyph occupies the mark's heart only while biometrics are
    /// the active affordance (never over the slide gate or during the absorb).
    private var showsBioBadge: Bool {
        mode == .biometric && !requireSlide && !absorbed
    }

    /// The password field belongs on screen in password mode, and also as soon
    /// as a biometric prompt has been dismissed — `mode` stays `.biometric` in
    /// that case so the badge remains one tap from a retry.
    private var showsPasswordSection: Bool {
        mode == .password || bioDismissed
    }

    /// Sub-header under the logo — names the biometric option when it's available,
    /// otherwise points straight at the password.
    private var subtitleText: LocalizedStringKey {
        // Deliberate lock (shake / Lock Now) → explain why biometrics wait for
        // the slide instead of firing on the owner's face right away.
        if requireSlide {
            return "You locked Loox yourself, so it stays locked until you slide to confirm."
        }
        if mode == .biometric && canUseBiometrics {
            return "Sign in with \(BiometricAuth.displayName) or enter your Loox Password."
        }
        return "Enter your Loox Password to unlock."
    }

    var body: some View {
        // Scroll-safe: at accessibility text sizes on an SE-width screen the fixed
        // Spacer-centered stack below (logo + title/subtitle + password field) can
        // outgrow the screen and clip. `OnboardingScrollingStep` (shared with the
        // onboarding flow) keeps the exact same Spacer-centered layout when it fits
        // and only becomes a real ScrollView once it doesn't — so default text sizes
        // render byte-identical to the un-wrapped VStack, while AX-XXL gets a safety
        // net. Purely presentational: no change to biometric/slide/attempt logic below.
        OnboardingScrollingStep {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    logoView
                    chrome
                }
                // Half the chrome height re-centres the MARK (not the group) while
                // the chrome is hidden — the launch/privacy pose. Hidden until the
                // first measurement so the mark never flashes at the lifted spot.
                .offset(y: chromeCollapsed ? chromeHeight / 2 : 0)
                .opacity(chromeMeasured ? 1 : 0)
                .padding(.horizontal, Space.s8)

                Spacer()
            }
        } // OnboardingScrollingStep
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Centre in the full screen (not just the safe area) so the logo lines up with the
        // LaunchScreen logo — otherwise the larger top inset (Dynamic Island) drops it ~12pt,
        // making it visibly jump down at the launch hand-off. `.container` keeps keyboard
        // avoidance intact for password mode.
        .ignoresSafeArea(.container, edges: .vertical)
        // "Forgot password?" floats at the bottom (password mode only) so its height
        // never shifts the Spacer-centred group — the absorb lands the mark at the
        // exact centre. Keyboard avoidance still lifts it just above the keyboard.
        .overlay(alignment: .bottom) {
            if showsPasswordSection, !requireSlide {
                Button("Forgot password?") { showRecovery = true }
                    .vaultType(.footnote)
                    .padding(.bottom, Space.s8)
                    .opacity(absorbed ? 0 : 1)
                    .transition(.opacity)
            }
        }
        .themedWallpaper(env.theme.wallpaper, fallback: Color(rgb: env.theme.active.background))
        .animation(.vault(.spring(response: 0.5, dampingFraction: 0.85), reduceMotion: reduceMotion), value: mode)
        .animation(.vault(.spring(response: 0.5, dampingFraction: 0.85), reduceMotion: reduceMotion), value: requireSlide)
        .animation(.vault(.spring(response: 0.5, dampingFraction: 0.85), reduceMotion: reduceMotion), value: bioDismissed)
        .sheet(isPresented: $showRecovery) { RecoveryView() }
        .analyticsScreen("lock")
        .onAppear {
            playEntrance()
            // After a shake-lock, wait for the slide; otherwise auto-prompt as usual.
            guard !requireSlide else { return }
            if !canUseBiometrics { mode = .password }
            triggerBiometric()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                didBackground = true
                // Snap back (no animation — we're off-screen) to the centred pose
                // so the switcher snapshot matches the privacy shield and the
                // return to the foreground replays the run-up arrival.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { entered = false }
            case .active:
                playEntrance()
                // Trigger on a genuine return from background OR on the first activation after
                // a cold launch — but never on the `.inactive → .active` bounce the Face ID
                // sheet closing produces (by then `didAutoPrompt` is already true).
                if didBackground {
                    didBackground = false
                    triggerBiometric()
                } else if !didAutoPrompt {
                    triggerBiometric()
                }
            default:
                break
            }
        }
    }

    // MARK: - Pieces

    /// The breathing mark. In biometric mode the Face ID / Touch ID glyph takes
    /// the sparkle's spot at its heart, and the whole mark is the retry target.
    private var logoView: some View {
        LooxLogoBreatheView(ready: false, showSparkle: !showsBioBadge)
            .frame(width: 132, height: 132)
            .overlay {
                if showsBioBadge {
                    BiometricBadge(authenticating: bioAuthenticating) {
                        triggerBiometric()
                    }
                    .transition(.opacity)
                }
            }
    }

    /// Everything below the mark — fades in on arrival and is absorbed into the
    /// mark on password success. Measured as one block so the centring offset
    /// tracks Dynamic Type and locale for free.
    private var chrome: some View {
        VStack(spacing: Space.s7) {
            VStack(spacing: Space.s2) {
                Text("Unlock your vault")
                    .vaultType(.screenTitle)
                Text(subtitleText)
                    .vaultType(.subhead)
                    .themedForeground(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if requireSlide {
                // Shake-locked → confirm by sliding before any Face ID prompt.
                SlideToUnlock { confirmSlide() }
                    .transition(.opacity)
            } else if showsPasswordSection {
                passwordSection
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.top, Space.s4)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            chromeHeight = height
            chromeMeasured = true
        }
        .opacity(chromeCollapsed ? 0 : 1)
        .scaleEffect(absorbed ? 0.35 : 1, anchor: .top)
    }

    private var passwordSection: some View {
        VStack(spacing: Space.s2) {
            LockPasswordField(text: $password, busy: busy, focus: $passwordFocused) {
                Task { await unlock() }
            }
            if let error {
                Text(error).vaultType(.footnote).foregroundStyle(VaultColors.strengthWeak)
            }
        }
    }

    // MARK: - Choreography

    /// Run the mark up from the centre pose into its resting spot. A short beat
    /// first, so the eye registers the centred (privacy/launch) frame it left.
    private func playEntrance() {
        guard !entered, !absorbed else { return }
        if reduceMotion { entered = true; return }
        // Mounting mid-background (Immediately auto-lock fires as the app leaves)
        // would burn the run-up off-screen and resume on the resting pose — hold
        // the centred pose instead; the `.active` scene-phase change replays it.
        guard scenePhase != .background else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !entered, !absorbed, scenePhase != .background else { return }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { entered = true }
        }
    }

    /// Password-success absorb: dismiss the keyboard, pull the chrome into the
    /// mark, and glide the mark back to the screen centre — then let the caller
    /// flip the session so the wink picks up from exactly there.
    private func playAbsorb() async {
        guard !reduceMotion else { return }
        passwordFocused = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { absorbed = true }
        try? await Task.sleep(for: .milliseconds(480))
    }

    // MARK: - Biometrics

    /// Auto-prompt biometrics — only while active, in biometric mode, and under the attempt
    /// cap. Sets `bioAuthenticating` synchronously so two near-simultaneous calls (e.g. the
    /// onAppear + scene-phase paths) can't launch a second prompt during the settle delay.
    /// The single entry point for every prompt (auto + badge tap).
    /// Confirm the post-shake slide, then proceed to the normal unlock affordance.
    private func confirmSlide() {
        slideConfirmed = true
        if canUseBiometrics { triggerBiometric() } else { mode = .password }
    }

    private func triggerBiometric() {
        guard !requireSlide, mode == .biometric, scenePhase == .active, canUseBiometrics,
              !bioAuthenticating, bioFailCount < maxBioAttempts else { return }
        bioAuthenticating = true
        didAutoPrompt = true
        Task {
            // Let the foreground transition settle so the system prompt isn't auto-dismissed.
            try? await Task.sleep(for: .milliseconds(250))
            await runBiometric()
        }
    }

    private func runBiometric() async {
        defer { bioAuthenticating = false }
        do {
            try await env.session.unlockWithBiometrics()
            AnalyticsEngine.shared.log(.vaultUnlocked(method: "biometric"))
            onUnlockSuccess(false)
            // Success → session state flips to unlocked → this view is replaced.
        } catch {
            handleBiometricFailure(error)
        }
    }

    /// A biometric failure is not one thing. Only a rejected face or a lockout
    /// is an attempt; a dismissed prompt costs nothing, and a key the system
    /// invalidated is a dead affordance rather than a failure at all.
    private func handleBiometricFailure(_ error: Error) {
        // `.biometryCurrentSet` invalidates the stored key the moment the
        // enrolled biometrics change. No retry can ever succeed, so retire the
        // affordance instead of counting attempts against it.
        if case BiometricKeyStore.Failure.invalidated = error {
            env.session.disableBiometricUnlock()
            showPasswordMode()
            return
        }
        let outcome = BiometricAuth.classify(error)
        guard outcome == .failed || outcome == .lockout else {
            // Dismissed, or biometry could not run. Neither proves anything, so
            // no attempt is burnt, no error haptic, and no failure analytics.
            bioDismissed = true
            return
        }
        AnalyticsEngine.shared.log(.vaultUnlockFailed(method: "biometric"))
        bioFailCount += 1
        Haptics.error()
        // A lockout holds until the device passcode is entered, so any further
        // prompt is guaranteed to fail — hand straight over to the password.
        if outcome == .lockout || bioFailCount >= maxBioAttempts {
            showPasswordMode()
        }
    }

    private func showPasswordMode() {
        withAnimation(.vault(.spring(response: 0.5, dampingFraction: 0.85),
                             reduceMotion: reduceMotion)) { mode = .password }
    }

    // MARK: - Password

    private func unlock() async {
        guard !password.isEmpty, !busy else { return }
        busy = true; error = nil
        do {
            // The absorb plays between "password proven" and the session flip, so
            // the wink takes over from a mark already resting at the centre.
            try await env.session.unlock(password: password) { await playAbsorb() }
            AnalyticsEngine.shared.log(.vaultUnlocked(method: "password"))
            onUnlockSuccess(!reduceMotion)
            password = ""
        } catch {
            AnalyticsEngine.shared.log(.vaultUnlockFailed(method: "password"))
            self.error = error.localizedDescription
            Haptics.error()
            env.theme.morphMesh()
        }
        busy = false
    }
}
