import SwiftUI

/// What the lock screen is offering the user right now, derived purely from its
/// state — so the one invariant that matters can be checked without a device:
/// **the screen must never present zero ways in.**
///
/// That invariant is easy to lose. The biometric badge disables itself into a
/// spinner while a prompt is in flight, and the password field is not mounted at
/// all until biometrics have been dismissed, so a prompt that never answers
/// leaves a spinner and nothing else — indistinguishable from a hang. The one
/// state that deliberately offers nothing is the pre-probe frame (`probed ==
/// false`): it holds the launch pose the mark arrives in. Nothing about that
/// state is self-limiting, so the screen puts a stopwatch on it — the probe is
/// the very daemon round-trip that can stall, and a stalled probe with no
/// controls under it would only be the same hang one layer down.
nonisolated struct LockAffordances: Equatable {
    enum Mode { case biometric, password }

    /// Which unlock route the screen has settled on.
    var mode: Mode = .biometric
    /// True once the biometric capability snapshot has answered. Before that the
    /// screen knows neither whether to offer the badge nor whether to fall
    /// straight back to the password.
    var probed = false
    /// Biometric unlock is enrolled, available, and switched on.
    var biometricsUsable = false
    /// Deliberate lock (shake or Lock Now): the slide gate stands in for every
    /// other control until it is confirmed.
    var requireSlide = false
    /// A biometric prompt is in flight, so the badge renders as a disabled spinner.
    var authenticating = false
    /// A prompt was dismissed, could not run, or outlived its deadline.
    var dismissed = false
    /// The password-success choreography is running; the vault is already open.
    var absorbed = false

    var showsSlide: Bool { requireSlide && !absorbed }

    var showsBiometricBadge: Bool {
        probed && biometricsUsable && mode == .biometric && !requireSlide && !absorbed
    }

    /// The password field belongs on screen in password mode, and also as soon
    /// as a biometric prompt has been dismissed — `mode` stays `.biometric` in
    /// that case so the badge remains one tap from a retry. It is also the only
    /// route when biometrics can't be used at all, which is stated here rather
    /// than left to `mode` so the fallback holds even if the flip is late.
    ///
    /// `absorbed` deliberately does NOT hide it: the absorb collapses the whole
    /// chrome — field included — into the mark. Unmounting the field mid-absorb
    /// would slide it out on its own transition and shrink the measured chrome
    /// height, which is exactly what puts the mark at the screen centre.
    var showsPasswordField: Bool {
        probed && (mode == .password || dismissed || !biometricsUsable) && !requireSlide
    }

    /// True while at least one control on screen can actually be operated. The
    /// badge does not count while it spins: it is disabled.
    var offersAWayIn: Bool {
        showsSlide || showsPasswordField || (showsBiometricBadge && !authenticating)
    }
}

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

    @State private var mode: LockAffordances.Mode = .biometric
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
    /// capability pass (cold launch) prompt once, while still ignoring the `.inactive → .active`
    /// bounce the Face ID sheet itself causes.
    @State private var didAutoPrompt = false
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showRecovery = false
    @FocusState private var passwordFocused: Bool

    /// Live mirror of `scenePhase`. `@Environment` is a stored property on this
    /// struct, so an escaping `Task` closure sees the phase as it was when the
    /// closure was created — reading it after an `await` can therefore report
    /// `.background` long after the app came back (which used to skip the
    /// entrance replay and the auto-prompt for good, leaving a screen with an
    /// invisible chrome and no controls). `@State` reads through its box, so it
    /// is current whenever the closure resumes.
    @State private var phase: ScenePhase = .active

    /// Snapshot of the biometric capability. Probing means blocking IPC to the
    /// biometry and keychain daemons — never from `body`; see
    /// `VaultSession.biometricCapability`.
    @State private var capability: BiometricCapability = .unavailable
    @State private var didProbe = false
    /// Bumped on every return to `.active` to re-run the probe: biometrics can
    /// be re-enrolled (or removed) while the app sits in the background, so a
    /// snapshot from the previous foreground pass can be wrong.
    @State private var capabilityPass = 0
    /// Identifies the biometric attempt a delayed task belongs to, so a settle
    /// or deadline task from a superseded attempt can't act on the current one.
    @State private var bioAttempt = 0
    /// The prompt in flight, held so leaving the app can cancel it. Cancelling
    /// is what invalidates the `LAContext` inside `BiometricKeyStore.retrieve`,
    /// and that is the only thing that unblocks a keychain read the biometry
    /// daemon never answered — without it the next foreground would raise a
    /// second prompt on top of a thread still parked on the first.
    @State private var bioTask: Task<Void, Never>?
    /// Same idea for the entrance animation's delayed task.
    @State private var entranceAttempt = 0

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

    /// How long a biometric prompt may hold the screen before the password field
    /// is surfaced anyway. LocalAuthentication answers in well under a second
    /// when its daemon is warm; after a device wake it can take the prompt and
    /// never come back, and the badge's spinner would be the only thing on
    /// screen. Dismissal costs no attempt, so revealing the field burns nothing.
    private let bioDeadline: Duration = .seconds(10)

    /// How long the capability probe may hold the screen before the password
    /// field is mounted anyway. The probe is the same pair of daemon round-trips
    /// that can stall right after a device wake — which is when this screen
    /// appears — so waiting on it with nothing rendered underneath would just
    /// move the freeze rather than fix it. Long enough that a warm probe (well
    /// under a frame) always wins the race and the field never flashes.
    private let probeDeadline: Duration = .milliseconds(500)

    /// Set once the user slides to confirm after a deliberate lock (shake or Lock Now).
    @State private var slideConfirmed = false

    private var canUseBiometrics: Bool {
        capability.isEnrolled && capability.isAvailable && env.settings.biometricUnlockEnabled
    }

    /// After a deliberate lock (panic shake or Settings "Lock Now"), gate Face ID behind a
    /// slide so the vault can't be instantly re-opened by the owner's face still being in
    /// front of the camera the moment they chose to lock it.
    private var requireSlide: Bool { env.session.deliberatelyLocked && !slideConfirmed }

    /// Everything the screen is currently offering, in one pure value — the
    /// "never zero ways in" invariant lives on this type, not in the view.
    private var affordances: LockAffordances {
        LockAffordances(mode: mode,
                        probed: didProbe,
                        biometricsUsable: canUseBiometrics,
                        requireSlide: requireSlide,
                        authenticating: bioAuthenticating,
                        dismissed: bioDismissed,
                        absorbed: absorbed)
    }

    /// The biometric glyph occupies the mark's heart only while biometrics are
    /// the active affordance (never over the slide gate or during the absorb).
    private var showsBioBadge: Bool { affordances.showsBiometricBadge }

    private var showsPasswordSection: Bool { affordances.showsPasswordField }

    /// Sub-header under the logo — names the biometric option when it's available,
    /// otherwise points straight at the password.
    private var subtitleText: LocalizedStringKey {
        // Deliberate lock (shake / Lock Now) → explain why biometrics wait for
        // the slide instead of firing on the owner's face right away.
        if requireSlide {
            return "You locked Loox yourself, so it stays locked until you slide to confirm."
        }
        if mode == .biometric && canUseBiometrics {
            return "Sign in with \(capability.displayName) or enter your Loox Password."
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
        // The wallpaper comes first so the tap gesture below inherits a
        // full-screen hit shape (the Spacer-filled areas draw nothing of their
        // own) — same pairing as the onboarding password step, which puts its
        // page background above the gesture for the same reason.
        .themedWallpaper(env.theme.wallpaper, fallback: Color(rgb: env.theme.active.background))
        // The password field takes focus on appear, so the keyboard covers the
        // lower half from the first frame: scrolling or a tap on empty space
        // puts it away. Deliberately placed BEFORE the overlay below — the
        // overlaid "Forgot password?" is then a SIBLING of this gesture rather
        // than a child, so it keeps its own tap. The badge, the slide knob and
        // the submit arrow sit inside, where the deeper gesture wins (the
        // variant that swallowed in-row buttons was a Form-level one; see the
        // note in `ItemEditorScreen`).
        .scrollDismissesKeyboard(.immediately)
        .onTapGesture { dismissKeyboard() }
        // "Forgot password?" floats at the bottom (password mode only) so its height
        // never shifts the Spacer-centred group — the absorb lands the mark at the
        // exact centre. Keyboard avoidance still lifts it just above the keyboard.
        .overlay(alignment: .bottom) {
            if showsPasswordSection {
                Button("Forgot password?") { showRecovery = true }
                    .vaultType(.footnote)
                    .padding(.bottom, Space.s8)
                    .opacity(absorbed ? 0 : 1)
                    .transition(.opacity)
            }
        }
        .animation(.vault(.spring(response: 0.5, dampingFraction: 0.85), reduceMotion: reduceMotion), value: mode)
        .animation(.vault(.spring(response: 0.5, dampingFraction: 0.85), reduceMotion: reduceMotion), value: requireSlide)
        .animation(.vault(.spring(response: 0.5, dampingFraction: 0.85), reduceMotion: reduceMotion), value: bioDismissed)
        // The capability probe decides between the badge and the password
        // fallback, so its answer fades the affordance in instead of popping it.
        .animation(.vault(.spring(response: 0.5, dampingFraction: 0.85), reduceMotion: reduceMotion), value: didProbe)
        .sheet(isPresented: $showRecovery) { RecoveryView() }
        .analyticsScreen("lock")
        .onAppear {
            phase = scenePhase
            playEntrance()
        }
        .task(id: capabilityPass) {
            await probeBiometricsAndAutoPrompt()
        }
        .onChange(of: scenePhase) { _, newPhase in
            phase = newPhase
            switch newPhase {
            case .background:
                didBackground = true
                // A prompt cannot outlive the app leaving: retire the attempt,
                // cancel its read and drop the spinner, or the badge comes back
                // disabled with the password field still unmounted — a screen
                // with no controls — over a read nothing will ever answer.
                bioAttempt &+= 1
                bioAuthenticating = false
                bioTask?.cancel()
                bioTask = nil
                // Snap back (no animation — we're off-screen) to the centred pose
                // so the switcher snapshot matches the privacy shield and the
                // return to the foreground replays the run-up arrival.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { entered = false }
            case .active:
                playEntrance()
                // Re-probe, then auto-prompt from there — enrolment can change
                // while the app is backgrounded.
                capabilityPass &+= 1
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
                    BiometricBadge(capability: capability, authenticating: bioAuthenticating) {
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

    /// Resign the first responder so the keyboard hides (on scroll / tap-outside).
    private func dismissKeyboard() {
        PlatformAppearance.dismissKeyboard()
    }

    // MARK: - Choreography

    /// Run the mark up from the centre pose into its resting spot. A short beat
    /// first, so the eye registers the centred (privacy/launch) frame it left.
    ///
    /// The chrome is invisible but still hit-testable while `entered` is false,
    /// so an arrival that never plays reads as a frozen screen. Every early exit
    /// here therefore leaves the replay to the next `.active` — and reads the
    /// live `phase` mirror, because the captured `scenePhase` could still say
    /// `.background` at the very moment the scene became active, which skipped
    /// the replay permanently.
    private func playEntrance() {
        guard !entered, !absorbed else { return }
        if reduceMotion { entered = true; return }
        // Mounting mid-background (Immediately auto-lock fires as the app leaves)
        // would burn the run-up off-screen and resume on the resting pose — hold
        // the centred pose instead; the `.active` scene-phase change replays it.
        guard phase != .background else { return }
        entranceAttempt &+= 1
        let attempt = entranceAttempt
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard attempt == entranceAttempt, !entered, !absorbed, phase != .background else { return }
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

    /// Take the capability snapshot off the main actor, then decide whether this
    /// pass owes an auto-prompt. The decision waits for the snapshot because
    /// both halves of it (is biometry available, is a key enrolled) are blocking
    /// daemon round-trips that must not run inside `body`.
    private func probeBiometricsAndAutoPrompt() async {
        // The stored setting is a local read and it alone can rule biometrics
        // OUT, so a user who never turned them on reaches the password field
        // without waiting on a daemon at all.
        guard env.settings.biometricUnlockEnabled else {
            capability = .unavailable
            didProbe = true
            mode = .password
            return
        }
        // Mount the fallback if the probe outstays its welcome. It is marked
        // dismissed rather than merely probed, so a late answer fades the badge
        // in BESIDE the field instead of pulling the field back out from under
        // a user who has already started typing.
        let reveal = Task {
            try? await Task.sleep(for: probeDeadline)
            guard !Task.isCancelled, !didProbe else { return }
            bioDismissed = true
            didProbe = true
        }
        let snapshot = await env.session.biometricCapability()
        reveal.cancel()
        capability = snapshot
        didProbe = true
        // After a shake-lock, wait for the slide; otherwise auto-prompt as usual.
        guard !requireSlide else { return }
        guard canUseBiometrics else {
            mode = .password
            return
        }
        // Trigger on a genuine return from background OR on the first pass after
        // a cold launch — but never on the `.inactive → .active` bounce the Face
        // ID sheet closing produces (by then `didAutoPrompt` is already true).
        if didBackground {
            didBackground = false
            triggerBiometric()
        } else if !didAutoPrompt {
            triggerBiometric()
        }
    }

    /// Confirm the post-shake slide, then proceed to the normal unlock affordance.
    private func confirmSlide() {
        slideConfirmed = true
        if canUseBiometrics { triggerBiometric() } else { mode = .password }
    }

    /// Auto-prompt biometrics — only while active, in biometric mode, and under the attempt
    /// cap. Sets `bioAuthenticating` synchronously so two near-simultaneous calls (e.g. the
    /// capability pass + a badge tap) can't launch a second prompt during the settle delay.
    /// The single entry point for every prompt (auto + badge tap).
    private func triggerBiometric() {
        guard !requireSlide, mode == .biometric, phase == .active, canUseBiometrics,
              !bioAuthenticating, bioFailCount < maxBioAttempts else { return }
        bioAuthenticating = true
        didAutoPrompt = true
        bioAttempt &+= 1
        let attempt = bioAttempt
        bioTask = Task {
            // Let the foreground transition settle so the system prompt isn't auto-dismissed.
            try? await Task.sleep(for: .milliseconds(250))
            guard attempt == bioAttempt, bioAuthenticating else { return }
            // The scene can leave `.active` during that beat — a wake that never
            // reached the user, another app taking over. Prompting then is
            // pointless, and leaving the flag set would strand the screen on a
            // disabled spinner with the password field still unmounted.
            guard phase == .active else {
                bioAuthenticating = false
                return
            }
            startBiometricDeadline(attempt: attempt)
            await runBiometric(attempt: attempt)
            if attempt == bioAttempt { bioTask = nil }
        }
    }

    /// Surface the password field if the prompt has not answered in time.
    /// `bioAuthenticating` is deliberately left alone: the system sheet may well
    /// still be up, and clearing it would let a second prompt launch on top of
    /// it. Revealing the field is enough — the screen has a way in again.
    private func startBiometricDeadline(attempt: Int) {
        Task {
            try? await Task.sleep(for: bioDeadline)
            guard attempt == bioAttempt, bioAuthenticating, !bioDismissed else { return }
            bioDismissed = true
        }
    }

    private func runBiometric(attempt: Int) async {
        // Only the current attempt may clear the flag: a call that was abandoned
        // at a background must not switch off the spinner of the prompt that
        // replaced it.
        defer { if attempt == bioAttempt { bioAuthenticating = false } }
        do {
            try await env.session.unlockWithBiometrics()
            AnalyticsEngine.shared.log(.vaultUnlocked(method: "biometric"))
            onUnlockSuccess(false)
            // Success → session state flips to unlocked → this view is replaced.
        } catch {
            // A retired attempt (the app left and cancelled its read) must not
            // spend an attempt or retire the affordance on behalf of the prompt
            // that replaced it.
            guard attempt == bioAttempt else { return }
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
