import Foundation

/// One created share (owner side): which item, which zone, who — device-local
/// bookkeeping only. The recipient label (email) never leaves this device;
/// CloudKit sees only the opaque zone name (M2).
nonisolated struct ItemShareRecord: Codable, Identifiable, Sendable {
    var id: String { zoneName }
    var itemId: String
    var zoneName: String
    var recipientLabel: String
    var grantId: String?
    var createdAtUnixMs: Int64
    var fingerprintConfirmed: Bool
    /// Public-DB invite record to GC once acceptance is proven (optional —
    /// records created before this field decode fine).
    var inviteRecordName: String? = nil
    /// Public-DB rendezvous drop to GC alongside it (creator-only delete).
    var dropRecordName: String? = nil
    /// nil = true (records predate the setting). When OFF, item edits do NOT
    /// republish values/display to this recipient — the owner pushes updates
    /// manually from the share-details sheet.
    var autoUpdate: Bool? = nil

    var isAutoUpdate: Bool { autoUpdate ?? true }
}

/// Owner-side registry of shares per item → "Shared with N" and the Phase-7
/// management/revocation list. Persisted as JSON in UserDefaults (non-secret).
@MainActor @Observable final class SharingStore {
    private static let key = "approval_item_share_records"

    private(set) var shares: [ItemShareRecord]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([ItemShareRecord].self, from: data) {
            shares = decoded
        } else {
            shares = []
        }
    }

    func shares(forItem itemId: String) -> [ItemShareRecord] {
        shares.filter { $0.itemId == itemId }
    }

    func upsert(_ record: ItemShareRecord) {
        shares.removeAll { $0.zoneName == record.zoneName }
        shares.append(record)
        persist()
    }

    func remove(zoneName: String) {
        shares.removeAll { $0.zoneName == zoneName }
        persist()
    }

    func wipe() {
        shares = []
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(shares) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
