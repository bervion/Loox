import Foundation

/// Bounded local log of sharing events (invites, approvals) so the
/// notifications screen keeps HISTORY, not just the actionable queue.
/// Device-local, non-secret (labels are emails/titles the user already sees).
@MainActor @Observable final class NotificationHistoryStore {
    nonisolated struct Entry: Codable, Identifiable, Sendable {
        enum Kind: String, Codable {
            case inviteReceived, inviteAccepted, inviteDismissed
            case approvalApproved, approvalRejected
        }
        var id: String = UUID().uuidString
        var kind: Kind
        /// Requester email / item title when known — display only.
        var label: String?
        var atUnixMs: Int64
    }

    private static let key = "sharing_notification_history"
    private static let cap = 50

    private(set) var entries: [Entry]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded
        } else {
            entries = []
        }
    }

    /// Newest first, FIFO-capped.
    func log(_ kind: Entry.Kind, label: String? = nil) {
        entries.insert(Entry(kind: kind, label: label,
                             atUnixMs: Int64(Date().timeIntervalSince1970 * 1000)), at: 0)
        if entries.count > Self.cap { entries.removeLast(entries.count - Self.cap) }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    func wipe() {
        entries = []
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}
