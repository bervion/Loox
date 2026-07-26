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
    @State private var userRecordID = "unknown"
    /// nil until a scan has run — distinguishes "not looked yet" from "none".
    @State private var owned: [String]?
    @State private var accepted: [CKRecordZone.ID]?
    @State private var working = false

    var body: some View {
        List {
            Section("State") {
                row("Pending breadcrumb",
                    UserDefaults.standard.bool(forKey: SharedConfig.pendingShareAcceptanceKey) ? "SET" : "not set")
                row("Approval mode", env.settings.approvalModeEnabled ? "ON" : "off")
                row("Vault unlocked", env.session.vaultKey != nil ? "yes" : "LOCKED")
                row("CloudKit configured", CloudSyncService.isConfigured ? "yes" : "NO")
                row("Owner shares", "\(env.sharingStore.shares.count)")
                row("My iCloud userRecordID", userRecordID)
            }
            .listRowBackground(VaultColors.surface)

            Section {
                row("Zones I own", zoneSummary(owned))
                row("Shares I accepted", zoneSummary(accepted))
                Button("Scan CloudKit zones") { Task { await scanZones() } }
                    .disabled(working)

                // Accepted shared zones live on the iCloud ACCOUNT, so no
                // reinstall or vault erase can reach them, and the owner's
                // zone registry is UserDefaults that dies with the app. Both
                // sides therefore need a way to enumerate and drop what they
                // actually still hold. Neither action can touch the vault
                // zone: both filter on the `apz-` prefix.
                Button("Leave every accepted share", role: .destructive) {
                    Task { await leaveAllAccepted() }
                }
                .disabled(working || accepted?.isEmpty == true)

                Button("Revoke every zone I own", role: .destructive) {
                    Task { await revokeAllOwned() }
                }
                .disabled(working || owned?.isEmpty == true)
            } header: {
                Text("CloudKit zone cleanup")
            } footer: {
                Text("Revoking removes the share at its source, so recipients lose it too. "
                     + "Leaving only drops this account's copy. Your vault zone is never touched.")
            }
            .listRowBackground(VaultColors.surface)

            Section {
                Text(text.isEmpty ? "No diagnostics yet." : text)
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

    private func zoneSummary(_ names: [String]?) -> String {
        guard let names else { return "tap Scan" }
        return names.isEmpty ? "none" : "\(names.count): \(names.joined(separator: ", "))"
    }
    private func zoneSummary(_ ids: [CKRecordZone.ID]?) -> String {
        zoneSummary(ids?.map(\.zoneName))
    }

    private func scanZones() async {
        working = true
        defer { working = false }
        owned = (try? await env.approvalShare.ownedApprovalZoneNames()) ?? []
        accepted = (try? await env.approvalRecipient.acceptedApprovalZones()) ?? []
        reload()
    }

    /// Drops this account's copy of every accepted share. The owner's zones
    /// are untouched, so a share the owner still holds can be re-accepted.
    private func leaveAllAccepted() async {
        working = true
        defer { working = false }
        for zoneID in accepted ?? [] {
            do { try await env.approvalRecipient.leave(zoneID: zoneID) } catch {
                ShareDiagnostics.log("CLEANUP", "leave \(zoneID.zoneName) failed=\(error)")
            }
        }
        await scanZones()
    }

    /// Deletes the owner-side zones, which is what actually kills a share:
    /// every recipient's mirror disappears with it. Irreversible.
    private func revokeAllOwned() async {
        working = true
        defer { working = false }
        await env.approvalShare.revokeAllOwned()
        await scanZones()
    }
}
