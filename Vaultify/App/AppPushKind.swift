import CloudKit
import Foundation

/// Routes an incoming CloudKit push to its pipeline (ADR-5). Sync stays a
/// silent content-available push; approval requests are user-visible alert
/// pushes and must NEVER flow through `.vaultRemoteChangePush` — that observer
/// early-returns when `iCloudSyncEnabled == false`, and Approval Mode works
/// independently of the vault-sync toggle.
nonisolated enum AppPushKind {
    case vaultRemoteChange
    case approvalRequest
    case approvalResponse

    static func classify(_ notification: CKNotification) -> AppPushKind {
        guard let subscriptionID = notification.subscriptionID else {
            // No subscription id → legacy/unknown; preserve pre-routing behavior.
            return .vaultRemoteChange
        }
        if subscriptionID.hasPrefix(ApprovalConfig.requestSubscriptionPrefix) {
            return .approvalRequest
        }
        if subscriptionID == ApprovalConfig.sharedDatabaseSubscriptionID {
            return .approvalResponse
        }
        // `SyncPushService.subscriptionID` and anything else → sync pull. An
        // unknown id defaulting to a pull is harmless (pull is idempotent);
        // defaulting to an approval route would be wrong.
        return .vaultRemoteChange
    }
}

extension Notification.Name {
    /// A participant asked for an `askEachTime` capability — the owner app
    /// surfaces the pending request (after verification) in the foreground
    /// approval ceremony. Payload stays opaque: no item, account, or code.
    static let approvalRequestReceived = Notification.Name("approvalRequestReceived")
    /// The owner answered — the requester pulls the sealed response.
    static let approvalResponseReceived = Notification.Name("approvalResponseReceived")
    /// A CKShare invitation was accepted on this device (userInfo-free; the
    /// accept already ran — observers refresh their shared-zone state).
    static let vaultShareAccepted = Notification.Name("vaultShareAccepted")
    /// An invite universal link arrived via the scene delegate (`object` =
    /// the URL); the app root resolves + accepts and surfaces the outcome.
    static let inviteLinkReceived = Notification.Name("inviteLinkReceived")
}
