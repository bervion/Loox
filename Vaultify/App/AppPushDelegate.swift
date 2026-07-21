import CloudKit
import SwiftUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

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
        guard !UITestConfiguration.current.isEnabled,
              !CloudSyncService.isHostingUnitTests else { return true }
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
        let kind = AppPushKind.classify(ckNotification)
        Self.route(ckNotification)
        switch kind {
        case .shareAcceptance, .vaultRemoteChange:
            // Silent content-available pushes trigger real CloudKit work
            // (share-status refresh / delta pull). Calling the completion
            // handler tells iOS it may suspend the process — returning it
            // before the work finishes races that suspension: the refresh
            // dies mid-flight, the "accepted" banner never posts, and
            // nothing retries until the next foreground. Hold the handler
            // until the work completes, bounded so a hung fetch can't burn
            // the whole background window. Report newData either way so iOS
            // keeps scheduling background deliveries for this app.
            let completion = PushFetchCompletion(application: application,
                                                 handler: completionHandler)
            Task {
                await SilentPushWork.awaitWork(for: kind)
                completion.finish()
            }
            Task {
                try? await Task.sleep(for: .seconds(20))
                completion.finish()
            }
        case .approvalRequest, .approvalResponse, .inviteRendezvous:
            // Alert pushes carry no fetch payload, and the response hint is
            // consumed by a foreground requester UI — nothing to keep alive.
            completionHandler(.newData)
        }
    }

    static func route(_ notification: CKNotification) {
        switch AppPushKind.classify(notification) {
        case .vaultRemoteChange:
            NotificationCenter.default.post(name: .vaultRemoteChangePush, object: nil)
        case .approvalRequest:
            NotificationCenter.default.post(name: .approvalRequestReceived, object: nil)
        case .approvalResponse:
            NotificationCenter.default.post(name: .approvalResponseReceived, object: nil)
        case .inviteRendezvous:
            NotificationCenter.default.post(name: .inviteRendezvousReceived, object: nil)
        case .shareAcceptance:
            NotificationCenter.default.post(name: .shareAcceptanceHint, object: nil)
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    /// The owner tapped the approval alert → open straight into the pending
    /// request (verification happens before any approval UI is shown).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        // Local share-status banner first: its userInfo carries no CloudKit
        // payload (the CK parse would fall through anyway — explicit ordering
        // documents the intent). Buffer BEFORE posting: a cold-launch tap runs
        // before any SwiftUI observer exists.
        if let zoneName = userInfo[ShareStatusNotifier.zoneNameUserInfoKey] as? String {
            PendingShareResumeTap.zoneName = zoneName
            NotificationCenter.default.post(name: .shareResumeTapRequested, object: nil)
        } else if let ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) {
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
           [.approvalRequest, .inviteRendezvous].contains(AppPushKind.classify(ckNotification)) {
            // Foreground: surface the pending request / invite immediately (no
            // tap needed) — these alert pushes carry no fetch payload by design.
            Self.route(ckNotification)
            completionHandler([.banner, .sound, .list])
        } else {
            completionHandler([])
        }
    }
}

/// One-shot wrapper around a background-fetch completion handler: whichever
/// finishes first (triggered work done, bounded timeout, or the system
/// reclaiming the background window) reports exactly once, and the paired
/// background-task assertion is always released alongside it. The assertion
/// documents the in-flight CloudKit work to the system and supplies the
/// expiration callback used to report just before a forced suspension.
@MainActor final class PushFetchCompletion {
    private var handler: ((UIBackgroundFetchResult) -> Void)?
    private var taskID: UIBackgroundTaskIdentifier = .invalid
    private let application: UIApplication

    init(application: UIApplication,
         handler: @escaping (UIBackgroundFetchResult) -> Void) {
        self.application = application
        self.handler = handler
        taskID = application.beginBackgroundTask(withName: "vaultify-silent-push-refresh") { [weak self] in
            // Expiration handlers are invoked on the main thread.
            MainActor.assumeIsolated { self?.finish() }
        }
    }

    func finish() {
        guard let handler else { return }
        self.handler = nil
        handler(.newData)
        if taskID != .invalid {
            application.endBackgroundTask(taskID)
            taskID = .invalid
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
        // Buffer FIRST: on a cold launch this runs before any SwiftUI
        // observer exists, and an unheard post is a silently dead link —
        // the app root drains the buffer when it appears.
        PendingInviteLink.url = url
        NotificationCenter.default.post(name: .inviteLinkReceived, object: url)
    }

    static func accept(_ metadata: CKShare.Metadata) {
        Task {
            // Routing-only breadcrumb (Validation §3), set BEFORE the accept:
            // a crash between accept-success and flag-write would otherwise
            // leave a server-side acceptance with no local resume. A flag with
            // no acceptance behind it is harmless (resume no-ops and clears).
            UserDefaults.standard.set(true, forKey: SharedConfig.pendingShareAcceptanceKey)
            ShareDiagnostics.log("ACCEPT", "native scene accept — breadcrumb set")
            do {
                let container = CKContainer(identifier: ApprovalConfig.containerID)
                _ = try await container.accept(metadata)
                ShareDiagnostics.log("ACCEPT", "native container.accept OK (share=\(metadata.share.recordID.zoneID.zoneName))")
                NotificationCenter.default.post(name: .vaultShareAccepted, object: nil)
            } catch {
                // Best-effort: the inviter can re-send; the recipient can re-tap.
                ShareDiagnostics.log("ACCEPT", "native container.accept ERROR: \(error)")
            }
        }
    }
}
#elseif canImport(AppKit)
final class AppPushDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !UITestConfiguration.current.isEnabled,
              !CloudSyncService.isHostingUnitTests else { return }
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
        case .inviteRendezvous:
            NotificationCenter.default.post(name: .inviteRendezvousReceived, object: nil)
        case .shareAcceptance:
            NotificationCenter.default.post(name: .shareAcceptanceHint, object: nil)
        }
    }

    func application(_ application: NSApplication,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task {
            // Routing breadcrumb set BEFORE accept (parity with the iOS branch):
            // without it, a Mac acceptor's profile publish only resumes when the
            // user happens to open "Shared with Me" — leaving the owner stuck on
            // "Waiting". A flag with no acceptance behind it is a harmless no-op.
            UserDefaults.standard.set(true, forKey: SharedConfig.pendingShareAcceptanceKey)
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
