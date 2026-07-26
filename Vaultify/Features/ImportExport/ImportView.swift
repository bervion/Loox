import SwiftUI
import UniformTypeIdentifiers

/// Import from a CSV export (1Password / Bitwarden / Chrome) or a Vaultify
/// encrypted backup. Folder names in the file are resolved to Spaces on import
/// (matched by name, created if missing); tags are restored too.
struct ImportView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    /// One parsed row: the item plus the folder NAME it should join (if any).
    private struct ImportRow: Identifiable {
        let item: VaultItem
        let folderName: String?
        var id: String { item.id }
    }

    @State private var showPicker = false
    @State private var parsed: [ImportRow] = []
    @State private var parsedPasskeys: [PasskeySecret] = []
    /// The backup's Level-2 wrap (if any) — adopted on import when this device
    /// has none, so restored sealed fields stay openable with the Extra Password.
    @State private var parsedLevel2: VaultBackup.Level2Wrap?
    @State private var encryptedData: Data?
    @State private var passphrase = ""
    @State private var error: String?
    @State private var working = false

    var body: some View {
        Form {
            Section {
                Button { showPicker = true } label: {
                    Label { Text("Choose File…") } icon: { PolarisIcon(Icons.importData) }
                }
            } footer: {
                Text("Supports CSV exports and Loox encrypted backups (.vaultify).")
            }
            .listRowBackground(VaultColors.surface)

            if let encryptedData {
                Section("Encrypted backup") {
                    RevealableSecureField(title: "Backup password", text: $passphrase, inList: true)
                    Button("Decrypt") { Task { await decrypt(encryptedData) } }
                        .disabled(passphrase.isEmpty || working)
                }
                .listRowBackground(VaultColors.surface)
            }

            if !parsed.isEmpty || !parsedPasskeys.isEmpty {
                Section("Preview (\(parsed.count + parsedPasskeys.count))") {
                    ForEach(parsed.prefix(6)) { VaultItemRow(item: $0.item) }
                    if parsed.count > 6 { Text("and \(parsed.count - 6) more…").vaultType(.footnote).themedForeground(.secondary) }
                    if !parsedPasskeys.isEmpty {
                        Label {
                            Text("\(parsedPasskeys.count) passkeys")
                        } icon: {
                            PolarisIcon(Icons.passkey)
                        }
                    }
                }
                .listRowBackground(VaultColors.surface)
                Section {
                    Button { performImport() } label: {
                        Text("Import \(parsed.count + parsedPasskeys.count) Records").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.themedProminent)
                }
                .listRowBackground(VaultColors.surface)
            }

            if let error { Text(error).foregroundStyle(VaultColors.strengthWeak) }
        }
        .themedFormBackground()
        .navigationTitle("Import")
        .platformNavigationBarTitleDisplayMode(.inline)
        .overlay { if working { ProgressView().controlSize(.large) } }
        .fileImporter(isPresented: $showPicker,
                      allowedContentTypes: [.commaSeparatedText, .json, .plainText, .data],
                      allowsMultipleSelection: false) { result in
            handle(result)
        }
    }

    private func handle(_ result: Result<[URL], Error>) {
        error = nil; parsed = []; parsedPasskeys = []; encryptedData = nil
        guard case let .success(urls) = result, let url = urls.first else {
            if case let .failure(failure) = result {
                error = failure.localizedDescription
                Haptics.error()
            }
            return
        }
        guard url.startAccessingSecurityScopedResource() else {
            error = appString("Couldn’t open the file.")
            Haptics.error()
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else {
            error = appString("Couldn’t read the file.")
            Haptics.error()
            return
        }

        if (try? JSONDecoder().decode(VaultBackup.EncryptedBackup.self, from: data)) != nil {
            encryptedData = data
        } else if let text = String(data: data, encoding: .utf8) {
            parsed = VaultBackup.parseCSVWithFolders(text).map { ImportRow(item: $0.item, folderName: $0.folderName) }
            if parsed.isEmpty {
                error = appString("No items found in that file.")
                Haptics.error()
            }
        } else {
            error = appString("Unsupported file format.")
            Haptics.error()
        }
    }

    private func decrypt(_ data: Data) async {
        working = true; error = nil
        do {
            let imported = try await VaultBackup.importEncryptedWithPasskeys(data, passphrase: passphrase)
            parsed = imported.items.map { ImportRow(item: $0.item, folderName: $0.folderName) }
            parsedPasskeys = imported.passkeys
            parsedLevel2 = imported.level2
            encryptedData = nil
            if parsed.isEmpty && parsedPasskeys.isEmpty {
                error = appString("Backup contained no records.")
                Haptics.error()
            }
        } catch {
            self.error = appString("Couldn’t decrypt, check the password.")
            Haptics.error()
        }
        working = false
    }

    private func performImport() {
        error = nil
        guard parsedPasskeys.isEmpty || env.session.vaultKey != nil else {
            error = appString("Unlock your vault before importing passkeys.")
            Haptics.error()
            return
        }
        var folderCache: [String: String] = [:]   // lowercased name → folder id
        do {
            // Bulk: one vault_imported summary below, never per-item events.
            try AnalyticsEngine.shared.runSuppressed {
                for row in parsed {
                    var item = row.item
                    if let name = row.folderName, !name.isEmpty {
                        item.folderId = resolveFolder(name, cache: &folderCache)
                    }
                    try env.repository.add(item)
                }
            }
            if let key = env.session.vaultKey {
                let vault = PasskeyVault(store: env.store)
                for passkey in parsedPasskeys {
                    _ = try vault.save(passkey, key: key)
                }
                env.repository.reload()
                // A passkey-only restore has no item add to schedule the
                // debounced push for it — imported credentials should reach
                // CloudKit without waiting for the next foreground sync.
                if !parsedPasskeys.isEmpty { env.repository.noteLocalMutation() }
            }
            if let level2 = parsedLevel2 {
                env.session.adoptLevel2WrapIfAbsent(wrappedL2SK: level2.wrappedL2SK,
                                                    salt: level2.salt, kdf: level2.kdf)
            }
            AnalyticsEngine.shared.log(.vaultImported(
                countBucket: AnalyticsBucket.count(parsed.count + parsedPasskeys.count)))
            Haptics.success()
            dismiss()
        } catch {
            self.error = appString("Import failed before all records could be saved.")
            Haptics.error()
        }
    }

    /// Match a folder by name (case-insensitive), creating it if it doesn't exist.
    private func resolveFolder(_ name: String, cache: inout [String: String]) -> String? {
        let key = name.lowercased()
        if let id = cache[key] { return id }
        if let existing = env.repository.folders.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            cache[key] = existing.id
            return existing.id
        }
        if let id = try? env.repository.addFolder(name: name, icon: "ic_folder", color: .blue) {
            cache[key] = id
            return id
        }
        return nil
    }
}
