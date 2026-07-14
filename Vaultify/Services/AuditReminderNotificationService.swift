import Foundation
import UserNotifications

/// Cadence shared by the periodic auto-audit (WatchtowerScreen) and the reminder
/// notification: how long a completed audit stays "fresh" before the vault is
/// due for another security checkup.
enum AuditReminder {
    /// 14 days, in seconds.
    static let cadenceDays = 14
    static let cadence: TimeInterval = Double(cadenceDays) * 86_400
}

/// Schedules the single "time for a security checkup" local notification.
///
/// Mirrors `RotationNotificationService`:
/// - One pending notification at a time (identifier `audit-checkup`), so each
///   reschedule replaces the previous one.
/// - Title-only content — never a score, an item, or any secret value.
/// - Authorization requested lazily, only when we actually schedule.
/// - A true background audit is impossible (the vault is locked and cannot be
///   decrypted off-screen), so this notification nudges the user to OPEN the
///   app, where the audit auto-runs.
final class AuditReminderNotificationService: @unchecked Sendable {

    static let shared = AuditReminderNotificationService()
    private init() {}

    private let center = UNUserNotificationCenter.current()
    private let identifier = "audit-checkup"

    /// Reschedule the checkup reminder one cadence window after the last audit.
    /// Disabled or an already-passed target cancels any pending reminder.
    func reschedule(lastAuditedAt: Date, enabled: Bool) {
        guard enabled else {
            cancel()
            return
        }
        let fireDate = lastAuditedAt.addingTimeInterval(AuditReminder.cadence)
        guard fireDate > .now else {
            // Already overdue — the in-app "run your audit" surface covers it;
            // don't fire an immediate notification.
            cancel()
            return
        }
        requestAuthorizationIfNeeded { [weak self] granted in
            guard let self, granted else { return }
            self.scheduleNotification(fireDate: fireDate)
        }
    }

    /// Cancel any pending checkup reminder (e.g. reminders toggled off).
    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    // MARK: Private

    private func requestAuthorizationIfNeeded(completion: @escaping (Bool) -> Void) {
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                completion(true)
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    completion(granted)
                }
            case .denied:
                completion(false)
            @unknown default:
                completion(false)
            }
        }
    }

    private func scheduleNotification(fireDate: Date) {
        let content = UNMutableNotificationContent()
        content.title = appString("Time for a security checkup")
        content.body = appString("Open Loox to check your vault's health.")
        content.sound = .default

        var components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fireDate)
        // Fire at 09:00 on the due day for a less disruptive time.
        components.hour = 9
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request) { _ in
            // Best-effort — the in-app surface remains authoritative.
        }
    }
}
