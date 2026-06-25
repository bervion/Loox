import Foundation
import UserNotifications

/// Schedules, reschedules, and cancels UNUserNotificationCenter local
/// notifications for password-rotation reminders.
///
/// Design choices:
/// - Authorization is deferred until the user first sets a cadence — the prompt
///   is never shown at launch (privacy-friendly).
/// - Notification content is title-only: item name + localized "Time to change
///   your password" — never includes passwords, usernames, or any secret value.
/// - Denied authorization degrades gracefully: in-app "Needs attention" still works.
/// - Notification identifier = "rotation-\(itemID)" so reschedule naturally
///   replaces any pending notification for the same item.
final class RotationNotificationService: @unchecked Sendable {

    static let shared = RotationNotificationService()
    private init() {}

    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "rotation-"

    // MARK: Public API

    /// Schedule (or reschedule) a rotation reminder for `item`.
    ///
    /// - If cadence is 0 (off) any pending notification is cancelled.
    /// - If `passwordChangedAt` is nil the item's creation date is used as
    ///   the baseline (mirrors `RotationStatus.evaluate` behavior).
    /// - Authorization is requested lazily on the first call that would
    ///   actually schedule a notification.
    func schedule(item: VaultItem, passwordChangedAt: Date?) {
        guard item.rotateDays > 0 else {
            cancel(itemID: item.id)
            return
        }
        let baseline = passwordChangedAt ?? item.createdAt
        let fireDate = baseline.addingTimeInterval(Double(item.rotateDays) * 86_400)

        // Only schedule if the due date is in the future.
        guard fireDate > .now else {
            // Already overdue — cancel any stale pending notification (the
            // in-app "Needs attention" surface handles the overdue state).
            cancel(itemID: item.id)
            return
        }

        requestAuthorizationIfNeeded { [weak self] granted in
            guard let self, granted else { return }
            self.scheduleNotification(itemID: item.id,
                                      itemTitle: item.title,
                                      fireDate: fireDate)
        }
    }

    /// Cancel any pending rotation notification for the given item ID.
    /// Safe to call even if no notification exists.
    func cancel(itemID: String) {
        center.removePendingNotificationRequests(
            withIdentifiers: [identifier(for: itemID)])
    }

    // MARK: Private helpers

    private func identifier(for itemID: String) -> String {
        identifierPrefix + itemID
    }

    /// Request notification authorization the first time we need it.
    /// The closure receives `true` only when authorization is granted.
    private func requestAuthorizationIfNeeded(completion: @escaping (Bool) -> Void) {
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                completion(true)
            case .notDetermined:
                // First cadence set → prompt the user now.
                self.center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    completion(granted)
                }
            case .denied:
                // Graceful degradation: in-app surface still works; skip silently.
                completion(false)
            @unknown default:
                completion(false)
            }
        }
    }

    private func scheduleNotification(itemID: String, itemTitle: String, fireDate: Date) {
        let content = UNMutableNotificationContent()
        // Title only — never include passwords, usernames, or any secret.
        let displayTitle = itemTitle.isEmpty ? appString("Untitled item") : itemTitle
        content.title = appString("Time to change your password: \(displayTitle)")
        content.sound = .default

        var components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fireDate)
        // Fire at 09:00 on the due day for a less disruptive time.
        components.hour = 9
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier(for: itemID),
                                            content: content,
                                            trigger: trigger)
        center.add(request) { _ in
            // Errors are ignored: notification is best-effort; in-app surface
            // remains the authoritative attention signal.
        }
    }
}
