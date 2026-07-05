import CloudKit
import SwiftUI
import UserNotifications

/// Receives CloudKit pushes and routes them by `AppPushKind` (ADR-5):
/// - `vaultRemoteChange` — silent zone push from `SyncPushService`'s
///   subscription → `.vaultRemoteChangePush` → `SyncCoordinator` pulls.
/// - `approvalRequest` — user-visible alert push (participant wrote a request
///   into an approval zone) → `.approvalRequestReceived`.
/// - `approvalResponse` — silent shared-db push (owner answered) →
///   `.approvalResponseReceived`.
/// Decoupled via NotificationCenter because the delegate is created by the
/// adaptor before `AppEnvironment` exists.
#if canImport(UIKit)
final class AppPushDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Silent CloudKit pushes need remote-notification registration; this never
        // shows a permission prompt (alert notifications are a separate opt-in).
        application.registerForRemoteNotifications()
        // Tap-routing for user-visible pushes (approval requests) and foreground
        // presentation policy. Rotation reminders keep their default behavior.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Inject a scene delegate so CKShare invitations can be accepted
    /// (`windowScene(_:userDidAcceptCloudKitShareWith:)`); SwiftUI still owns
    /// the window — the delegate only listens.
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = VaultSceneDelegate.self
        return config
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard let ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            completionHandler(.noData)
            return
        }
        Self.route(ckNotification)
        // The pull runs async via the coordinator; report newData so iOS keeps
        // scheduling background deliveries for this app.
        completionHandler(.newData)
    }

    static func route(_ notification: CKNotification) {
        switch AppPushKind.classify(notification) {
        case .vaultRemoteChange:
            NotificationCenter.default.post(name: .vaultRemoteChangePush, object: nil)
        case .approvalRequest:
            NotificationCenter.default.post(name: .approvalRequestReceived, object: nil)
        case .approvalResponse:
            NotificationCenter.default.post(name: .approvalResponseReceived, object: nil)
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    /// The owner tapped the approval alert → open straight into the pending
    /// request (verification happens before any approval UI is shown).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) {
            Self.route(ckNotification)
        }
        completionHandler()
    }

    /// Foreground policy: approval alerts still banner (the owner may have the
    /// app open on another screen); everything else keeps the pre-delegate
    /// default of not presenting while foregrounded.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        if let ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo),
           AppPushKind.classify(ckNotification) == .approvalRequest {
            // Foreground owner: surface the pending request immediately (no tap
            // needed) — the alert push carries no fetch payload by design.
            Self.route(ckNotification)
            completionHandler([.banner, .sound, .list])
        } else {
            completionHandler([])
        }
    }
}

/// Accepts CKShare invitations (approval-zone shares) AND receives universal
/// links: once a custom scene delegate exists, UIKit routes NSUserActivity
/// continuation HERE — SwiftUI's `onContinueUserActivity` never fires — so
/// both the warm-tap and cold-launch paths must be forwarded explicitly.
final class VaultSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        VaultSceneDelegate.accept(cloudKitShareMetadata)
    }

    /// Warm tap: app already running, user taps an invite link.
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        forwardInviteLink(in: userActivity)
    }

    /// Cold launch: the tap started the app; the activity rides the
    /// connection options instead of `continue`.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        for activity in connectionOptions.userActivities {
            forwardInviteLink(in: activity)
        }
    }

    private func forwardInviteLink(in activity: NSUserActivity) {
        guard activity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = activity.webpageURL,
              InviteLinkService.isInviteLink(url) else { return }
        NotificationCenter.default.post(name: .inviteLinkReceived, object: url)
    }

    static func accept(_ metadata: CKShare.Metadata) {
        Task {
            // Routing-only breadcrumb (Validation §3), set BEFORE the accept:
            // a crash between accept-success and flag-write would otherwise
            // leave a server-side acceptance with no local resume. A flag with
            // no acceptance behind it is harmless (resume no-ops and clears).
            UserDefaults.standard.set(true, forKey: SharedConfig.pendingShareAcceptanceKey)
            do {
                let container = CKContainer(identifier: ApprovalConfig.containerID)
                _ = try await container.accept(metadata)
                NotificationCenter.default.post(name: .vaultShareAccepted, object: nil)
            } catch {
                // Best-effort: the inviter can re-send; the recipient can re-tap.
            }
        }
    }
}
#elseif canImport(AppKit)
final class AppPushDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.registerForRemoteNotifications()
    }

    func application(_ application: NSApplication,
                     didReceiveRemoteNotification userInfo: [String: Any]) {
        guard let ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) else { return }
        switch AppPushKind.classify(ckNotification) {
        case .vaultRemoteChange:
            NotificationCenter.default.post(name: .vaultRemoteChangePush, object: nil)
        case .approvalRequest:
            NotificationCenter.default.post(name: .approvalRequestReceived, object: nil)
        case .approvalResponse:
            NotificationCenter.default.post(name: .approvalResponseReceived, object: nil)
        }
    }

    func application(_ application: NSApplication,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task {
            do {
                let container = CKContainer(identifier: ApprovalConfig.containerID)
                _ = try await container.accept(metadata)
                NotificationCenter.default.post(name: .vaultShareAccepted, object: nil)
            } catch {
                // Best-effort, mirroring the iOS branch: post only on success.
            }
        }
    }
}
#endif
