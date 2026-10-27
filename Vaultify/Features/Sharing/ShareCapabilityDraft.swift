import Foundation

/// Owner-side edit state for one share's capabilities: what the live grant
/// carries, what the owner has picked on screen, and the hand-over waiting
/// for its confirmation.
///
/// Every mode change goes through `select(_:for:)`, so the irreversibility
/// gate (INV-08) lives in ONE place instead of at each row's call site. It
/// used to be a `requestHandOver` closure each capability row took with a
/// silent no-op default, and the share-details sheet never passed one for
/// TOTP rows: after moving a handed-over seed to "Ask each time", picking
/// hand over again did nothing at all, with no confirmation and no error.
nonisolated struct ShareCapabilityDraft: Equatable, Sendable {
    /// A hand-over mode the owner picked but has not confirmed yet.
    struct HandOver: Equatable, Sendable {
        let slot: String
        let capability: FieldCapability
    }

    /// What the live grant carries: the baseline unsaved changes compare against.
    private(set) var published: [String: FieldCapability]
    /// What the owner has picked on screen.
    private(set) var selection: [String: FieldCapability]
    private(set) var pendingHandOver: HandOver?

    init(published: [String: FieldCapability]) {
        self.published = published
        self.selection = published
    }

    var hasChanges: Bool { selection != published }

    /// Whether anything besides the pending hand-over differs from the grant.
    /// Confirming a hand-over publishes those edits along with it.
    var hasChangesBesideHandOver: Bool {
        guard let slot = pendingHandOver?.slot else { return hasChanges }
        return selection.filter { $0.key != slot } != published.filter { $0.key != slot }
    }

    /// The selection with the pending hand-over applied: what confirming publishes.
    var selectionConfirmingHandOver: [String: FieldCapability] {
        guard let pendingHandOver else { return selection }
        var next = selection
        next[pendingHandOver.slot] = pendingHandOver.capability
        return next
    }

    func capability(for slot: String) -> FieldCapability? { selection[slot] }

    /// The one entry point for a mode change. A hand-over mode parks until it
    /// is confirmed; every other mode applies at once. A hand-over the grant
    /// already carries (picked again before Apply) is restored without asking
    /// twice: nothing new leaves the vault.
    mutating func select(_ capability: FieldCapability, for slot: String) {
        guard selection[slot] != capability else { return }
        if capability.isHandOver, published[slot] != capability {
            pendingHandOver = HandOver(slot: slot, capability: capability)
        } else {
            selection[slot] = capability
        }
    }

    mutating func confirmHandOver() {
        selection = selectionConfirmingHandOver
        pendingHandOver = nil
    }

    mutating func cancelHandOver() { pendingHandOver = nil }

    /// The grant now carries `capabilities`, so they become the new baseline.
    mutating func didPublish(_ capabilities: [String: FieldCapability]) {
        published = capabilities
        selection = capabilities
        pendingHandOver = nil
    }

    /// Item edits this recipient has not received: the item changed after the
    /// last delivery this device knows of (a grant publish or an edit-time push).
    static func hasUnsentItemEdits(itemUpdatedAt: Date, lastSentAtUnixMs: Int64) -> Bool {
        Int64(itemUpdatedAt.timeIntervalSince1970 * 1000) > lastSentAtUnixMs
    }
}

extension FieldCapability {
    /// The "nothing granted" mode for a field of this kind.
    nonisolated static func off(for field: DynamicField) -> FieldCapability {
        field.kind == .totp ? .totp(.none) : .value(.none)
    }
}
