import SwiftUI

/// Master-password unlock used by the passkey flows. On success it hands the
/// derived Vault Key back to the view controller, which performs the WebAuthn
/// registration or assertion.
struct PasskeyActionView: View {
    let prompt: LocalizedStringResource
    let onUnlocked: (_ vaultKey: [UInt8]) -> Void
    let onCancel: () -> Void

    @State private var masterPassword = ""
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Master password", text: $masterPassword)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit(unlock)
                } header: {
                    Text(prompt)
                } footer: {
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                }
                Section {
                    Button(action: unlock) {
                        HStack { Spacer(); Text("Unlock").bold(); Spacer() }
                    }
                    .disabled(masterPassword.isEmpty || working)
                }
            }
            .navigationTitle("Vaultify")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
            }
            .overlay { if working { ProgressView().controlSize(.large) } }
            .disabled(working)
        }
    }

    private func unlock() {
        guard !masterPassword.isEmpty else { return }
        working = true; errorMessage = nil
        let password = masterPassword
        Task {
            do {
                let key = try await Task.detached(priority: .userInitiated) {
                    try VaultReader.deriveVaultKey(masterPassword: password)
                }.value
                onUnlocked(key)
            } catch VaultReader.Failure.wrongPassword {
                errorMessage = String(localized: "Incorrect master password."); working = false
            } catch {
                errorMessage = String(localized: "Couldn’t unlock the vault."); working = false
            }
        }
    }
}
