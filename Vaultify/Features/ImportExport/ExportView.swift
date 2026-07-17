import SwiftUI

/// Export the vault as a passphrase-encrypted backup (recommended) or plain CSV.
struct ExportView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case encrypted, csv
        var id: String { rawValue }
        var title: LocalizedStringResource {
            let base: LocalizedStringResource = self == .encrypted ? "Encrypted" : "CSV (plain)"
            return base.inAppLocalized
        }
    }

    @Environment(AppEnvironment.self) private var env
    @State private var mode: Mode = .encrypted
    @State private var passphrase = ""
    @State private var confirm = ""
    @State private var exportURL: URL?
    @State private var working = false
    @State private var error: String?
    @State private var confirmPlainExport = false

    private var canExport: Bool {
        guard !env.repository.items.isEmpty || !env.repository.passkeys.isEmpty else { return false }
        if mode == .encrypted { return passphrase.count >= 8 && passphrase == confirm }
        return true
    }

    var body: some View {
        Form {
            Picker("Format", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { exportURL = nil }

            if mode == .encrypted {
                Section {
                    RevealableSecureField(title: "Password", text: $passphrase).listRowInsets(.init())
                    RevealableSecureField(title: "Confirm", text: $confirm).listRowInsets(.init())
                } header: {
                    Text("Backup password")
                } footer: {
                    Text("The backup is sealed with Argon2id + AES-256-GCM. You’ll need this password to restore it.")
                }
                .listRowBackground(VaultColors.surface)
            } else {
                Section {
                    Label {
                        Text("A CSV export is **not encrypted**. Anyone with the file can read every password. Passkeys are never included in CSV.")
                    } icon: {
                        PolarisIcon(Icons.alert).foregroundStyle(VaultColors.strengthWeak)
                    }
                }
                .listRowBackground(VaultColors.surface)
            }

            Section {
                if mode == .csv {
                    // Plaintext export gets deliberate friction: a destructive-styled
                    // CTA plus a confirmation, so it can't be created in passing.
                    Button(role: .destructive) { confirmPlainExport = true } label: {
                        Text("Create Unencrypted Export")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(env.theme.active.color(.destructive))
                    }
                    .disabled(!canExport || working)
                } else {
                    Button { Task { await generate() } } label: {
                        Text("Create Export").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.themedProminent)
                    .disabled(!canExport || working)
                }
            }
            .listRowBackground(VaultColors.surface)

            if let exportURL {
                Section {
                    ShareLink(item: exportURL) {
                        Label { Text("Share Export") } icon: { PolarisIcon(Icons.share) }
                    }
                }
                .listRowBackground(VaultColors.surface)
            }

            if let error { Text(error).foregroundStyle(VaultColors.strengthWeak) }
        }
        .themedFormBackground()
        .navigationTitle("Export")
        .platformNavigationBarTitleDisplayMode(.inline)
        .overlay { if working { ProgressView().controlSize(.large) } }
        .confirmationDialog("Create an unencrypted export?",
                            isPresented: $confirmPlainExport, titleVisibility: .visible) {
            Button("Create Unencrypted Export", role: .destructive) { Task { await generate() } }
        } message: {
            Text("Anyone who gets this file can read every password in it. Delete it as soon as you're done.")
        }
    }

    private func generate() async {
        working = true; error = nil; exportURL = nil
        do {
            let items = env.repository.items
            let folderNames = Dictionary(env.repository.folders.map { ($0.id, $0.name) },
                                         uniquingKeysWith: { a, _ in a })
            if mode == .encrypted {
                let passkeys = env.session.vaultKey.map { PasskeyVault(store: env.store).secrets(key: $0) } ?? []
                // A backup that silently omits existing passkeys would betray
                // its purpose exactly when it matters (restore) — refuse
                // instead of exporting an incomplete vault.
                if passkeys.count < env.repository.passkeys.count {
                    throw ExportError.passkeysUnavailable
                }
                let data = try await VaultBackup.exportEncrypted(items, folderNames: folderNames,
                                                                 passkeys: passkeys, passphrase: passphrase)
                exportURL = try write(data, name: "loox-backup.vaultify")
            } else {
                exportURL = try write(Data(VaultBackup.makeCSV(items, folderNames: folderNames).utf8), name: "loox-export.csv")
            }
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
        }
        working = false
    }

    private func write(_ data: Data, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .completeFileProtection)
        return url
    }
}

/// An encrypted export must be COMPLETE to be a backup — a passkey the vault
/// holds but the export can't resolve (vault key unavailable mid-flight, or a
/// credential that fails to decode) would make the file silently lossy,
/// discovered only at restore time.
private enum ExportError: LocalizedError {
    case passkeysUnavailable
    var errorDescription: String? {
        appString("Passkeys couldn't be included in this export. Lock the app, unlock it, then try again.")
    }
}
