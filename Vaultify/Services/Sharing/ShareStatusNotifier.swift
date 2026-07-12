import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

/// Local notification when an outgoing share becomes actionable for the
/// owner: the recipient's device published its identity profile, so the
/// fingerprint ceremony can run now. Fires only while the app is not active
/// (in the foreground the pending row on Home updates instead) and only on
/// the crossing INTO `.readyForCeremony` — the store's monotonic lifecycle
/// guarantees each share crosses exactly once, so no extra dedup state.
///
/// Notification permission is verified before any share can be created
/// (`ApprovalPrerequisites.check`), so this banner is deliverable for every
/// share unless the user later revokes permission — in which case scheduling
/// silently no-ops and the in-app surfaces remain authoritative.
@MainActor final class ShareStatusNotifier {
    /// `userInfo` key carrying the share's opaque zone name on the banner;
    /// the tap handler routes it back to the resume stepper. Opaque routing
    /// only — all state is re-read from the local store, never trusted from
    /// the payload.
    nonisolated static let zoneNameUserInfoKey = "shareZoneName"

    private let center = UNUserNotificationCenter.current()

    /// Pure decision, separated for unit testing: notify only when the share
    /// CROSSES into ready-for-ceremony while the app is not frontmost. The
    /// `.accepted` milestone is deliberately excluded — one acceptance would
    /// otherwise produce two banners minutes apart, and ready-for-ceremony is
    /// the state that actually needs the owner's hands.
    nonisolated static func shouldNotify(previous: ShareLifecycle,
                                         next: ShareLifecycle,
                                         appActive: Bool) -> Bool {
        next == .readyForCeremony && previous.rank < next.rank && !appActive
    }

    /// Whether the app is frontmost. iOS only: macOS has no local banner for
    /// share status (in-app surfaces cover the desktop), so it reads as
    /// active and the notifier stays silent there.
    var isAppActive: Bool {
        #if canImport(UIKit)
        UIApplication.shared.applicationState == .active
        #else
        true
        #endif
    }

    func notifyReadyForCeremony(record: ItemShareRecord) {
        let content = UNMutableNotificationContent()
        // Privacy line: the recipient label is device-local data (it never
        // leaves this device). Never put the item title, codes, or any secret
        // in lock-screen visible text.
        content.title = appString("They accepted your invite")
        content.body = appString("\(record.recipientLabel) accepted. Tap to finish setting up the share.")
        content.sound = .default
        content.userInfo = [Self.zoneNameUserInfoKey: record.zoneName]
        // Stable per-share identifier: a re-fire replaces the pending banner
        // instead of stacking duplicates in Notification Center.
        let request = UNNotificationRequest(identifier: "share-ready-\(record.zoneName)",
                                            content: content,
                                            trigger: nil)
        center.add(request) { _ in
            // Best-effort: in-app surfaces remain the authoritative signal.
        }
    }
}
