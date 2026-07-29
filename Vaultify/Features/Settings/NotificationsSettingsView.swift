import SwiftUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

/// Notifications settings: system permission status (read-only here — iOS owns the
/// grant) plus the one in-app notification category Loox actually schedules, rotation
/// reminders. No invented categories: `RotationNotificationService` is the only
/// scheduler in the app today.
struct NotificationsSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text(statusLabel).themedForeground(statusRole)
                } label: {
                    Label { Text("Notification permission") } icon: { VaultIcon(Icons.notification) }
                }
                if authorizationStatus == .denied {
                    // Denied is a blocked state with a remedy the user owns, not
                    // a soft warning: reminders below cannot fire at all.
                    VaultInfoBanner(.error,
                                    text: "Notifications are turned off for Loox in iOS Settings. Turn them back on to receive rotation reminders.",
                                    actionLabel: "Open Settings",
                                    action: openSystemSettings)
                    .inList()
                }
            } footer: {
                Text("Controlled by iOS. Loox only asks once, the first time you turn on a reminder below.")
            }
            .listRowBackground(VaultColors.surface)

            Section {
                Toggle(isOn: rotationRemindersBinding) {
                    Label { Text("Rotation reminders") } icon: { VaultIcon(Icons.refresh) }
                }
            } footer: {
                Text("Get a local notification on the day a password is due to rotate. The notification shows only the item name, never a password or username.")
            }
            .listRowBackground(VaultColors.surface)

            Section {
                Toggle(isOn: auditRemindersBinding) {
                    Label { Text("Security checkup reminders") } icon: { VaultIcon(Icons.shieldPerson) }
                }
            } footer: {
                Text("Get a reminder every two weeks to open Loox and check your vault's health. The notification shows no scores or item details.")
            }
            .listRowBackground(VaultColors.surface)
        }
        .themedFormBackground()
        .toggleStyle(.switch)
        .tint(Color(rgb: env.theme.active.switchOn))
        .navigationTitle("Notifications")
        .platformNavigationBarTitleDisplayMode(.inline)
        .task { await refreshAuthorizationStatus() }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await refreshAuthorizationStatus() }
        }
    }

    private var rotationRemindersBinding: Binding<Bool> {
        Binding(
            get: { env.settings.rotationRemindersEnabled },
            set: { isOn in
                env.settings.rotationRemindersEnabled = isOn
                Haptics.tap()
            })
    }

    private var auditRemindersBinding: Binding<Bool> {
        Binding(
            get: { env.settings.auditRemindersEnabled },
            set: { isOn in
                env.settings.auditRemindersEnabled = isOn
                // Turning off cancels immediately; turning on lets the next audit
                // (or a Security-tab visit) schedule the reminder.
                if !isOn { AuditReminderNotificationService.shared.cancel() }
                Haptics.tap()
            })
    }

    private var statusLabel: LocalizedStringKey {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "Allowed"
        case .denied: return "Not allowed"
        case .notDetermined: return "Not requested yet"
        @unknown default: return "Not requested yet"
        }
    }

    private var statusRole: ThemeRole {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .success
        case .denied: return .warning
        default: return .secondary
        }
    }

    private func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    private func openSystemSettings() {
        #if canImport(UIKit) && os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}
