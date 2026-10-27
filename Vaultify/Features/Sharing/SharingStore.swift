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
    /// Composite identity (Family full-group sharing, A2): a zone can now
    /// hold N item-shares — one Space share publishes one grant per eligible
    /// item into the SAME member zone — so `zoneName` alone no longer names a
    /// record uniquely. `id` is computed, never stored/`Codable` (it was
    /// never encoded even under the old `zoneName`-only identity), so a
    /// legacy JSON blob (written when a zone held exactly one share) decodes
    /// unchanged and simply recomputes `id` from its two stored fields.
    var id: String { "\(zoneName)::\(itemId)" }
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
    /// True when the SPACE fan-out (`SpaceShareMembershipExecutor`) created or
    /// last republished this share — the device-local ownership registry the
    /// Space reconciler consults before updating or revoking a grant. nil
    /// (records predating the field, and every single-item ceremony share) =
    /// NOT space-managed: the blanket Space flow must never touch a grant the
    /// owner configured per item.
    var spaceManaged: Bool? = nil
    /// The owner's field selection, frozen when the invite was created.
    ///
    /// The grant cannot be SEALED until the recipient publishes their key, but
    /// the owner's INTENT is settled the moment they tap Create — so it is
    /// persisted here and replayed when the ceremony finishes, instead of being
    /// re-collected. Without this the sheet's ephemeral `@State` was the only
    /// copy: dismissing (which the waiting screen actively invites) discarded it
    /// and forced the owner to re-pick every field on resume.
    ///
    /// Exposure: field ids and capability MODES only, alongside the recipient
    /// email already stored here. No field values, no key material.
    /// nil = a record written before this field existed, or a Space fan-out
    /// share whose capabilities are derived by `SpaceShareSafelist`.
    var plannedCapabilities: [String: FieldCapability]? = nil
    /// Device scope frozen with the selection above. nil = predates the field.
    ///
    /// Persisted for a security reason, not just convenience: the sheet's
    /// in-memory default is `true` (multi-device), so a share the owner
    /// deliberately scoped to a SINGLE device silently resumed as multi-device
    /// — the resumed default was strictly more permissive than what they chose.
    var plannedAllowMultipleDevices: Bool? = nil
    /// When this device last delivered the item's current content to this
    /// recipient: a grant publish, or an edit-time push that succeeded. It is
    /// what the share-details sheet's Apply compares edits against, so an
    /// edit whose automatic push failed (offline) still reads as unsent.
    /// nil = nothing recorded yet (the live grant's creation time stands in).
    var lastSentAtUnixMs: Int64? = nil

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
    @ObservationIgnored private let defaults: UserDefaults

    private(set) var shares: [ItemShareRecord]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([ItemShareRecord].self, from: data) {
            shares = decoded
        } else {
            shares = []
        }
    }

    func shares(forItem itemId: String) -> [ItemShareRecord] {
        shares.filter { $0.itemId == itemId }
    }

    /// Every item-share for one recipient, across all their zones (a member
    /// re-shared under a Personal vs. Work persona gets separate zones,
    /// INV-R03 — this spans both).
    func shares(forRecipient recipientLabel: String) -> [ItemShareRecord] {
        shares.filter { $0.recipientLabel == recipientLabel }
    }

    /// Shares waiting on the OWNER's hands (the fingerprint ceremony) — the
    /// one lifecycle state that is actionable rather than merely pending.
    /// Feeds the Home bell badge alongside invites and approval requests.
    var awaitingCeremonyCount: Int {
        shares.filter { $0.status == .readyForCeremony }.count
    }

    /// Replace the record for this exact `(zoneName, itemId)` pair, leaving
    /// every OTHER item-share in the same zone untouched. Matching on
    /// `zoneName` alone (the old behavior) would wipe every sibling item-share
    /// in the zone the moment a second item republished — the bug this
    /// composite identity exists to fix. With one item per zone (today's
    /// shipped shape, `FamilyShareTransport.perGrantEnabled == false`) this is
    /// byte-for-byte the old `removeAll { $0.zoneName == record.zoneName }`,
    /// since `(zoneName, itemId)` is always the same pair across a share's
    /// pending → confirmed upserts.
    func upsert(_ record: ItemShareRecord) {
        shares.removeAll { $0.zoneName == record.zoneName && $0.itemId == record.itemId }
        shares.append(record)
        persist()
    }

    /// Advance every item-share in this zone to `status` (still keyed by
    /// `zoneName` alone, not per item): the fingerprint ceremony is a
    /// per-zone/per-member event — ALL item-shares published into a member's
    /// zone become ready/confirmed together, so they must advance together
    /// too, or siblings added after the first would read a stale status.
    /// Monotonic per record (never downgrades) and never touches an
    /// already-confirmed record — a transient refresh miss must not undo real
    /// progress. With one item per zone this is behaviorally identical to the
    /// old single-record update (the loop body runs exactly once).
    func updateStatus(zoneName: String, to status: ShareLifecycle) {
        var changed = false
        for idx in shares.indices where shares[idx].zoneName == zoneName {
            guard !shares[idx].fingerprintConfirmed,
                  status.rank > shares[idx].status.rank else { continue }
            shares[idx].statusRaw = status.rawValue
            changed = true
        }
        if changed { persist() }
    }

    /// Remove exactly one item-share (an item left the Space, was deleted, or
    /// the owner unshared just that one item) — leaves every other item-share
    /// in the same zone untouched.
    func remove(zoneName: String, itemId: String) {
        shares.removeAll { $0.zoneName == zoneName && $0.itemId == itemId }
        persist()
    }

    /// Remove EVERY item-share in this zone — a whole-member revoke (deleting
    /// the zone removes all of that member's access atomically, the family
    /// semantic). Unchanged from before this identity rework: with one item
    /// per zone it already meant "remove this share"; now it explicitly means
    /// "remove all of this member's item-shares."
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
            defaults.set(data, forKey: Self.key)
        }
    }
}
