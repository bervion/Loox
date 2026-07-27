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
            // The list stays: Copy / Share / Save PDF / Regenerate are real
            // action rows and read best with list chrome. Only the framing moves
            // — the swirl header rides in a chrome-less first section so this
            // screen opens like its two security siblings.
            Section {
                header
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: Space.s4, trailing: 0))
                    .listRowBackground(Color.clear)
                // Same banner chrome as the other security subscreens — a raw Label
                // with an accent icon read as a stray row, not the framing note.
                VaultInfoBanner(.info, icon: Icons.shield, text: kitStatusText)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            // Two chrome-less rows in one section would otherwise be split by a
            // hairline running across the empty page.
            .listRowSeparator(.hidden)

            if !newKey.isEmpty {
                Section {
                    Text(newKey)
                        .font(.vaultCode(.body, weight: .medium))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s2)
                    Button { env.clipboard.copy(newKey, label: appString("recovery key")) } label: {
                        Label { Text("Copy") } icon: { PolarisIcon(Icons.copy) }
                    }
                    ShareLink(item: newKey) { Label { Text("Share") } icon: { PolarisIcon(Icons.share) } }
                    // Export glyph, not a shield: this row hands the kit to the
                    // Files sheet, it doesn't say anything about protection.
                    Button(action: presentExporter) {
                        Label { Text("Save Emergency Kit (PDF)") } icon: { PolarisIcon(Icons.exportData) }
                    }
                    if let exportError {
                        Text(exportError).vaultType(.footnote)
                            .foregroundStyle(env.theme.active.color(.destructive))
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
                    // `Icons.refresh` is the app's sync glyph — it read as
                    // "fetch again", not "issue a new kit". A key for the first
                    // issue, a replay arrow for a re-issue.
                    Label { Text(env.session.hasRecoveryKit ? "Regenerate Kit" : "Generate Kit") }
                        icon: { PolarisIcon(env.session.hasRecoveryKit ? Icons.replay : Icons.key) }
                }
                .disabled(busy)
                if let generateError {
                    Text(generateError).vaultType(.footnote)
                        .foregroundStyle(env.theme.active.color(.destructive))
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
        // Extension in the name on purpose — iOS's fileExporter doesn't reliably
        // append it from the content type (see EmergencyKitInfo.suggestedFilename).
        .fileExporter(isPresented: $showExporter, document: pdfFile, contentType: .pdf,
                      defaultFilename: "Loox Emergency Kit.pdf") { result in
            if case .failure(let error) = result, (error as NSError).code != NSUserCancelledError {
                exportError = appString("Couldn’t save the Emergency Kit. Please try again.")
                Haptics.error()
            } else {
                exportError = nil
                if case .success = result { Haptics.success() }
            }
        }
    }

    /// One-shot swirl reveal around a life ring (recovery, not protection),
    /// then the title and subtitle — the shape the Extra Password and master
    /// password screens use.
    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            LooxSwirlAnimationView(mode: .reveal,
                                   centerIcon: "dt_life_ring",
                                   centerTint: env.theme.active.color(.accent))
                .frame(width: 150, height: 150)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s4)
            Text("Your Emergency Kit")
                .vaultType(.screenTitle)
            Text("The recovery key can restore your vault if you forget your master password.")
                .vaultType(.subhead).themedForeground(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kitStatusText: LocalizedStringKey {
        env.session.hasRecoveryKit
            ? "An Emergency Kit is set up for this vault."
            : "No Emergency Kit yet. Generate one to enable recovery."
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
            // A regenerated key invalidates the synced envelope for future
            // joins — push the replacement now, not on the next item sync.
            env.syncNow()
            Haptics.success()
        } catch {
            generateError = appString("Couldn’t generate a new recovery key. Please try again.")
            Haptics.error()
        }
        busy = false
    }
}
