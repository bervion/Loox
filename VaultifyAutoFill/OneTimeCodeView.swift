import SwiftUI

/// 2FA AutoFill: unlock, then supply the current TOTP code for a login matching the site.
/// A single matching code is filled automatically after unlock; multiple show a picker.
/// (Unlock orchestration mirrors `AutoFillView` / `SavePasswordView` — a shared unlock gate is
/// a worthwhile future refactor now that three flows duplicate it.)
struct OneTimeCodeView: View {
    let serviceIdentifiers: [String]
    let preferredRecordID: String?
    let onSelect: (_ code: String) -> Void
    let onCancel: () -> Void

    @State private var masterPassword = ""
    @State private var unlocking = false
    @State private var errorMessage: String?
    @State private var items: [VaultItem] = []
    @State private var unlocked = false
    @State private var biometricInProgress = true

    var body: some View {
        NavigationStack {
            Group {
                if unlocked { codeList }
                else if biometricInProgress {
                    ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else { unlockForm }
            }
            .navigationTitle("One-time code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
            }
        }
        .task { await attemptBiometricUnlock() }
    }

    // MARK: List

    private var codeList: some View {
        List {
            if matched.isEmpty && others.isEmpty {
                Text("No 2FA codes found").foregroundStyle(.secondary)
            }
            if !matched.isEmpty { Section("For this app") { ForEach(matched, content: row) } }
            if !others.isEmpty { Section("Other codes") { ForEach(others, content: row) } }
        }
    }

    private var matched: [VaultItem] { items.filter { $0.matchesAutoFill(serviceIdentifiers: serviceIdentifiers) } }
    private var others: [VaultItem] {
        serviceIdentifiers.isEmpty ? items : items.filter { !$0.matchesAutoFill(serviceIdentifiers: serviceIdentifiers) }
    }

    /// Title + username only — never render the live code inline (avoids putting every 2FA code
    /// on one screen, matching the password picker's "don't show the secret you're about to fill"
    /// stance). The code is generated on tap in `provide`.
    private func row(_ item: VaultItem) -> some View {
        Button { provide(item) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? "Untitled" : item.title).foregroundStyle(.primary)
                if let user = item.usernameField?.value, !user.isEmpty {
                    Text(user).font(.caption).foregroundStyle(.secondary)
                }
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
            let key = try await BiometricKeyStore.retrieve(reason: appString("Unlock your vault"))
            adoptUnlocked(key: key)
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
                let key = try await Task.detached(priority: .userInitiated) {
                    try VaultReader.deriveVaultKey(masterPassword: password)
                }.value
                adoptUnlocked(key: key)
            } catch VaultReader.Failure.wrongPassword {
                errorMessage = appString("Incorrect master password.")
            } catch {
                errorMessage = appString("Couldn’t unlock the vault.")
            }
            unlocking = false
        }
    }

    /// Load TOTP items; auto-fill a preferred record or a sole match, else reveal the picker.
    private func adoptUnlocked(key: [UInt8]) {
        items = VaultReader.totpItems(vaultKey: key)
        if let preferredRecordID, let hit = items.first(where: { $0.id == preferredRecordID }) {
            provide(hit); return
        }
        let m = matched
        if m.count == 1 { provide(m[0]); return }
        unlocked = true
    }

    // MARK: Provide

    private func currentCode(_ item: VaultItem) -> String? {
        guard let value = item.totpField?.value else { return nil }
        return TOTPGenerator.code(forStoredValue: value)
    }

    private func provide(_ item: VaultItem) {
        if let code = currentCode(item) {
            onSelect(code)
        } else {
            unlocked = true
            errorMessage = appString("Couldn’t generate the code.")
        }
    }
}
