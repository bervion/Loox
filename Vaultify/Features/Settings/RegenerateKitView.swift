import SwiftUI
import UniformTypeIdentifiers

/// View / regenerate the Emergency Kit recovery key. Generating a new key
/// invalidates the previous one.
struct RegenerateKitView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var newKey = ""
    @State private var busy = false
    @State private var confirmRegenerate = false
    @State private var showExporter = false
    @State private var pdfFile: EmergencyKitPDFFile?
    @State private var exportError: String?
    @State private var generateError: String?

    var body: some View {
        Form {
            Section {
                Label {
                    Text(env.session.hasRecoveryKit
                         ? "An Emergency Kit is set up for this vault."
                         : "No Emergency Kit yet. Generate one to enable recovery.")
                } icon: {
                    PolarisIcon(Icons.shield).foregroundStyle(Color.accentColor)
                }
            } footer: {
                Text("The recovery key can restore your vault if you forget your master password.")
            }
            .listRowBackground(VaultColors.surface)

            if !newKey.isEmpty {
                Section {
                    Text(newKey)
                        .font(.vaultCode(.body, weight: .medium))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s2)
                    Button { env.clipboard.copy(newKey, label: "Recovery key") } label: {
                        Label { Text("Copy") } icon: { PolarisIcon(Icons.copy) }
                    }
                    ShareLink(item: newKey) { Label { Text("Share") } icon: { PolarisIcon(Icons.share) } }
                    Button(action: presentExporter) {
                        Label { Text("Save Emergency Kit (PDF)") } icon: { PolarisIcon(Icons.shield) }
                    }
                    if let exportError {
                        Text(exportError).vaultType(.footnote).foregroundStyle(VaultColors.strengthWeak)
                    }
                } header: {
                    Text("Your new recovery key")
                } footer: {
                    Text("Store it somewhere safe and offline. It is shown only once.")
                }
                .listRowBackground(VaultColors.surface)
            }

            Section {
                Button {
                    if env.session.hasRecoveryKit { confirmRegenerate = true } else { Task { await regenerate() } }
                } label: {
                    Label { Text(env.session.hasRecoveryKit ? "Regenerate Kit" : "Generate Kit") } icon: { PolarisIcon(Icons.refresh) }
                }
                .disabled(busy)
                if let generateError {
                    Text(generateError).vaultType(.footnote).foregroundStyle(VaultColors.strengthWeak)
                }
            }
            .listRowBackground(VaultColors.surface)
        }
        .themedFormBackground()
        .navigationTitle("Emergency Kit")
        .platformNavigationBarTitleDisplayMode(.inline)
        .overlay { if busy { ProgressView().controlSize(.large) } }
        .confirmationDialog("Regenerate recovery key?", isPresented: $confirmRegenerate, titleVisibility: .visible) {
            Button("Regenerate", role: .destructive) { Task { await regenerate() } }
        } message: {
            Text("Your previous recovery key will stop working.")
        }
        .fileExporter(isPresented: $showExporter, document: pdfFile, contentType: .pdf,
                      defaultFilename: "Loox Emergency Kit") { result in
            if case .failure(let error) = result, (error as NSError).code != NSUserCancelledError {
                exportError = appString("Couldn’t save the Emergency Kit. Please try again.")
                Haptics.error()
            } else {
                exportError = nil
                if case .success = result { Haptics.success() }
            }
        }
    }

    /// Build the kit PDF from the just-shown key and present the save sheet. Owner name /
    /// iCloud account are left blank here (those rows are omitted) — the recovery key, Setup
    /// Code, warning, and instructions are what matter for a re-print.
    private func presentExporter() {
        let info = EmergencyKitInfo(recoveryKey: newKey, ownerName: "", iCloudAccount: "", createdAt: .now)
        guard let data = EmergencyKitPDF.makeData(info) else {
            exportError = appString("Couldn’t build the Emergency Kit PDF. Please try again.")
            return
        }
        pdfFile = EmergencyKitPDFFile(data: data)
        showExporter = true
    }

    private func regenerate() async {
        busy = true; generateError = nil
        do {
            newKey = try await env.session.generateRecoveryKit()
            Haptics.success()
        } catch {
            generateError = appString("Couldn’t generate a new recovery key. Please try again.")
            Haptics.error()
        }
        busy = false
    }
}
