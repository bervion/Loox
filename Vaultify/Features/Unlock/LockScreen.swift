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
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showRecovery = false

    /// Biometric attempts (auto-prompt + taps) before falling back to the password field.
    private let maxBioAttempts = 3

    private var canUseBiometrics: Bool {
        env.session.biometricEnrolled && env.settings.biometricUnlockEnabled && BiometricAuth.isAvailable
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: Space.s8) {
                BrandLogoMark(size: 104, shadowRadius: 16, shadowY: 8)
                    .overlay(alignment: .bottomTrailing) {
                        if mode == .biometric {
                            BiometricBadge(authenticating: bioAuthenticating) {
                                Task { await tryBiometrics() }
                            }
                            .offset(x: 6, y: 6)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }

                if mode == .password {
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
        .sheet(isPresented: $showRecovery) { RecoveryView() }
        .onAppear {
            if !canUseBiometrics { mode = .password }
            triggerBiometric()
        }
        .onChange(of: scenePhase) { _, phase in
            // Re-prompt Face ID when the app returns to the foreground (it auto-locks on
            // background, so the lock screen is already on screen).
            if phase == .active { triggerBiometric() }
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
    /// cap. A short delay lets the foreground transition settle so the prompt isn't dismissed.
    private func triggerBiometric() {
        guard mode == .biometric, scenePhase == .active, canUseBiometrics,
              !bioAuthenticating, bioFailCount < maxBioAttempts else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            await tryBiometrics()
        }
    }

    private func tryBiometrics() async {
        guard mode == .biometric, !bioAuthenticating else { return }
        bioAuthenticating = true
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
        bioAuthenticating = false
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
