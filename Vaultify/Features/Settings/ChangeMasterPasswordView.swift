import SwiftUI

/// Re-keys the master-password unlock path after verifying the current password.
/// The Vault Key is unchanged, so biometrics and the Emergency Kit stay valid.
struct ChangeMasterPasswordView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var newPassword = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var error: String?

    private var canSubmit: Bool {
        !current.isEmpty && newPassword.count >= 8 && newPassword == confirm && !busy
    }

    var body: some View {
        Form {
            Section {
                VaultInfoBanner(.info, icon: Icons.key,
                                text: "Your Vault Key doesn't change — Face ID unlock and your Emergency Kit keep working.")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section("Current password") {
                RevealableSecureField(title: "Current master password", text: $current)
                    .listRowInsets(.init())
            }
            .listRowBackground(VaultColors.surface)
            Section("New password") {
                RevealableSecureField(title: "New password", text: $newPassword)
                    .listRowInsets(.init())
                PasswordStrengthMeter(password: newPassword)
                RevealableSecureField(title: "Confirm new password", text: $confirm)
                    .listRowInsets(.init())
                if !confirm.isEmpty && newPassword != confirm {
                    Text("Passwords don’t match")
                        .vaultType(.footnote)
                        .foregroundStyle(VaultColors.strengthWeak)
                }
            }
            .listRowBackground(VaultColors.surface)
            if let error {
                Text(error).foregroundStyle(VaultColors.strengthWeak)
            }
        }
        .themedFormBackground()
        .navigationTitle("Change Master Password")
        .platformNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await change() } }.disabled(!canSubmit)
            }
        }
        .overlay { if busy { ProgressView().controlSize(.large) } }
    }

    private func change() async {
        busy = true; error = nil
        do {
            try await env.session.changeMasterPassword(current: current, new: newPassword)
            Haptics.success()
            dismiss()
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
        }
        busy = false
    }
}
