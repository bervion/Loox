import SwiftUI

/// Unlock (master password) then pick a login to fill. Items whose website
/// matches the requesting app/site are shown first.
struct AutoFillView: View {
    let serviceIdentifiers: [String]
    let preferredRecordID: String?
    let onSelect: (_ user: String, _ password: String) -> Void
    let onCancel: () -> Void

    @State private var masterPassword = ""
    @State private var unlocking = false
    @State private var errorMessage: String?
    @State private var items: [VaultItem] = []
    @State private var unlocked = false
    /// True while the initial Face ID attempt is in flight — shows a spinner instead of
    /// flashing the master-password form. Set false on any biometric failure or when not enrolled.
    @State private var biometricInProgress = true
    /// Retained after unlock so "Create new login" can seal a new item; the extension already
    /// holds decrypted secrets in memory, so this is no new exposure.
    @State private var vaultKey: [UInt8] = []
    /// Default-identity email/name to prefill the Create-login username. Empty if none.
    @State private var defaultUsername = ""

    var body: some View {
        NavigationStack {
            Group {
                if unlocked { credentialList }
                else if biometricInProgress { biometricLoading }
                else { unlockForm }
            }
            .navigationTitle("Vaultify")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
            }
        }
        .task { await attemptBiometricUnlock() }
    }

    private var biometricLoading: some View {
        ProgressView().controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Biometric unlock (Face ID — no Argon2)

    /// On appear, if a biometric Vault Key is provisioned (shared keychain group), prompt Face ID
    /// and unlock directly — skipping the master password. ANY failure (cancel, item-not-found,
    /// entitlement, biometrics changed) reveals the master-password form as a fallback.
    private func attemptBiometricUnlock() async {
        guard BiometricKeyStore.isEnrolled else { biometricInProgress = false; return }
        do {
            let key = try await BiometricKeyStore.retrieve(reason: appString("Unlock your vault"))
            adoptUnlocked(key: key)
            if let preferredRecordID, let hit = items.first(where: { $0.id == preferredRecordID }) {
                select(hit)
            }
        } catch {
            biometricInProgress = false
        }
    }

    /// Load logins + the default-identity prefill and retain the key for Create-login.
    private func adoptUnlocked(key: [UInt8]) {
        items = VaultReader.logins(vaultKey: key)
        vaultKey = key
        defaultUsername = VaultReader.defaultIdentityUsername(vaultKey: key) ?? ""
        unlocked = true
    }

    // MARK: Unlock

    private var unlockForm: some View {
        Form {
            Section {
                SecureField("Master password", text: $masterPassword)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .onSubmit(unlock)
            } header: {
                Text("Unlock your vault")
            } footer: {
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            Section {
                Button(action: unlock) {
                    HStack { Spacer(); Text("Unlock").bold(); Spacer() }
                }
                .disabled(masterPassword.isEmpty || unlocking)
            }
        }
        .overlay { if unlocking { ProgressView().controlSize(.large) } }
        .disabled(unlocking)
    }

    // MARK: Credential list

    private var credentialList: some View {
        List {
            Section {
                NavigationLink {
                    CreateLoginView(host: serviceIdentifiers.first ?? "",
                                    defaultUsername: defaultUsername,
                                    vaultKey: vaultKey,
                                    onSaved: onSelect)
                } label: {
                    Text("＋ Create new login")
                }
            }
            if matched.isEmpty && !others.isEmpty {
                Section("All logins") { ForEach(others, content: row) }
            } else {
                if !matched.isEmpty { Section("For this app") { ForEach(matched, content: row) } }
                if !others.isEmpty { Section("Other logins") { ForEach(others, content: row) } }
            }
            if items.isEmpty { Text("No logins found").foregroundStyle(.secondary) }
        }
    }

    private var matched: [VaultItem] { items.filter { $0.matchesAutoFill(serviceIdentifiers: serviceIdentifiers) } }
    private var others: [VaultItem] {
        serviceIdentifiers.isEmpty ? items : items.filter { !$0.matchesAutoFill(serviceIdentifiers: serviceIdentifiers) }
    }

    private func row(_ item: VaultItem) -> some View {
        Button { select(item) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? "Untitled" : item.title).foregroundStyle(.primary)
                if let user = item.usernameField?.value, !user.isEmpty {
                    Text(user).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Actions

    private func unlock() {
        guard !masterPassword.isEmpty else { return }
        unlocking = true; errorMessage = nil
        let password = masterPassword
        Task {
            do {
                let key = try await Task.detached(priority: .userInitiated) {
                    try VaultReader.deriveVaultKey(masterPassword: password)
                }.value
                adoptUnlocked(key: key)
                if let preferredRecordID, let hit = items.first(where: { $0.id == preferredRecordID }) {
                    select(hit)
                }
            } catch VaultReader.Failure.wrongPassword {
                errorMessage = appString("Incorrect master password.")
            } catch {
                errorMessage = appString("Couldn’t unlock the vault.")
            }
            unlocking = false
        }
    }

    private func select(_ item: VaultItem) {
        onSelect(item.usernameField?.value ?? "", item.passwordField?.value ?? "")
    }
}
