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
                Text("Supports CSV exports and Vaultify encrypted backups (.vaultify).")
            }

            if let encryptedData {
                Section("Encrypted backup") {
                    RevealableSecureField(title: "Backup password", text: $passphrase)
                        .listRowInsets(.init())
                    Button("Decrypt") { Task { await decrypt(encryptedData) } }
                        .disabled(passphrase.isEmpty || working)
                }
            }

            if !parsed.isEmpty {
                Section("Preview (\(parsed.count))") {
                    ForEach(parsed.prefix(6)) { VaultItemRow(item: $0.item) }
                    if parsed.count > 6 { Text("and \(parsed.count - 6) more…").font(.footnote).foregroundStyle(.secondary) }
                }
                Section {
                    Button { performImport() } label: {
                        Text("Import \(parsed.count) Items").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.themedProminent)
                }
            }

            if let error { Text(error).foregroundStyle(VaultColors.strengthWeak) }
        }
        .themedFormBackground()
        .navigationTitle("Import")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if working { ProgressView().controlSize(.large) } }
        .fileImporter(isPresented: $showPicker,
                      allowedContentTypes: [.commaSeparatedText, .json, .plainText, .data],
                      allowsMultipleSelection: false) { result in
            handle(result)
        }
    }

    private func handle(_ result: Result<[URL], Error>) {
        error = nil; parsed = []; encryptedData = nil
        guard case let .success(urls) = result, let url = urls.first else {
            if case let .failure(failure) = result { error = failure.localizedDescription }
            return
        }
        guard url.startAccessingSecurityScopedResource() else { error = "Couldn’t open the file."; return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else { error = "Couldn’t read the file."; return }

        if (try? JSONDecoder().decode(VaultBackup.EncryptedBackup.self, from: data)) != nil {
            encryptedData = data
        } else if let text = String(data: data, encoding: .utf8) {
            parsed = VaultBackup.parseCSVWithFolders(text).map { ImportRow(item: $0.item, folderName: $0.folderName) }
            if parsed.isEmpty { error = "No items found in that file." }
        } else {
            error = "Unsupported file format."
        }
    }

    private func decrypt(_ data: Data) async {
        working = true; error = nil
        do {
            parsed = try await VaultBackup.importEncrypted(data, passphrase: passphrase)
                .map { ImportRow(item: $0.item, folderName: $0.folderName) }
            encryptedData = nil
            if parsed.isEmpty { error = "Backup contained no items." }
        } catch {
            self.error = "Couldn’t decrypt — check the password."
        }
        working = false
    }

    private func performImport() {
        var folderCache: [String: String] = [:]   // lowercased name → folder id
        for row in parsed {
            var item = row.item
            if let name = row.folderName, !name.isEmpty {
                item.folderId = resolveFolder(name, cache: &folderCache)
            }
            try? env.repository.add(item)
        }
        Haptics.success()
        dismiss()
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
