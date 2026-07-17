import CloudKit
import Foundation

/// The resolved recipient one `SpaceShareMembershipExecutor.reconcile` run
/// targets — supplied by the trust-ceremony UI (Project A, phase A3 stage 2),
/// never resolved here (no CKShare, no fingerprint, no key pinning happens in
/// this file). Bundles exactly what `SharedGrantComposer.publish` and
/// `SharingStore` need; `profile` reuses `SharedGrantComposer.RecipientProfile`
/// so this can never drift from the single-item ceremony's shape.
struct SpaceShareRecipientContext {
    let zoneID: CKRecordZone.ID
    /// Device-local label only (M2 metadata hygiene) — never written to
    /// CloudKit; same role as `ItemShareRecord.recipientLabel`.
    let recipientLabel: String
    let profile: SharedGrantComposer.RecipientProfile
    let deviceScope: DeviceScope
}

/// The CloudKit-facing operations `SpaceShareMembershipExecutor` needs —
/// narrow enough to fake in a unit test (no CloudKit, no crypto), wide
/// enough that the production adapter (`LiveSpaceShareGrantPublisher` below)
/// just routes 1:1 to the real `ApprovalShareService` + `SharedGrantComposer`
/// with no logic of its own, so production can never drift from the
/// single-item ceremony's crypto/composition path.
@MainActor protocol SpaceShareGrantPublishing {
    /// Every grant currently live in this member's zone (owner's private DB).
    func fetchAllGrants(zoneID: CKRecordZone.ID, nowUnixMs: Int64) async throws -> [AccessGrant]
    /// Publish (or, per `ApprovalShareService.publishGrant`'s flag-on
    /// replace-on-republish, REPLACE any prior grant for the same item) one
    /// item's grant at `epoch`. Callers pass `1` for a brand-new item and
    /// `existingEpoch + 1` for a republish — mirrors the single-item edit
    /// path (`ShareRecipientDetailSheet`): bumping the epoch invalidates any
    /// in-flight ask-each-time request signed against the OLD epoch.
    func publish(item: VaultItem, capabilities: [String: FieldCapability], epoch: UInt32,
                recipient: SpaceShareRecipientContext, nowUnixMs: Int64) async throws -> AccessGrant
    /// Delete one grant + its display + its fields — never the zone.
    func revokeGrant(_ grantId: String, zoneID: CKRecordZone.ID) async throws
}

/// Production adapter: routes to the real `ApprovalShareService` +
/// `SharedGrantComposer`, no logic of its own. Space shares never grant
/// passkey capabilities (`SpaceShareSafelist` only allows
/// username/password/url/email), so `itemPasskeys`/`vaultKey` are always
/// empty/nil here — the composer's passkey-resolution branch is simply never
/// reached for this caller.
@MainActor struct LiveSpaceShareGrantPublisher: SpaceShareGrantPublishing {
    let service: ApprovalShareService
    let store: VaultStore

    func fetchAllGrants(zoneID: CKRecordZone.ID, nowUnixMs: Int64) async throws -> [AccessGrant] {
        try await service.fetchAllGrants(zoneID: zoneID, nowUnixMs: nowUnixMs)
    }

    func publish(item: VaultItem, capabilities: [String: FieldCapability], epoch: UInt32,
                recipient: SpaceShareRecipientContext, nowUnixMs: Int64) async throws -> AccessGrant {
        try await SharedGrantComposer.publish(
            service: service, store: store, item: item, capabilities: capabilities,
            itemPasskeys: [], vaultKey: nil, profile: recipient.profile,
            deviceScope: recipient.deviceScope, epoch: epoch, zoneID: recipient.zoneID,
            nowUnixMs: nowUnixMs)
    }

    func revokeGrant(_ grantId: String, zoneID: CKRecordZone.ID) async throws {
        try await service.revokeGrant(grantId, zoneID: zoneID)
    }
}

/// Executes a `SpaceShareMembershipReconciler` plan against one member's
/// zone: fetch what's live, diff against the Space's current eligible items,
/// then publish/revoke to close the gap. Runs AFTER the trust ceremony —
/// `recipient` is the ALREADY-RESOLVED zone + participant identity; this
/// type resolves nothing itself (no CKShare creation, no fingerprint wait,
/// no key pinning).
///
/// Idempotent + resumable by construction: `reconcile` always starts from a
/// FRESH `fetchAllGrants` read, and `SpaceShareMembershipReconciler.plan` is
/// a pure, deterministic function of (desired, published) — re-running
/// against the same live state after a success, a crash, or a partial
/// failure always converges toward zero ops (the reconciler's own
/// idempotence/resumability is exhaustively unit-tested in
/// `SpaceShareMembershipReconcilerTests`; this type owns only "execute the
/// diff without inventing new failure semantics" — a per-op failure is
/// recorded in `Summary.failures` and every OTHER op still runs, so a caller
/// can simply re-invoke `reconcile` later to retry just what's left).
@MainActor final class SpaceShareMembershipExecutor {
    typealias Reconciler = SpaceShareMembershipReconciler

    /// One item's outcome — lets a future progress UI (stage 2+) report
    /// PARTIAL fan-out state without the whole reconcile aborting on the
    /// first CloudKit hiccup.
    struct ItemOutcome: Equatable {
        enum Kind: Equatable { case created, updated, revoked }
        let itemId: String
        let kind: Kind
    }

    struct Summary {
        var outcomes: [ItemOutcome] = []
        /// Keyed by itemId (create/update) or grantId (revoke) — the error
        /// that stopped that ONE op; every other op in the plan still ran.
        var failures: [String: Error] = [:]

        var isFullySuccessful: Bool { failures.isEmpty }
    }

    enum ExecutorError: Error {
        /// The reconciler computed a create/update for an itemId that isn't
        /// in `spaceItems` — can't happen from a single, consistent
        /// `spaceItems` snapshot (`Reconciler.desired` only ever emits
        /// itemIds it read FROM that same array); guards a caller passing a
        /// mismatched pair rather than crashing on a forced unwrap.
        case itemMissing(String)
    }

    /// One target to publish (create OR update) — both execute through the
    /// SAME call (`publishGrant`'s flag-on path makes a same-item republish
    /// REPLACE instead of duplicating), just with a different epoch/outcome.
    private struct PublishTarget {
        let itemId: String
        let capabilities: [String: FieldCapability]
        let epoch: UInt32
        let kind: ItemOutcome.Kind
    }

    private let publisher: SpaceShareGrantPublishing
    private let store: SharingStore

    init(publisher: SpaceShareGrantPublishing, store: SharingStore) {
        self.publisher = publisher
        self.store = store
    }

    @discardableResult
    func reconcile(spaceItems: [VaultItem], recipient: SpaceShareRecipientContext,
                   nowUnixMs: Int64) async throws -> Summary {
        let desired = Reconciler.desired(spaceItems: spaceItems)
        let liveGrants = try await publisher.fetchAllGrants(zoneID: recipient.zoneID, nowUnixMs: nowUnixMs)
        let published = Reconciler.published(grants: liveGrants)
        // Ownership registry: only grants THIS flow created may be updated or
        // revoked — a reused zone also carries the recipient's per-item
        // ceremony shares (passkeys, ask-each-time TOTP), which the blanket
        // fan-out must leave exactly as the owner configured them.
        let zoneName = recipient.zoneID.zoneName
        let spaceManagedItemIds = Set(store.shares
            .filter { $0.zoneName == zoneName && $0.spaceManaged == true }
            .map(\.itemId))
        let ops = Reconciler.planManaged(desired: desired, published: published,
                                         spaceManagedItemIds: spaceManagedItemIds)
        guard !ops.isEmpty else { return Summary() }

        let itemsById = Dictionary(uniqueKeysWithValues: spaceItems.map { ($0.id, $0) })
        // `AccessGrant.epoch` isn't carried by `Reconciler.PublishedGrant` —
        // look it up from the raw fetch so an update can bump it.
        let epochByGrantId = Dictionary(uniqueKeysWithValues: liveGrants.map { ($0.id, $0.epoch) })
        let itemIdByGrantId = Dictionary(uniqueKeysWithValues: published.values.map { ($0.grantId, $0.itemId) })

        let targets = ops.creates.map {
            PublishTarget(itemId: $0.itemId, capabilities: $0.capabilities, epoch: 1, kind: .created)
        } + ops.updates.map {
            PublishTarget(itemId: $0.itemId, capabilities: $0.desired.capabilities,
                         epoch: (epochByGrantId[$0.existingGrantId] ?? 0) + 1, kind: .updated)
        }

        var summary = Summary()
        // Sequential, not concurrent — the simplest possible cap on
        // in-flight CloudKit work (CloudKit rate-limits batch/record ops).
        // Every op is independently idempotent, so a future
        // bounded-parallel/background executor can reorder this without
        // changing observable behavior.
        for target in targets {
            guard let item = itemsById[target.itemId] else {
                summary.failures[target.itemId] = ExecutorError.itemMissing(target.itemId)
                continue
            }
            do {
                let grant = try await publisher.publish(
                    item: item, capabilities: target.capabilities, epoch: target.epoch,
                    recipient: recipient, nowUnixMs: nowUnixMs)
                store.upsert(shareRecord(itemId: target.itemId, grantId: grant.id,
                                        recipient: recipient, nowUnixMs: nowUnixMs))
                summary.outcomes.append(ItemOutcome(itemId: target.itemId, kind: target.kind))
            } catch {
                summary.failures[target.itemId] = error
            }
        }

        for grantId in ops.revokes {
            do {
                try await publisher.revokeGrant(grantId, zoneID: recipient.zoneID)
                if let itemId = itemIdByGrantId[grantId] {
                    store.remove(zoneName: recipient.zoneID.zoneName, itemId: itemId)
                    summary.outcomes.append(ItemOutcome(itemId: itemId, kind: .revoked))
                }
            } catch {
                summary.failures[grantId] = error
            }
        }

        return summary
    }

    /// The ceremony already confirmed this member (`reconcile` runs AFTER
    /// it), so every published item-share is `.active` immediately — no
    /// separate "ready for ceremony" state the way the single-item flow has.
    /// Preserves an existing record's `createdAtUnixMs` (an update must not
    /// reset "shared since" — it's rendered to the owner,
    /// `ShareRecipientDetailSheet`/`ShareResumeStepperSheet`), `autoUpdate`
    /// (an explicit owner choice — never silently reset), and
    /// `inviteRecordName`/`dropRecordName` (zone-level invite artifacts the
    /// single-item ceremony already carries forward into the active record
    /// so `revoke`'s best-effort GC can retry a possibly-failed delete).
    private func shareRecord(itemId: String, grantId: String, recipient: SpaceShareRecipientContext,
                             nowUnixMs: Int64) -> ItemShareRecord {
        let zoneName = recipient.zoneID.zoneName
        let existing = store.shares.first { $0.zoneName == zoneName && $0.itemId == itemId }
        let zoneSibling = existing ?? store.shares.first { $0.zoneName == zoneName }
        return ItemShareRecord(
            itemId: itemId, zoneName: zoneName, recipientLabel: recipient.recipientLabel,
            grantId: grantId, createdAtUnixMs: existing?.createdAtUnixMs ?? nowUnixMs,
            fingerprintConfirmed: true,
            inviteRecordName: zoneSibling?.inviteRecordName,
            dropRecordName: zoneSibling?.dropRecordName,
            autoUpdate: existing?.autoUpdate,
            spaceManaged: true)
    }
}
