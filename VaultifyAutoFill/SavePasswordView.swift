import SwiftUI
import AuthenticationServices

/// Confirm + save a credential the system handed us via the iOS 26.2 native "Save password" flow
/// (after the user registers/changes a password on a web form). Unlocks the vault (Face ID → master
/// password fallback), shows the login, then seals it into the vault via `VaultWriter`.
struct SavePasswordView: View {
    let host: String
    let username: String
    let password: String
    let onSaved: () -> Void
    let onCancel: () -> Void

    @State private var masterPassword = ""
    @State private var vaultKey: [UInt8] = []
    @State private var unlocked = false
    @State private var biometricInProgress = true
    @State private var unlocking = false
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if unlocked { saveConfirm }
                else if biometricInProgress {
                    ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else { unlockForm }
            }
            .navigationTitle("Save login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
            }
        }
        .task { await attemptBiometricUnlock() }
    }

    // MARK: Confirm

    private var saveConfirm: some View {
        Form {
            Section {
                LabeledContent("Website", value: host.isEmpty ? "—" : host)
                LabeledContent("Username", value: username.isEmpty ? "—" : username)
            } footer: {
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            Section {
                Button(action: save) { HStack { Spacer(); Text("Save").bold(); Spacer() } }
                    .disabled(saving)
            }
        }
    }

    // MARK: Unlock

    private var unlockForm: some View {
        Form {
            Section {
                SecureField("Master password", text: $masterPassword)
                    .textContentType(.password).submitLabel(.go).onSubmit(unlockWithMaster)
            } header: {
                Text("Unlock your vault")
            } footer: {
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            Section {
                Button(action: unlockWithMaster) { HStack { Spacer(); Text("Unlock").bold(); Spacer() } }
                    .disabled(masterPassword.isEmpty || unlocking)
            }
        }
        .overlay { if unlocking { ProgressView().controlSize(.large) } }
        .disabled(unlocking)
    }

    private func attemptBiometricUnlock() async {
        guard BiometricKeyStore.isEnrolled else { biometricInProgress = false; return }
        do {
            vaultKey = try await BiometricKeyStore.retrieve(reason: appString("Unlock your vault"))
            unlocked = true
        } catch {
            biometricInProgress = false
        }
    }

    private func unlockWithMaster() {
        guard !masterPassword.isEmpty else { return }
        unlocking = true; errorMessage = nil
        let password = masterPassword
        Task {
            do {
                vaultKey = try await Task.detached(priority: .userInitiated) {
                    try VaultReader.deriveVaultKey(masterPassword: password)
                }.value
                unlocked = true
            } catch VaultReader.Failure.wrongPassword {
                errorMessage = appString("Incorrect master password.")
            } catch {
                errorMessage = appString("Couldn’t unlock the vault.")
            }
            unlocking = false
        }
    }

    // MARK: Save

    private func save() {
        saving = true; errorMessage = nil
        do {
            let id = try VaultWriter.createLogin(site: host, username: username,
                                                 password: password, vaultKey: vaultKey)
            indexCredential(recordID: id)
            onSaved()
        } catch {
            errorMessage = appString("Couldn’t save the login.")
            saving = false
        }
    }

    /// Append a QuickType identity so the saved login is suggested next visit (skip if no host).
    private func indexCredential(recordID: String) {
        let raw = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !username.isEmpty,
              let h = URL(string: raw.contains("://") ? raw : "https://\(raw)")?.host?.lowercased()
        else { return }
        let identity = ASPasswordCredentialIdentity(
            serviceIdentifier: ASCredentialServiceIdentifier(identifier: h, type: .domain),
            user: username, recordIdentifier: recordID)
        ASCredentialIdentityStore.shared.saveCredentialIdentities([identity], completion: nil)
    }
}
