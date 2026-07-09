import CloudKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// DEBUG-only viewer for the Approval-Mode share handshake log
/// (`ShareDiagnostics`). Reachable from Settings on both devices so the owner
/// and recipient logs can be read + copied out and compared side by side.
struct ShareDiagnosticsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var text = ""
    @State private var userRecordID = "—"

    var body: some View {
        List {
            Section("State") {
                row("Pending breadcrumb",
                    UserDefaults.standard.bool(forKey: SharedConfig.pendingShareAcceptanceKey) ? "SET" : "—")
                row("Approval mode", env.settings.approvalModeEnabled ? "ON" : "off")
                row("Vault unlocked", env.session.vaultKey != nil ? "yes" : "LOCKED")
                row("CloudKit configured", CloudSyncService.isConfigured ? "yes" : "NO")
                row("Owner shares", "\(env.sharingStore.shares.count)")
                row("My iCloud userRecordID", userRecordID)
            }
            .listRowBackground(VaultColors.surface)

            Section {
                Text(text.isEmpty ? "— no diagnostics yet —" : text)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } header: {
                Text("Log (### lines, newest last)")
            }
            .listRowBackground(VaultColors.surface)
        }
        .navigationTitle("Share Diagnostics")
        .platformNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Copy") {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = ShareDiagnostics.contents()
                    #endif
                }
                Button("Clear", role: .destructive) {
                    ShareDiagnostics.clear()
                    reload()
                }
            }
        }
        .refreshable { reload() }
        .task {
            reload()
            let container = CKContainer(identifier: ApprovalConfig.containerID)
            userRecordID = (try? await container.userRecordID())?.recordName ?? "unavailable"
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label).vaultType(.body).themedForeground()
            Spacer()
            Text(verbatim: value).vaultType(.footnote).themedForeground(.secondary)
        }
    }

    private func reload() { text = ShareDiagnostics.contents() }
}
