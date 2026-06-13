import SwiftUI
import UniformTypeIdentifiers

/// Import from a CSV export (1Password / Bitwarden / Chrome) or a Vaultify
/// encrypted backup.
struct ImportView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var showPicker = false
    @State private var parsed: [VaultItem] = []
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
                    ForEach(parsed.prefix(6)) { VaultItemRow(item: $0) }
                    if parsed.count > 6 { Text("and \(parsed.count - 6) more…").font(.footnote).foregroundStyle(.secondary) }
                }
                Section {
                    Button { performImport() } label: {
                        Text("Import \(parsed.count) Items").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if let error { Text(error).foregroundStyle(VaultColors.strengthWeak) }
        }
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
            parsed = VaultBackup.parseCSV(text)
            if parsed.isEmpty { error = "No items found in that file." }
        } else {
            error = "Unsupported file format."
        }
    }

    private func decrypt(_ data: Data) async {
        working = true; error = nil
        do {
            parsed = try await VaultBackup.importEncrypted(data, passphrase: passphrase)
            encryptedData = nil
            if parsed.isEmpty { error = "Backup contained no items." }
        } catch {
            self.error = "Couldn’t decrypt — check the password."
        }
        working = false
    }

    private func performImport() {
        for item in parsed { try? env.repository.add(item) }
        Haptics.success()
        dismiss()
    }
}
