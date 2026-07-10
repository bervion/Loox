import SwiftUI

/// Master-password / biometric unlock gate shown whenever the vault is locked.
///
/// Two modes:
/// - **Biometric** — logo only, centred, with a Face ID / Touch ID badge at its bottom-right
///   corner (progress while authenticating, reverts on failure). After repeated failures it
///   falls back to password entry.
/// - **Password** — the logo eases up to make room for the password field (inline accent
///   login arrow; the keyboard's Go key also submits) and a "Forgot password?" link pinned
///   to the bottom of the screen.
struct LockScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Mode { case biometric, password }
    @State private var mode: Mode = .biometric
    @State private var bioAuthenticating = false
    @State private var bioFailCount = 0
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
        // Spacer-centered stack below (logo + title/subtitle + password field/forgot
        // link) can outgrow the screen and clip. `OnboardingScrollingStep` (shared with
        // the onboarding flow) keeps the exact same Spacer-centered layout when it fits
        // and only becomes a real ScrollView once it doesn't — so default text sizes
        // render byte-identical to the un-wrapped VStack, while AX-XXL gets a safety
        // net. Purely presentational: no change to biometric/slide/attempt logic below.
        OnboardingScrollingStep {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: Space.s7) {
                    VStack(spacing: Space.s4) {
                        BrandLogoMark.hero
                            .overlay(alignment: .bottomTrailing) {
                                if mode == .biometric && !requireSlide {
                                    BiometricBadge(authenticating: bioAuthenticating) {
                                        triggerBiometric()
                                    }
                                    .offset(x: 6, y: 6)
                                    .transition(.scale.combined(with: .opacity))
                                }
                            }

                        VStack(spacing: Space.s2) {
                            Text("Unlock your vault")
                                .vaultType(.screenTitle)
                            // While the vault key is being derived/fetched the ∞ draws
                            // itself — the gate working open (Controlled Reveal). The
                            // instruction line yields for that moment only.
                            if bioAuthenticating || busy {
                                LooxGateMark(animating: true)
                                    .frame(height: 18)
                                    .transition(.opacity)
                                    // Fresh element: the mark itself is accessibility-
                                    // hidden (decorative), but this moment needs a
                                    // VoiceOver announcement.
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(Text("Unlocking"))
                            } else {
                                Text(subtitleText)
                                    .vaultType(.subhead)
                                    .themedForeground(.secondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .animation(.vault(Motion.standard, reduceMotion: reduceMotion),
                                   value: bioAuthenticating || busy)
                    }

                    if requireSlide {
                        // Shake-locked → confirm by sliding before any Face ID prompt.
                        SlideToUnlock { confirmSlide() }
                            .transition(.opacity)
                    } else if mode == .password {
                        passwordSection
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, Space.s8)

                Spacer()

                // "Forgot password?" pinned to the bottom (password mode only). Keyboard
                // avoidance lifts it just above the keyboard when the field is focused.
                if mode == .password {
                    Button("Forgot password?") { showRecovery = true }
                        .vaultType(.footnote)
                        .padding(.bottom, Space.s8)
                        .transition(.opacity)
                }
            }
        } // OnboardingScrollingStep
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Centre in the full screen (not just the safe area) so the logo lines up with the
        // LaunchScreen logo — otherwise the larger top inset (Dynamic Island) drops it ~12pt,
        // making it visibly jump down at the launch hand-off. `.container` keeps keyboard
        // avoidance intact for password mode.
        .ignoresSafeArea(.container, edges: .vertical)
        .themedWallpaper(env.theme.wallpaper, fallback: Color(rgb: env.theme.active.background))
        .animation(.vault(.spring(response: 0.5, dampingFraction: 0.85), reduceMotion: reduceMotion), value: mode)
        .animation(.vault(.spring(response: 0.5, dampingFraction: 0.85), reduceMotion: reduceMotion), value: requireSlide)
        .sheet(isPresented: $showRecovery) { RecoveryView() }
        .onAppear {
            // After a shake-lock, wait for the slide; otherwise auto-prompt as usual.
            guard !requireSlide else { return }
            if !canUseBiometrics { mode = .password }
            triggerBiometric()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                didBackground = true
            case .active:
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

    private var passwordSection: some View {
        VStack(spacing: Space.s2) {
            LockPasswordField(text: $password, busy: busy) {
                Task { await unlock() }
            }
            if let error {
                Text(error).vaultType(.footnote).foregroundStyle(VaultColors.strengthWeak)
            }
        }
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
            // Success → session state flips to unlocked → this view is replaced.
        } catch {
            bioFailCount += 1
            Haptics.error()
            if bioFailCount >= maxBioAttempts {
                withAnimation(.vault(.spring(response: 0.5, dampingFraction: 0.85), reduceMotion: reduceMotion)) { mode = .password }
            }
        }
    }

    // MARK: - Password

    private func unlock() async {
        guard !password.isEmpty, !busy else { return }
        busy = true; error = nil
        do {
            try await env.session.unlock(password: password)
            password = ""
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
            env.theme.morphMesh()
        }
        busy = false
    }
}
