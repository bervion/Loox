import SwiftUI

/// Recover a vault with the Emergency Kit recovery key and set a new master
/// password. Presented as a sheet from the lock screen.
struct RecoveryView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var recoveryKey = ""
    @State private var newPassword = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var error: String?

    private var canSubmit: Bool {
        !recoveryKey.isEmpty && newPassword.count >= 8 && newPassword == confirm && !busy
    }

    var body: some View {
        VaultSheetScaffold(title: "Recover Vault", trailing: {
            Button("Recover") { Task { await recover() } }.disabled(!canSubmit)
        }) {
            Form {
                Section {
                    TextField("Recovery key", text: $recoveryKey, axis: .vertical)
                        .font(.vaultCode())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } header: {
                    Text("Emergency Kit")
                } footer: {
                    Text("Enter the recovery key from your Emergency Kit.")
                }
                .listRowBackground(VaultColors.surface)

                Section("New master password") {
                    RevealableSecureField(title: "New password", text: $newPassword)
                        .listRowInsets(.init())
                    PasswordStrengthMeter(password: newPassword)
                    RevealableSecureField(title: "Confirm password", text: $confirm)
                        .listRowInsets(.init())
                }
                .listRowBackground(VaultColors.surface)

                if let error {
                    Text(error).foregroundStyle(VaultColors.strengthWeak)
                }
            }
            .overlay { if busy { ProgressView().controlSize(.large) } }
        }
    }

    private func recover() async {
        busy = true; error = nil
        do {
            try await env.session.recover(recoveryKey: recoveryKey, newPassword: newPassword)
            dismiss()
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
        }
        busy = false
    }
}
