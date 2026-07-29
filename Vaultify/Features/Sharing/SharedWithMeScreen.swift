import CloudKit
import SwiftUI

/// Route value for the Home → Shared-with-me navigation.
nonisolated struct SharedWithMeRoute: Hashable {}

/// The Shared-with-Me SPACE (V1.2 — a standard item list, not a custom zone
/// browser): rows are the projected shared items, tap opens the ordinary
/// item detail. Nothing here touches the local vault store.
struct SharedWithMeScreen: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Group {
            if env.sharedItems.items.isEmpty {
                ContentUnavailableView {
                    Label { Text("Nothing shared with you yet") } icon: {
                        VaultIcon(Icons.shield, size: Metric.iconTileLarge)
                    }
                } description: {
                    Text("When someone shares access with you, it appears here.")
                }
            } else {
                List(env.sharedItems.items) { item in
                    VaultItemRowLink(item: item)
                        .listRowBackground(VaultColors.surface)
                }
                .themedFormBackground()
            }
        }
        .background(Color(rgb: env.theme.active.groupedBackground).ignoresSafeArea())
        .navigationTitle("Shared with Me")
        .platformNavigationBarTitleDisplayMode(.inline)
        .task(id: env.approvalCoordinator.recipientChangeCounter) { await refresh() }
    }

    private func refresh() async {
        guard let vaultKey = env.session.vaultKey?.bytes else { return }
        // Safety net for a silently-failed acceptance resume: re-run the
        // idempotent completion (escrow → profile publish → subscription)
        // whenever the vault is unlocked, so the owner's waiting screen can
        // always find the profile once B visits this screen.
        if let identity = try? await env.participantEscrow.ensureIdentity(vaultKey: vaultKey) {
            // Burn the resume breadcrumb ONLY once a profile was actually
            // published (≥1 zone) — an offline visit, or one before the accepted
            // zone has propagated into the shared DB, publishes nothing and must
            // not disable the shell's auto-resume.
            if let published = try? await env.approvalRecipient.completeAcceptance(
                identity: identity,
                nowUnixMs: Int64(Date().timeIntervalSince1970 * 1000)), published > 0 {
                UserDefaults.standard.removeObject(forKey: SharedConfig.pendingShareAcceptanceKey)
            }
            await SharedZoneSubscriptionService().ensureSubscribedIfNeeded(settings: env.settings)
        }
        await env.sharedItems.refresh(vaultKey: vaultKey)
    }
}
