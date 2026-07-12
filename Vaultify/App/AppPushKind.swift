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
    case inviteRendezvous
    case shareAcceptance

    static func classify(_ notification: CKNotification) -> AppPushKind {
        guard let subscriptionID = notification.subscriptionID else {
            // No subscription id → legacy/unknown; preserve pre-routing behavior.
            return .vaultRemoteChange
        }
        if subscriptionID.hasPrefix(ApprovalConfig.requestSubscriptionPrefix) {
            return .approvalRequest
        }
        if subscriptionID.hasPrefix(ApprovalConfig.acceptSubscriptionPrefix) {
            return .shareAcceptance
        }
        if subscriptionID == ApprovalConfig.sharedDatabaseSubscriptionID {
            return .approvalResponse
        }
        if subscriptionID == ApprovalConfig.inviteInboxSubscriptionID {
            return .inviteRendezvous
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
    /// A public-db invite drop addressed to this account's inbox (U5).
    /// Push = hint only; observers reconcile against the public-db inbox.
    static let inviteRendezvousReceived = Notification.Name("inviteRendezvousReceived")
    /// A recipient's device published its identity profile into one of this
    /// owner's approval zones (silent push). Hint-only, no payload — observers
    /// re-resolve share status against CloudKit, same contract as the hints
    /// above.
    static let shareAcceptanceHint = Notification.Name("shareAcceptanceHint")
}

/// Cold-launch mailbox for an invite universal link: the scene delegate
/// receives the NSUserActivity BEFORE any SwiftUI observer exists, so a
/// bare NotificationCenter post would vanish. The delegate both posts (warm
/// path) and buffers here; the app root drains the buffer once it appears.
@MainActor enum PendingInviteLink {
    static var url: URL?
}
