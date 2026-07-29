import SwiftUI

/// Notification-permission gate embedded in a flow that needs alerts (sharing
/// approval today; onboarding and tutorials reuse it with their own copy).
/// Three jobs: explain WHY before the one-shot OS prompt ever fires, fire that
/// prompt only on the user's explicit tap, and — after a denial — route to the
/// system Settings toggle instead of a dead "try again" (iOS never re-asks).
struct NotificationPermissionGateView: View {
    /// What the surrounding flow needs notifications FOR — context copy shown
    /// above the action. Each caller supplies its own.
    let explanation: LocalizedStringKey
    /// False → never asked: explainer + "Allow Notifications" (fires the OS
    /// prompt). True → previously denied: explainer + "Open Settings".
    let denied: Bool
    /// Re-run the owner's prerequisite check. Called after the OS prompt
    /// resolves (either answer), and by "Check again" for the return trip from
    /// Settings — the owner decides where the flow goes next.
    let recheck: () -> Void

    var body: some View {
        VStack(spacing: Space.s4) {
            VaultIcon(Icons.notification, size: Metric.iconTile)
                .themedForeground(.warning)
            Text("Notification permission")
                .vaultType(.section).themedForeground()
            Text(explanation)
                .vaultType(.callout).themedForeground(.secondary)
                .multilineTextAlignment(.center)
            if denied {
                Button { PlatformAppearance.openNotificationSettings() } label: {
                    Text("Open Settings").frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedProminent)
                Button(action: recheck) {
                    Text("Check again").frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedTinted)
            } else {
                Button {
                    Task {
                        _ = await ApprovalPrerequisites.requestNotificationPermission()
                        recheck()
                    }
                } label: {
                    Text("Allow Notifications").frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedProminent)
            }
        }
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
