import CloudKit
import Foundation

/// Participant-side push: a silent `CKDatabaseSubscription` on the SHARED
/// database, so the requester learns immediately when the owner writes an
/// approval response (or any shared-zone change) instead of polling.
///
/// Mirrors `SyncPushService`'s guarded-flag pattern but stays a separate
/// service: it watches a different database, is gated by `approvalModeEnabled`
/// (never by `iCloudSyncEnabled`), and routes to `.approvalResponseReceived`.
/// The common CloudKit-subscription bit gets extracted in the transport phase.
@MainActor final class SharedZoneSubscriptionService {
    static let subscriptionID = ApprovalConfig.sharedDatabaseSubscriptionID
    private static let subscribedKey = "cloudkit_shared_db_subscription_created"

    private lazy var container = CKContainer(identifier: ApprovalConfig.containerID)

    /// Create the silent shared-db subscription once (no-op after success).
    /// Retried on later approval activity until it succeeds. Gated by the
    /// caller-owned `approvalModeEnabled` — NEVER by `iCloudSyncEnabled`.
    func ensureSubscribedIfNeeded(settings: SettingsStore) async {
        guard CloudSyncService.isConfigured, settings.approvalModeEnabled else { return }
        guard !UserDefaults.standard.bool(forKey: Self.subscribedKey) else { return }
        let subscription = CKDatabaseSubscription(subscriptionID: Self.subscriptionID)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true // silent — the ALERT push is owner-side only
        subscription.notificationInfo = info
        do {
            _ = try await container.sharedCloudDatabase
                .modifySubscriptions(saving: [subscription], deleting: [])
            UserDefaults.standard.set(true, forKey: Self.subscribedKey)
        } catch {
            // Best-effort: retried on the next approval-mode activation.
        }
    }

    /// Forget the local marker (vault erase / approval-mode teardown) so a
    /// future activation re-creates the subscription.
    static func clearLocalFlag() {
        UserDefaults.standard.removeObject(forKey: subscribedKey)
    }
}
