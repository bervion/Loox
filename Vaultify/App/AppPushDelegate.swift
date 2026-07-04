import CloudKit
import SwiftUI

/// Receives CloudKit silent pushes (registered by `SyncPushService`'s zone
/// subscription) and turns them into a `.vaultRemoteChangePush` notification the
/// `SyncCoordinator` reacts to. Decoupled via NotificationCenter because the
/// delegate is created by the adaptor before `AppEnvironment` exists.
#if canImport(UIKit)
final class AppPushDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Silent CloudKit pushes need remote-notification registration; this never
        // shows a permission prompt (alert notifications are a separate opt-in).
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            completionHandler(.noData)
            return
        }
        NotificationCenter.default.post(name: .vaultRemoteChangePush, object: nil)
        // The pull runs async via the coordinator; report newData so iOS keeps
        // scheduling background deliveries for this app.
        completionHandler(.newData)
    }
}
#elseif canImport(AppKit)
final class AppPushDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.registerForRemoteNotifications()
    }

    func application(_ application: NSApplication,
                     didReceiveRemoteNotification userInfo: [String: Any]) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else { return }
        NotificationCenter.default.post(name: .vaultRemoteChangePush, object: nil)
    }
}
#endif
