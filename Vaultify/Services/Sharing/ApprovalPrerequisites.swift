import CloudKit
import Foundation
import UserNotifications

/// Runtime gates for Approval Mode (ADR-2). Both are FAIL-CLOSED:
/// - iCloud account must be `.available` (checked live, never assumed from the
///   compile flag or the vault-sync toggle).
/// - Notification authorization must be granted before any `askEachTime` grant
///   can exist — a request the owner never sees would strand the recipient.
@MainActor enum ApprovalPrerequisites {
    enum Blocker {
        /// No usable iCloud account (signed out, restricted, temporarily unavailable).
        case iCloudUnavailable
        /// User declined alert notifications — approval requests can't surface.
        case notificationsDenied
    }

    /// Check both gates, prompting for notification permission if it was never
    /// asked. Returns nil when Approval Mode may proceed.
    static func check() async -> Blocker? {
        guard CloudSyncService.isConfigured else { return .iCloudUnavailable }
        let status = try? await CKContainer(identifier: ApprovalConfig.containerID).accountStatus()
        guard status == .available else { return .iCloudUnavailable }
        return await notificationsAuthorized() ? nil : .notificationsDenied
    }

    private static func notificationsAuthorized() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            // First entry into the sharing flow → prompt now (never at launch).
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
}
