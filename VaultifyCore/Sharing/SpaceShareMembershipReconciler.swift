import Foundation

/// A0-4 (DEC-FAM-01) live-membership diff engine for Family Space sharing: a
/// Space share tracks the Space's CURRENT eligible items, not a one-shot
/// snapshot. Given what SHOULD be shared (`desired`, from
/// `SpaceShareSafelist`) and what IS currently published to one member
/// (`published`, that member's live `AccessGrant`s), `plan` computes the
/// create/update/revoke operations that reconcile them.
///
/// PURE LOGIC ONLY: this type computes a plan, it never calls CloudKit,
/// `publishGrant`, or any revoke — that execution (with retries, batching,
/// and resumable state) is `A3`'s executor. Every function here is a total,
/// deterministic function of its arguments.
///
/// Callers invoke `plan` ONCE PER MEMBER ZONE. `desired` itself is
/// member-independent — A0-4's "desired = eligible(items in Space) × members"
/// cross product lives in the CALLER (one `published` per member, the SAME
/// `desired` reused for each), because every member of a live Space share
/// sees the identical eligible fields.
nonisolated enum SpaceShareMembershipReconciler {

    /// One item's safelisted capability set, as it SHOULD exist for every
    /// member of a live Space share.
    struct DesiredGrant: Equatable, Sendable {
        var itemId: String
        var capabilities: [String: FieldCapability]
    }

    /// One item's capability set as it CURRENTLY exists in a member's zone —
    /// one already-published `AccessGrant`, reduced to what `plan` needs to
    /// diff and, if the item is no longer desired, revoke.
    struct PublishedGrant: Equatable, Sendable {
        var grantId: String
        var itemId: String
        var capabilities: [String: FieldCapability]
    }

    /// A republish: same item, same existing grant id (the executor bumps its
    /// epoch and re-seals), new capability set.
    struct UpdateOp: Equatable, Sendable {
        var itemId: String
        var desired: DesiredGrant
        var existingGrantId: String
    }

    /// The reconciliation result. Arrays are sorted (by itemId / grantId), NOT
    /// dictionary iteration order, so `plan` is a pure, repeatable function of
    /// its inputs — required for idempotence and resumability.
    struct Ops: Equatable, Sendable {
        var creates: [DesiredGrant] = []
        var updates: [UpdateOp] = []
        var revokes: [String] = []

        var isEmpty: Bool { creates.isEmpty && updates.isEmpty && revokes.isEmpty }
    }

    /// The Space's live eligible items, keyed by itemId. An item the safelist
    /// rejects (not a login, or a login with zero eligible fields) is skipped
    /// entirely — never "desired" at any capability, so a bare revoke (never
    /// a zero-capability update) is what removes it from a member's zone.
    static func desired(spaceItems: [VaultItem]) -> [String: DesiredGrant] {
        var result: [String: DesiredGrant] = [:]
        for item in spaceItems {
            guard let fields = SpaceShareSafelist.shareableFields(for: item) else { continue }
            result[item.id] = DesiredGrant(itemId: item.id, capabilities: fields)
        }
        return result
    }

    /// One member's currently published grants, keyed by itemId. Two grants
    /// for the same item should never happen, but a mid-fan-out crash or an
    /// upstream bug could momentarily leave one — resolved deterministically
    /// (highest `epoch` wins, i.e. the most recently republished grant; ties
    /// broken by the latest `createdAtUnixMs`, then by `id`) rather than by
    /// dictionary/array insertion order, which `plan`'s determinism depends on.
    static func published(grants: [AccessGrant]) -> [String: PublishedGrant] {
        var byItem: [String: AccessGrant] = [:]
        for grant in grants {
            if let existing = byItem[grant.itemId] {
                if isNewer(grant, than: existing) { byItem[grant.itemId] = grant }
            } else {
                byItem[grant.itemId] = grant
            }
        }
        return byItem.mapValues {
            PublishedGrant(grantId: $0.id, itemId: $0.itemId, capabilities: $0.capabilities)
        }
    }

    private static func isNewer(_ candidate: AccessGrant, than current: AccessGrant) -> Bool {
        if candidate.epoch != current.epoch { return candidate.epoch > current.epoch }
        if candidate.createdAtUnixMs != current.createdAtUnixMs {
            return candidate.createdAtUnixMs > current.createdAtUnixMs
        }
        return candidate.id > current.id
    }

    /// The desired−published diff (A0-4): create what's missing, republish
    /// what changed, revoke what's no longer desired.
    /// - create: itemId ∈ desired, ∉ published.
    /// - update: itemId ∈ both, but the safelisted capability set differs
    ///   from the published grant's capabilities (dictionary equality —
    ///   order-independent, exactly the comparison a field-added/dropped or
    ///   item-became-ineligible-then-eligible-again change needs).
    /// - revoke: itemId ∈ published, ∉ desired (item left the Space, was
    ///   deleted, or became ineligible — e.g. Login → Note).
    ///
    /// Deterministic + idempotent: the same `(desired, published)` pair
    /// always yields byte-identical `Ops` (unit-tested), and applying `Ops`
    /// then re-planning against the resulting published state yields an
    /// empty `Ops` (unit-tested) — required for a resumable, crash-safe
    /// executor in A3.
    static func plan(desired: [String: DesiredGrant],
                     published: [String: PublishedGrant]) -> Ops {
        var creates: [DesiredGrant] = []
        var updates: [UpdateOp] = []
        var revokes: [String] = []

        for (itemId, want) in desired {
            guard let have = published[itemId] else {
                creates.append(want)
                continue
            }
            if have.capabilities != want.capabilities {
                updates.append(UpdateOp(itemId: itemId, desired: want,
                                        existingGrantId: have.grantId))
            }
        }
        for (itemId, have) in published where desired[itemId] == nil {
            revokes.append(have.grantId)
        }

        creates.sort { $0.itemId < $1.itemId }
        updates.sort { $0.itemId < $1.itemId }
        revokes.sort()
        return Ops(creates: creates, updates: updates, revokes: revokes)
    }
}
