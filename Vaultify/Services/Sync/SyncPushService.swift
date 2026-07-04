import CloudKit
import Foundation

/// Near-real-time sync: a silent CloudKit push subscription on the Vault zone.
/// When another device pushes a change, CloudKit delivers a content-available
/// notification (no alert, no user permission needed) → the app pulls the delta
/// within seconds instead of waiting for the next foreground activation.
///
/// The subscription is per-device state on the server; creation is guarded by a
/// local flag and retried on later syncs until it succeeds.
@MainActor final class SyncPushService {
    /// Stable id so re-saving is an upsert, and Erase Vault can delete it by name.
    static let subscriptionID = "vault-zone-changes"
    private static let subscribedKey = "cloudkit_zone_subscription_created"

    private lazy var container = CKContainer(identifier: "iCloud.com.bervion.vaultify")

    /// Create the silent zone subscription once (no-op after success).
    func ensureSubscribedIfNeeded() async {
        guard CloudSyncService.isConfigured else { return }
        guard !UserDefaults.standard.bool(forKey: Self.subscribedKey) else { return }
        // Same zone CloudSyncService owns; only its records change, so a zone
        // subscription is exactly the wake-up signal we need.
        let subscription = CKRecordZoneSubscription(
            zoneID: CKRecordZone.ID(zoneName: "Vault"),
            subscriptionID: Self.subscriptionID)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true // silent push — no banner, no permission
        subscription.notificationInfo = info
        do {
            _ = try await container.privateCloudDatabase
                .modifySubscriptions(saving: [subscription], deleting: [])
            UserDefaults.standard.set(true, forKey: Self.subscribedKey)
        } catch {
            // Best-effort: retried after the next successful sync.
        }
    }

    /// Forget the local "subscribed" marker (vault erase) so a future vault
    /// re-creates the subscription.
    static func clearLocalFlag() {
        UserDefaults.standard.removeObject(forKey: subscribedKey)
    }
}

extension Notification.Name {
    /// Posted by the app delegate when a CloudKit silent push signals that
    /// another device changed the vault; the sync coordinator pulls in response.
    static let vaultRemoteChangePush = Notification.Name("vaultRemoteChangePush")
}
