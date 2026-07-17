import CloudKit
import XCTest
@testable import Vaultify

/// Project A phase A3 stage 1, Part 2: `SpaceShareMembershipExecutor` maps a
/// `SpaceShareMembershipReconciler.Ops` plan to the right
/// `SpaceShareGrantPublishing` calls and keeps `SharingStore` in lockstep —
/// exercised here against a fake publisher (no CloudKit, no crypto). The
/// production adapter (`LiveSpaceShareGrantPublisher`) has no logic of its
/// own beyond routing to `ApprovalShareService`/`SharedGrantComposer`, so its
/// correctness is the two-account device checklist's job, same convention as
/// every other CloudKit-touching method in this transport.
@MainActor final class SpaceShareMembershipExecutorTests: XCTestCase {

    private typealias Reconciler = SpaceShareMembershipReconciler
    private typealias Outcome = SpaceShareMembershipExecutor.ItemOutcome

    // MARK: Fixtures

    private func loginItem(id: String, fieldValues: [(kind: FieldKind, protected: Bool)] = [
        (.username, false), (.password, false),
    ]) -> VaultItem {
        let fields = fieldValues.enumerated().map { index, spec in
            DynamicField(id: "\(id)-f\(index)", label: spec.kind.defaultLabel, kind: spec.kind,
                        value: "v", protected: spec.protected)
        }
        return VaultItem(id: id, category: .login, title: "Item \(id)", fields: fields)
    }

    private func makeGrant(id: String, itemId: String, capabilities: [String: FieldCapability],
                           epoch: UInt32 = 1) -> AccessGrant {
        AccessGrant(id: id, itemId: itemId, recipientId: "rcpt", participantPubKey: Data(),
                   pinnedDeviceSigningKeys: [], capabilities: capabilities, epoch: epoch,
                   createdAtUnixMs: 0, expiresAtUnixMs: nil,
                   ownerSigningPubKey: Data(), ownerSignature: Data())
    }

    private func makeRecipient(zoneName: String = "apz-fam") -> SpaceShareRecipientContext {
        SpaceShareRecipientContext(
            zoneID: CKRecordZone.ID(zoneName: zoneName),
            recipientLabel: "member@example.com",
            profile: SharedGrantComposer.RecipientProfile(
                participantPubKey: Data([1]), deviceSigningKeys: [], deviceHPKEDirectory: []),
            deviceScope: .multi)
    }

    private func makeStore() -> SharingStore {
        let store = SharingStore()
        store.wipe()
        return store
    }

    /// Fake `SpaceShareGrantPublishing`: records the call sequence, returns a
    /// minted grant per publish (id derived from the itemId so assertions can
    /// trace which item produced which grant), and can be told to fail
    /// specific ops to exercise the executor's partial-failure handling.
    @MainActor private final class FakePublisher: SpaceShareGrantPublishing {
        enum Call: Equatable {
            case publish(itemId: String, capabilities: [String: FieldCapability], epoch: UInt32)
            case revoke(grantId: String)
        }
        struct Boom: Error {}

        var liveGrants: [AccessGrant] = []
        var failPublishForItemIds: Set<String> = []
        var failRevokeForGrantIds: Set<String> = []
        private(set) var calls: [Call] = []

        func fetchAllGrants(zoneID: CKRecordZone.ID, nowUnixMs: Int64) async throws -> [AccessGrant] {
            liveGrants
        }

        func publish(item: VaultItem, capabilities: [String: FieldCapability], epoch: UInt32,
                    recipient: SpaceShareRecipientContext, nowUnixMs: Int64) async throws -> AccessGrant {
            calls.append(.publish(itemId: item.id, capabilities: capabilities, epoch: epoch))
            if failPublishForItemIds.contains(item.id) { throw Boom() }
            return AccessGrant(id: "minted-\(item.id)", itemId: item.id, recipientId: "rcpt",
                              participantPubKey: Data(), pinnedDeviceSigningKeys: [],
                              capabilities: capabilities, epoch: epoch, createdAtUnixMs: nowUnixMs,
                              expiresAtUnixMs: nil, ownerSigningPubKey: Data(), ownerSignature: Data())
        }

        func revokeGrant(_ grantId: String, zoneID: CKRecordZone.ID) async throws {
            calls.append(.revoke(grantId: grantId))
            if failRevokeForGrantIds.contains(grantId) { throw Boom() }
        }
    }

    // MARK: creates

    func testReconcileCallsPublishForEachCreateAtEpochOneAndUpsertsSharingStore() async throws {
        let fake = FakePublisher()
        let store = makeStore()
        defer { store.wipe() }
        let executor = SpaceShareMembershipExecutor(publisher: fake, store: store)

        let summary = try await executor.reconcile(
            spaceItems: [loginItem(id: "item-1")], recipient: makeRecipient(), nowUnixMs: 1000)

        XCTAssertTrue(summary.isFullySuccessful)
        XCTAssertEqual(summary.outcomes, [Outcome(itemId: "item-1", kind: .created)])
        XCTAssertEqual(fake.calls.count, 1)
        guard case .publish(let itemId, _, let epoch) = fake.calls[0] else {
            return XCTFail("expected a publish call")
        }
        XCTAssertEqual(itemId, "item-1")
        XCTAssertEqual(epoch, 1)
        let stored = store.shares(forItem: "item-1").first
        XCTAssertEqual(stored?.grantId, "minted-item-1")
        XCTAssertEqual(stored?.zoneName, "apz-fam")
        XCTAssertTrue(stored?.fingerprintConfirmed ?? false)
    }

    func testReconcileSkipsNoteItemsEntirely() async throws {
        let fake = FakePublisher()
        let store = makeStore()
        defer { store.wipe() }
        let executor = SpaceShareMembershipExecutor(publisher: fake, store: store)
        let note = VaultItem(id: "item-1", category: .note, title: "Note",
                            fields: [DynamicField(label: "Note", kind: .multiline, value: "hi")])

        let summary = try await executor.reconcile(spaceItems: [note], recipient: makeRecipient(), nowUnixMs: 1000)

        XCTAssertTrue(summary.outcomes.isEmpty)
        XCTAssertTrue(fake.calls.isEmpty)
    }

    // MARK: updates

    func testReconcileCallsPublishForUpdateWithTheExistingGrantsEpochBumped() async throws {
        let fake = FakePublisher()
        let item = loginItem(id: "item-1", fieldValues: [(.username, false)])
        let desiredCaps = Reconciler.desired(spaceItems: [item])["item-1"]!.capabilities
        fake.liveGrants = [makeGrant(id: "grant-old", itemId: "item-1",
                                    capabilities: ["stale": .value(.shared)], epoch: 3)]
        let store = makeStore()
        defer { store.wipe() }
        store.upsert(ItemShareRecord(itemId: "item-1", zoneName: "apz-fam", recipientLabel: "member@example.com",
                                    grantId: "grant-old", createdAtUnixMs: 0, fingerprintConfirmed: true,
                                    spaceManaged: true))
        let executor = SpaceShareMembershipExecutor(publisher: fake, store: store)

        let summary = try await executor.reconcile(spaceItems: [item], recipient: makeRecipient(), nowUnixMs: 2000)

        XCTAssertEqual(summary.outcomes, [Outcome(itemId: "item-1", kind: .updated)])
        guard case .publish(let itemId, let caps, let epoch) = fake.calls.first else {
            return XCTFail("expected a publish call")
        }
        XCTAssertEqual(itemId, "item-1")
        XCTAssertEqual(caps, desiredCaps)
        XCTAssertEqual(epoch, 4, "must bump the EXISTING grant's epoch, not restart at 1")
    }

    func testReconcileUpdatePreservesCreatedAtAndAutoUpdateFromTheExistingRecord() async throws {
        let fake = FakePublisher()
        let item = loginItem(id: "item-1", fieldValues: [(.username, false)])
        fake.liveGrants = [makeGrant(id: "grant-old", itemId: "item-1",
                                    capabilities: ["stale": .value(.shared)])]
        let store = makeStore()
        defer { store.wipe() }
        store.upsert(ItemShareRecord(itemId: "item-1", zoneName: "apz-fam", recipientLabel: "member@example.com",
                                    grantId: "grant-old", createdAtUnixMs: 500,
                                    fingerprintConfirmed: true, autoUpdate: false, spaceManaged: true))
        let executor = SpaceShareMembershipExecutor(publisher: fake, store: store)

        _ = try await executor.reconcile(spaceItems: [item], recipient: makeRecipient(), nowUnixMs: 9000)

        let updated = store.shares(forItem: "item-1").first
        XCTAssertEqual(updated?.createdAtUnixMs, 500, "an update must not reset \"shared since\"")
        XCTAssertEqual(updated?.autoUpdate, false, "must not silently reset an explicit owner choice")
        XCTAssertEqual(updated?.grantId, "minted-item-1")
    }

    // MARK: revokes

    func testReconcileCallsRevokeForItemsNoLongerDesiredAndRemovesFromSharingStore() async throws {
        let fake = FakePublisher()
        fake.liveGrants = [makeGrant(id: "grant-gone", itemId: "item-1",
                                    capabilities: ["f": .value(.shared)])]
        let store = makeStore()
        defer { store.wipe() }
        store.upsert(ItemShareRecord(itemId: "item-1", zoneName: "apz-fam", recipientLabel: "member@example.com",
                                    grantId: "grant-gone", createdAtUnixMs: 0, fingerprintConfirmed: true,
                                    spaceManaged: true))
        let executor = SpaceShareMembershipExecutor(publisher: fake, store: store)

        let summary = try await executor.reconcile(spaceItems: [], recipient: makeRecipient(), nowUnixMs: 1000)

        XCTAssertEqual(summary.outcomes, [Outcome(itemId: "item-1", kind: .revoked)])
        XCTAssertEqual(fake.calls, [.revoke(grantId: "grant-gone")])
        XCTAssertTrue(store.shares(forItem: "item-1").isEmpty)
    }

    // MARK: no-op / idempotence

    func testReconcileIsANoOpWhenAlreadyFullySynced() async throws {
        let fake = FakePublisher()
        let item = loginItem(id: "item-1")
        let caps = Reconciler.desired(spaceItems: [item])["item-1"]!.capabilities
        fake.liveGrants = [makeGrant(id: "grant-1", itemId: "item-1", capabilities: caps)]
        let store = makeStore()
        defer { store.wipe() }
        let executor = SpaceShareMembershipExecutor(publisher: fake, store: store)

        let summary = try await executor.reconcile(spaceItems: [item], recipient: makeRecipient(), nowUnixMs: 1000)

        XCTAssertTrue(summary.outcomes.isEmpty)
        XCTAssertTrue(summary.isFullySuccessful)
        XCTAssertTrue(fake.calls.isEmpty)
    }

    // MARK: mixed batch (deterministic order: sorted creates, then updates, then revokes)

    func testReconcileHandlesCreateUpdateAndRevokeInOneRun() async throws {
        let fake = FakePublisher()
        let stable = loginItem(id: "item-3")
        let toUpdate = loginItem(id: "item-2", fieldValues: [(.username, false)])
        let toCreate = loginItem(id: "item-1")
        let stableCaps = Reconciler.desired(spaceItems: [stable])["item-3"]!.capabilities
        fake.liveGrants = [
            makeGrant(id: "grant-2", itemId: "item-2", capabilities: ["stale": .value(.shared)], epoch: 1),
            makeGrant(id: "grant-3", itemId: "item-3", capabilities: stableCaps),
            makeGrant(id: "grant-4", itemId: "item-4", capabilities: ["x": .value(.shared)]),
        ]
        let store = makeStore()
        defer { store.wipe() }
        for (itemId, grantId) in [("item-2", "grant-2"), ("item-3", "grant-3"), ("item-4", "grant-4")] {
            store.upsert(ItemShareRecord(itemId: itemId, zoneName: "apz-fam",
                                        recipientLabel: "member@example.com", grantId: grantId,
                                        createdAtUnixMs: 0, fingerprintConfirmed: true,
                                        spaceManaged: true))
        }
        let executor = SpaceShareMembershipExecutor(publisher: fake, store: store)

        let summary = try await executor.reconcile(
            spaceItems: [toCreate, toUpdate, stable], recipient: makeRecipient(), nowUnixMs: 1000)

        XCTAssertEqual(summary.outcomes, [
            Outcome(itemId: "item-1", kind: .created),
            Outcome(itemId: "item-2", kind: .updated),
            Outcome(itemId: "item-4", kind: .revoked),
        ])
        XCTAssertTrue(summary.isFullySuccessful)
    }

    // MARK: partial failure / resumability

    func testReconcilePartialFailureContinuesRemainingOpsAndReportsTheFailure() async throws {
        let fake = FakePublisher()
        fake.failPublishForItemIds = ["item-1"]
        let store = makeStore()
        defer { store.wipe() }
        let executor = SpaceShareMembershipExecutor(publisher: fake, store: store)

        let summary = try await executor.reconcile(
            spaceItems: [loginItem(id: "item-1"), loginItem(id: "item-2")],
            recipient: makeRecipient(), nowUnixMs: 1000)

        XCTAssertFalse(summary.isFullySuccessful)
        XCTAssertNotNil(summary.failures["item-1"])
        XCTAssertEqual(summary.outcomes, [Outcome(itemId: "item-2", kind: .created)])
        // The failed item was NEVER upserted — a retry must see it as still
        // needing a create, not silently mark it synced.
        XCTAssertTrue(store.shares(forItem: "item-1").isEmpty)
        XCTAssertFalse(store.shares(forItem: "item-2").isEmpty)
    }

    func testReconcilePartialRevokeFailureStillRemovesTheSuccessfulOnesFromSharingStore() async throws {
        let fake = FakePublisher()
        fake.failRevokeForGrantIds = ["grant-stuck"]
        fake.liveGrants = [
            makeGrant(id: "grant-stuck", itemId: "item-1", capabilities: ["f": .value(.shared)]),
            makeGrant(id: "grant-ok", itemId: "item-2", capabilities: ["f": .value(.shared)]),
        ]
        let store = makeStore()
        defer { store.wipe() }
        store.upsert(ItemShareRecord(itemId: "item-1", zoneName: "apz-fam", recipientLabel: "member@example.com",
                                    grantId: "grant-stuck", createdAtUnixMs: 0, fingerprintConfirmed: true,
                                    spaceManaged: true))
        store.upsert(ItemShareRecord(itemId: "item-2", zoneName: "apz-fam", recipientLabel: "member@example.com",
                                    grantId: "grant-ok", createdAtUnixMs: 0, fingerprintConfirmed: true,
                                    spaceManaged: true))
        let executor = SpaceShareMembershipExecutor(publisher: fake, store: store)

        let summary = try await executor.reconcile(spaceItems: [], recipient: makeRecipient(), nowUnixMs: 1000)

        XCTAssertNotNil(summary.failures["grant-stuck"])
        XCTAssertEqual(summary.outcomes, [Outcome(itemId: "item-2", kind: .revoked)])
        XCTAssertFalse(store.shares(forItem: "item-1").isEmpty, "the failed revoke must not be dropped locally")
        XCTAssertTrue(store.shares(forItem: "item-2").isEmpty)
    }

    func testReconcileRerunAfterASuccessfulRunConvergesToZeroOps() async throws {
        let fake = FakePublisher()
        let store = makeStore()
        defer { store.wipe() }
        let executor = SpaceShareMembershipExecutor(publisher: fake, store: store)
        let item = loginItem(id: "item-1")

        let first = try await executor.reconcile(spaceItems: [item], recipient: makeRecipient(), nowUnixMs: 1000)
        XCTAssertFalse(first.outcomes.isEmpty)

        // Simulate the live state now reflecting the successful publish.
        let caps = Reconciler.desired(spaceItems: [item])["item-1"]!.capabilities
        fake.liveGrants = [makeGrant(id: "minted-item-1", itemId: "item-1", capabilities: caps)]

        let second = try await executor.reconcile(spaceItems: [item], recipient: makeRecipient(), nowUnixMs: 2000)

        XCTAssertTrue(second.outcomes.isEmpty)
        XCTAssertTrue(second.isFullySuccessful)
        XCTAssertEqual(fake.calls.count, 1, "the second reconcile must not re-publish anything")
    }

    // MARK: foreign grants (per-item ceremony shares in a reused zone)

    /// A grant with no `spaceManaged` marker is a per-item ceremony share —
    /// the fan-out must not revoke it, not downgrade it, and not publish over
    /// it, while the Space's own items still reconcile normally.
    func testReconcileLeavesForeignGrantsInTheReusedZoneUntouched() async throws {
        let fake = FakePublisher()
        fake.liveGrants = [makeGrant(id: "grant-foreign", itemId: "item-foreign",
                                    capabilities: ["slot": .passkey(.shared)])]
        let store = makeStore()
        defer { store.wipe() }
        store.upsert(ItemShareRecord(itemId: "item-foreign", zoneName: "apz-fam",
                                    recipientLabel: "member@example.com",
                                    grantId: "grant-foreign", createdAtUnixMs: 0,
                                    fingerprintConfirmed: true))
        let executor = SpaceShareMembershipExecutor(publisher: fake, store: store)

        let summary = try await executor.reconcile(
            spaceItems: [loginItem(id: "item-new")], recipient: makeRecipient(), nowUnixMs: 1000)

        XCTAssertEqual(summary.outcomes, [Outcome(itemId: "item-new", kind: .created)])
        XCTAssertFalse(fake.calls.contains(.revoke(grantId: "grant-foreign")))
        XCTAssertFalse(store.shares(forItem: "item-foreign").isEmpty,
                       "the ceremony share record must survive the fan-out")
    }
}
