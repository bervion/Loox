import SwiftUI

/// Master-password / biometric unlock gate shown whenever the vault is locked.
struct LockScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showRecovery = false
    @State private var promptingBiometric = false

    private var canUseBiometrics: Bool {
        env.session.biometricEnrolled && env.settings.biometricUnlockEnabled && BiometricAuth.isAvailable
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            PolarisIcon(Icons.lockFill, size: 60).foregroundStyle(Color.accentColor)
            Text("Vaultify").font(.largeTitle.bold()).padding(.top, 12)
            Text("Enter your master password to unlock")
                .font(.subheadline).foregroundStyle(.secondary).padding(.top, 2)

            VStack(spacing: 12) {
                RevealableSecureField(title: "Master password", text: $password)
                    .submitLabel(.go)
                    .onSubmit { Task { await unlock() } }

                if let error {
                    Text(error).font(.footnote).foregroundStyle(VaultColors.strengthWeak)
                }

                Button {
                    Task { await unlock() }
                } label: {
                    if busy { ProgressView().frame(maxWidth: .infinity) }
                    else { Text("Unlock").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(password.isEmpty || busy)

                if canUseBiometrics {
                    Button {
                        Task { await unlockWithBiometrics() }
                    } label: {
                        Label("Unlock with \(BiometricAuth.displayName)", image: BiometricAuth.iconAsset)
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 32)

            Spacer()
            Button("Forgot master password?") { showRecovery = true }
                .font(.footnote)
                .padding(.bottom, 24)
        }
        .sheet(isPresented: $showRecovery) { RecoveryView() }
        .onAppear { triggerBiometric() }
        .onChange(of: scenePhase) { _, phase in
            // Re-prompt Face ID when the app returns to the foreground (the vault
            // auto-locks on background, so the lock screen is already on screen).
            if phase == .active { triggerBiometric() }
        }
    }

    /// Auto-prompt biometrics, but only while the app is active (iOS won't show
    /// Face ID otherwise) and not already prompting. A short delay lets the
    /// foreground transition settle so the prompt isn't dismissed.
    private func triggerBiometric() {
        guard scenePhase == .active, canUseBiometrics, !promptingBiometric, !busy else { return }
        promptingBiometric = true
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            await unlockWithBiometrics()
            promptingBiometric = false
        }
    }

    private func unlock() async {
        guard !password.isEmpty else { return }
        busy = true; error = nil
        do {
            try await env.session.unlock(password: password)
            password = ""
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
        }
        busy = false
    }

    private func unlockWithBiometrics() async {
        do { try await env.session.unlockWithBiometrics() }
        catch { /* user cancelled or failed — fall back to password entry */ }
    }
}
