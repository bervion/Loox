import SwiftUI

/// Loox — a hub for the app's online/collaboration features: Private Email (per-persona
/// aliases), Share Links (per-item shares + approval requests), and the app-wide Approval
/// Mode toggle. Consolidates entry points that previously lived across Profile + Settings.
struct LooxHubScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var confirmApprovalOff = false

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s6) {
                // Private Email is per-persona.
                ProfileGroupCard {
                    ProfileNavRow(title: "Private Email", icon: Icons.mail) { PersonaAliasesScreen() }
                }
                // Sharing + approval are app-wide (independent of iCloud vault sync — ADR-2).
                ProfileGroupCard {
                    ProfileNavRow(title: "Share Links", icon: Icons.share) { NotificationsScreen() }
                    ProfileRowDivider()
                    approvalRow
                }
            }
            .padding(Space.gutter)
        }
        .background(Color(rgb: env.theme.active.groupedBackground).ignoresSafeArea())
        .navigationTitle("Loox")
        .platformNavigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Turn off Approval Mode?", isPresented: $confirmApprovalOff, titleVisibility: .visible) {
            Button("Turn Off", role: .destructive) {
                env.settings.approvalModeEnabled = false
                Haptics.tap()
            }
        } message: {
            Text("Logins you already shared stay shared. New approval requests and invites pause until you turn this back on.")
        }
    }

    /// Approval Mode — bound to the SAME `approvalModeEnabled` flag as Settings (single source
    /// of truth). Turning OFF asks for confirmation, matching the Settings behavior.
    private var approvalRow: some View {
        Toggle(isOn: Binding(
            get: { env.settings.approvalModeEnabled },
            set: { on in
                if on { env.settings.approvalModeEnabled = true } else { confirmApprovalOff = true }
            }
        )) {
            HStack(spacing: Space.s3) {
                ProfileRowTile(icon: Icons.shield)
                Text("Approval Mode").vaultType(.body).themedForeground()
            }
        }
        .tint(Color(rgb: env.theme.active.switchOn))
        .toggleStyle(.switch)
        .padding(.horizontal, Space.s4)
        .frame(minHeight: Metric.rowHeight)
    }
}
