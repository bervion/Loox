import CloudKit
import Foundation
import UserNotifications

/// Runtime gates for Approval Mode (ADR-2). Both are FAIL-CLOSED:
/// - iCloud account must be `.available` (checked live, never assumed from the
///   compile flag or the vault-sync toggle).
/// - Notification authorization must be granted before any `askEachTime` grant
///   can exist — a request the owner never sees would strand the recipient.
@MainActor enum ApprovalPrerequisites {
    enum Blocker: Equatable {
        /// No usable iCloud account (signed out, restricted, temporarily unavailable).
        case iCloudUnavailable
        /// Never asked yet. `check()` deliberately does NOT fire the OS prompt:
        /// mid-state-machine it appears with zero context and a denial is
        /// near-permanent (iOS never re-asks). The sheet shows its own
        /// explainer first and calls `requestNotificationPermission()` when the
        /// user opts in.
        case notificationsNotAsked
        /// User declined alert notifications — approval requests can't surface.
        case notificationsDenied
    }

    /// Check both gates without side effects. Returns nil when Approval Mode
    /// may proceed.
    static func check() async -> Blocker? {
        guard CloudSyncService.isConfigured else { return .iCloudUnavailable }
        let status = try? await CKContainer(identifier: ApprovalConfig.containerID).accountStatus()
        guard status == .available else { return .iCloudUnavailable }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return nil
        case .notDetermined:
            return .notificationsNotAsked
        case .denied:
            return .notificationsDenied
        @unknown default:
            return .notificationsDenied
        }
    }

    /// Fire the OS permission prompt. Callers show their pre-permission
    /// explainer BEFORE this, and re-run `check()` after it resolves.
    static func requestNotificationPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }
}
