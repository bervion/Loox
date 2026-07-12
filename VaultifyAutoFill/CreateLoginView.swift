import SwiftUI
import AuthenticationServices

/// Create + save a new login during web registration, then fill it. Site is prefilled from the
/// requesting domain, username/email from the default identity, password freshly generated.
/// Saving writes the item to the shared vault (`VaultWriter`), indexes it for QuickType, and
/// returns the credential to fill. There is no iOS hook for registration success, so an abandoned
/// signup leaves the item in the vault (the user prunes it later) — an accepted trade-off.
struct CreateLoginView: View {
    let host: String
    /// The presentation's single vault store (owned by the hosting controller).
    let store: VaultStore
    let vaultKey: SecureBytes
    /// Called after a successful save to fill the form (maps to the credential completion).
    let onSaved: (_ user: String, _ password: String) -> Void

    @State private var site: String
    @State private var username: String
    @State private var password: String
    @State private var folderId: String?
    @State private var spaces: [VaultSpaceReader.Space] = []
    @State private var errorMessage: String?

    init(host: String, defaultUsername: String, store: VaultStore, vaultKey: SecureBytes,
         onSaved: @escaping (_ user: String, _ password: String) -> Void) {
        self.host = host
        self.store = store
        self.vaultKey = vaultKey
        self.onSaved = onSaved
        _site = State(initialValue: host)
        _username = State(initialValue: defaultUsername)
        _password = State(initialValue: PasswordGenerator.generate(PasswordOptions()))
    }

    var body: some View {
        Form {
            Section { TextField("Website", text: $site).textInputAutocapitalization(.never) }
                header: { Text("Website") }
            Section { TextField("Username", text: $username).textInputAutocapitalization(.never) }
                header: { Text("Username") }
            Section {
                HStack {
                    // Redacts the generated secret in app-switcher snapshots.
                    Text(password).font(.body.monospaced()).lineLimit(1).minimumScaleFactor(0.7)
                        .privacySensitive()
                    Spacer()
                    Button("Regenerate") { password = PasswordGenerator.generate(PasswordOptions()) }
                        .buttonStyle(.borderless)
                }
            } header: { Text("Password") } footer: {
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
                Button(action: save) {
                    HStack { Spacer(); Text("Save & fill").bold(); Spacer() }
                }
                .disabled(password.isEmpty)
            }
        }
        .navigationTitle("New login")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            spaces = VaultSpaceReader.activePersonaSpaces(store: store, vaultKey: vaultKey)
            folderId = VaultSpaceReader.defaultSpaceId(store: store, vaultKey: vaultKey)
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
        do {
            let id = try VaultWriter.createLogin(store: store, site: site, username: username,
                                                 password: password, folderId: folderId,
                                                 vaultKey: vaultKey)
            indexCredential(recordID: id)
            onSaved(username, password)
        } catch {
            errorMessage = appString("Couldn’t save the login.")
        }
    }

    /// Append (not replace) a QuickType identity for the new item so it's suggested next visit.
    /// Skips when there's no usable host — `autofillHost` needs a non-empty URL to match.
    private func indexCredential(recordID: String) {
        let raw = site.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !username.isEmpty,
              let host = URL(string: raw.contains("://") ? raw : "https://\(raw)")?.host?.lowercased()
        else { return }
        let identity = ASPasswordCredentialIdentity(
            serviceIdentifier: ASCredentialServiceIdentifier(identifier: host, type: .domain),
            user: username,
            recordIdentifier: recordID)
        ASCredentialIdentityStore.shared.saveCredentialIdentities([identity], completion: nil)
    }
}
