import Foundation

/// Owner-visible lifecycle of a share. Distinguishes the two milestones the
/// transport otherwise conflates: the recipient accepting the CKShare
/// (immediate, CloudKit-level) vs. their device publishing its identity profile
/// (needed before the owner can seal the grant — often blocked while the
/// recipient's vault is still locked). Refreshed off-sheet on foreground/unlock,
/// so an acceptance that lands after the waiting sheet closed is not lost.
nonisolated enum ShareLifecycle: String, Codable, Sendable {
    /// Invite created; recipient has not accepted the CKShare yet.
    case inviteSent
    /// Recipient accepted the CKShare, but their device has not published its
    /// identity profile yet (commonly: their vault is still locked).
    case accepted
    /// Profile published — the owner can run the fingerprint ceremony now.
    case readyForCeremony
    /// Fingerprint confirmed and grant published — fully active.
    case active

    /// Monotonic ordering: status only ever advances, never regresses on a
    /// transient fetch miss.
    var rank: Int {
        switch self {
        case .inviteSent: 0
        case .accepted: 1
        case .readyForCeremony: 2
        case .active: 3
        }
    }
}

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
    /// Persisted owner-side lifecycle (nil in records that predate this field →
    /// derived from `fingerprintConfirmed` on read). Only ever advances.
    var statusRaw: String? = nil

    var isAutoUpdate: Bool { autoUpdate ?? true }

    /// The confirmed ceremony is the authoritative `.active` terminal; below it
    /// the persisted raw status wins, defaulting to `.inviteSent` for both new
    /// and legacy (pre-`statusRaw`) records.
    var status: ShareLifecycle {
        if fingerprintConfirmed { return .active }
        if let statusRaw, let value = ShareLifecycle(rawValue: statusRaw), value != .active {
            return value
        }
        return .inviteSent
    }
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

    /// Advance a share's lifecycle. Monotonic (never downgrades) and never
    /// touches a ceremony-confirmed record — a transient refresh miss must not
    /// undo real progress.
    func updateStatus(zoneName: String, to status: ShareLifecycle) {
        guard let idx = shares.firstIndex(where: { $0.zoneName == zoneName }),
              !shares[idx].fingerprintConfirmed,
              status.rank > shares[idx].status.rank else { return }
        shares[idx].statusRaw = status.rawValue
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
