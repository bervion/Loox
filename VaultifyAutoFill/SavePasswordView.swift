import SwiftUI
import AuthenticationServices

/// Confirm + save a credential the system handed us via the iOS 26.2 native "Save password" flow.
/// Unlock is handled by the shared `UnlockGate`; this view confirms + seals via `VaultWriter`.
struct SavePasswordView: View {
    let host: String
    let username: String
    let password: String
    let onSaved: () -> Void
    let onCancel: () -> Void

    var body: some View {
        UnlockGate(title: "Save login", onCancel: onCancel) { vaultKey in
            SaveConfirmView(host: host, username: username, password: password,
                            vaultKey: vaultKey, onSaved: onSaved)
        }
    }
}

/// Post-unlock save confirmation. Shows the login, then seals it into the vault on Save.
private struct SaveConfirmView: View {
    let host: String
    let username: String
    let password: String
    let vaultKey: [UInt8]
    let onSaved: () -> Void

    @State private var saving = false
    @State private var folderId: String?
    @State private var spaces: [VaultSpaceReader.Space] = []
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Website", value: host.isEmpty ? appString("Not provided") : host)
                LabeledContent("Username", value: username.isEmpty ? appString("Not provided") : username)
            } footer: {
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            // Only the ACTIVE persona's own Spaces are offered (INV-R03) — never
            // another persona's, even by name. "Save to" (not "Space") sidesteps an
            // existing source-string collision with the password generator's literal
            // "Space" (spacebar character) key, which carries an unrelated VI string.
            if !spaces.isEmpty {
                Section { spacePicker } header: { Text("Save to") }
            }
            Section {
                Button(action: save) { HStack { Spacer(); Text("Save").bold(); Spacer() } }
                    .disabled(saving)
            }
        }
        .task {
            spaces = VaultSpaceReader.activePersonaSpaces(vaultKey: vaultKey)
            folderId = VaultSpaceReader.defaultSpaceId(vaultKey: vaultKey)
        }
    }

    /// Menu-style Picker so the ≥44pt row stays compact — matches the rest of this
    /// Form's system styling (no design-system tokens; the extension only links
    /// VaultifyCore).
    private var spacePicker: some View {
        Picker(selection: $folderId) {
            Text("Unfiled").tag(String?.none)
            ForEach(spaces) { space in Text(space.name).tag(String?.some(space.id)) }
        } label: { Text("Save to") }
    }

    private func save() {
        saving = true; errorMessage = nil
        do {
            let id = try VaultWriter.createLogin(site: host, username: username,
                                                 password: password, folderId: folderId,
                                                 vaultKey: vaultKey)
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
