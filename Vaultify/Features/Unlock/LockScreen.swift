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

    /// Set once the user slides to confirm after a shake-lock.
    @State private var slideConfirmed = false

    private var canUseBiometrics: Bool {
        env.session.biometricEnrolled && env.settings.biometricUnlockEnabled && BiometricAuth.isAvailable
    }

    /// After a shake-lock, gate Face ID behind a deliberate slide so a panic-shake in public
    /// can't be instantly re-opened before the user puts the phone away.
    private var requireSlide: Bool { env.session.shakeLocked && !slideConfirmed }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: Space.s8) {
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
                    .font(.footnote)
                    .padding(.bottom, Space.s8)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Centre in the full screen (not just the safe area) so the logo lines up with the
        // LaunchScreen logo — otherwise the larger top inset (Dynamic Island) drops it ~12pt,
        // making it visibly jump down at the launch hand-off. `.container` keeps keyboard
        // avoidance intact for password mode.
        .ignoresSafeArea(.container, edges: .vertical)
        .themedWallpaper(env.theme.wallpaper, fallback: Color(rgb: env.theme.active.background))
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: mode)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: requireSlide)
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
                Text(error).font(.footnote).foregroundStyle(VaultColors.strengthWeak)
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
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { mode = .password }
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
