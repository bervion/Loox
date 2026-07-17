import XCTest
@testable import Vaultify

/// Part 3 (Family full-group sharing, A2): `SpaceShareMembershipReconciler` —
/// the pure desired−published diff engine (A0-4/DEC-FAM-01 live membership).
/// Exhaustive over every diff case the frozen contract names, plus the two
/// properties a resumable executor (A3) depends on: determinism/idempotence
/// (the same inputs always yield byte-identical `Ops`) and resumability
/// (applying a plan, then re-planning against the result, yields an empty
/// `Ops`).
final class SpaceShareMembershipReconcilerTests: XCTestCase {

    typealias Reconciler = SpaceShareMembershipReconciler

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

    private func noteItem(id: String) -> VaultItem {
        VaultItem(id: id, category: .note, title: "Note \(id)",
                 fields: [DynamicField(label: "Note", kind: .multiline, value: "hi")])
    }

    private func makeGrant(id: String, itemId: String, capabilities: [String: FieldCapability],
                           epoch: UInt32 = 1, createdAtUnixMs: Int64 = 0) -> AccessGrant {
        AccessGrant(id: id, itemId: itemId, recipientId: "rcpt", participantPubKey: Data(),
                   pinnedDeviceSigningKeys: [], capabilities: capabilities, epoch: epoch,
                   createdAtUnixMs: createdAtUnixMs, expiresAtUnixMs: nil,
                   ownerSigningPubKey: Data(), ownerSignature: Data())
    }

    // MARK: desired()

    func testDesiredSkipsIneligibleItemsAndKeepsEligibleOnesKeyedByItemId() {
        let login = loginItem(id: "item-1")
        let note = noteItem(id: "item-2")

        let result = Reconciler.desired(spaceItems: [login, note])

        XCTAssertEqual(Set(result.keys), ["item-1"])
        XCTAssertEqual(result["item-1"]?.itemId, "item-1")
    }

    func testDesiredOverEmptySpaceIsEmpty() {
        XCTAssertTrue(Reconciler.desired(spaceItems: []).isEmpty)
    }

    // MARK: published()

    func testPublishedKeyedByItemId() {
        let grant = makeGrant(id: "grant-1", itemId: "item-1", capabilities: ["f": .value(.shared)])
        let result = Reconciler.published(grants: [grant])
        XCTAssertEqual(result["item-1"]?.grantId, "grant-1")
    }

    func testPublishedResolvesDuplicateItemIdByHighestEpochDeterministically() {
        let stale = makeGrant(id: "grant-old", itemId: "item-1",
                              capabilities: ["a": .value(.shared)], epoch: 1)
        let fresh = makeGrant(id: "grant-new", itemId: "item-1",
                              capabilities: ["b": .value(.shared)], epoch: 2)
        // Order-independent: enumeration order must not affect the winner.
        let resultA = Reconciler.published(grants: [stale, fresh])
        let resultB = Reconciler.published(grants: [fresh, stale])
        XCTAssertEqual(resultA["item-1"]?.grantId, "grant-new")
        XCTAssertEqual(resultB["item-1"]?.grantId, "grant-new")
    }

    // MARK: plan() — add item / create

    func testPlanCreatesForItemsDesiredButNotYetPublished() {
        let desired = Reconciler.desired(spaceItems: [loginItem(id: "item-1")])
        let ops = Reconciler.plan(desired: desired, published: [:])

        XCTAssertEqual(ops.creates.map(\.itemId), ["item-1"])
        XCTAssertTrue(ops.updates.isEmpty)
        XCTAssertTrue(ops.revokes.isEmpty)
    }

    // MARK: plan() — remove item / revoke

    func testPlanRevokesForItemsPublishedButNoLongerDesired() {
        let published = Reconciler.published(grants: [
            makeGrant(id: "grant-1", itemId: "item-1", capabilities: ["f": .value(.shared)]),
        ])
        let ops = Reconciler.plan(desired: [:], published: published)

        XCTAssertEqual(ops.revokes, ["grant-1"])
        XCTAssertTrue(ops.creates.isEmpty)
        XCTAssertTrue(ops.updates.isEmpty)
    }

    // MARK: plan() — capability change (password added / dropped)

    func testPlanUpdatesWhenCapabilitySetGrows() {
        let usernameOnly = loginItem(id: "item-1", fieldValues: [(.username, false)])
        let usernameAndPassword = loginItem(id: "item-1",
                                            fieldValues: [(.username, false), (.password, false)])
        let publishedGrant = makeGrant(
            id: "grant-1", itemId: "item-1",
            capabilities: Reconciler.desired(spaceItems: [usernameOnly])["item-1"]!.capabilities)

        let desired = Reconciler.desired(spaceItems: [usernameAndPassword])
        let published = Reconciler.published(grants: [publishedGrant])
        let ops = Reconciler.plan(desired: desired, published: published)

        XCTAssertEqual(ops.updates.map(\.itemId), ["item-1"])
        XCTAssertEqual(ops.updates.first?.existingGrantId, "grant-1")
        XCTAssertTrue(ops.creates.isEmpty)
        XCTAssertTrue(ops.revokes.isEmpty)
    }

    func testPlanUpdatesWhenCapabilitySetShrinksBecauseAFieldWasRemoved() {
        let both = loginItem(id: "item-1", fieldValues: [(.username, false), (.password, false)])
        let usernameOnly = loginItem(id: "item-1", fieldValues: [(.username, false)])
        let publishedGrant = makeGrant(
            id: "grant-1", itemId: "item-1",
            capabilities: Reconciler.desired(spaceItems: [both])["item-1"]!.capabilities)

        let desired = Reconciler.desired(spaceItems: [usernameOnly])
        let published = Reconciler.published(grants: [publishedGrant])
        let ops = Reconciler.plan(desired: desired, published: published)

        XCTAssertEqual(ops.updates.map(\.itemId), ["item-1"])
        XCTAssertTrue(ops.creates.isEmpty)
        XCTAssertTrue(ops.revokes.isEmpty)
    }

    func testPlanUpdatesWhenCapabilitySetShrinksBecauseAFieldBecameExtraProtected() {
        let both = loginItem(id: "item-1", fieldValues: [(.username, false), (.password, false)])
        // EXTRA-protection (guard2 / SecretGuard L2) drops a field from the safelist;
        // the normal masked `protected` flag does NOT — a masked password stays shared
        // (that is the whole point of a login share). So it's flipping the password to
        // guard2, not merely `protected`, that shrinks the desired capability set.
        let passwordNowGuarded = VaultItem(
            id: "item-1", category: .login, title: "Item item-1",
            fields: [
                DynamicField(id: "item-1-f0", label: FieldKind.username.defaultLabel,
                            kind: .username, value: "v", protected: false),
                DynamicField(id: "item-1-f1", label: FieldKind.password.defaultLabel,
                            kind: .password, value: "v", protected: true, guard2: true),
            ])
        let publishedGrant = makeGrant(
            id: "grant-1", itemId: "item-1",
            capabilities: Reconciler.desired(spaceItems: [both])["item-1"]!.capabilities)

        let desired = Reconciler.desired(spaceItems: [passwordNowGuarded])
        let published = Reconciler.published(grants: [publishedGrant])
        let ops = Reconciler.plan(desired: desired, published: published)

        XCTAssertEqual(ops.updates.map(\.itemId), ["item-1"])
        XCTAssertTrue(ops.creates.isEmpty)
        XCTAssertTrue(ops.revokes.isEmpty)
    }

    // MARK: plan() — item became ineligible (Login → Note)

    func testPlanRevokesWhenItemBecomesIneligible() {
        let login = loginItem(id: "item-1")
        let publishedGrant = makeGrant(
            id: "grant-1", itemId: "item-1",
            capabilities: Reconciler.desired(spaceItems: [login])["item-1"]!.capabilities)
        let published = Reconciler.published(grants: [publishedGrant])

        // The SAME item id, now a Note — desired() naturally excludes it.
        let desired = Reconciler.desired(spaceItems: [noteItem(id: "item-1")])
        let ops = Reconciler.plan(desired: desired, published: published)

        XCTAssertEqual(ops.revokes, ["grant-1"])
        XCTAssertTrue(ops.creates.isEmpty)
        XCTAssertTrue(ops.updates.isEmpty)
    }

    // MARK: plan() — stable set → no-ops / identical caps → no update

    func testPlanIsEmptyWhenPublishedAlreadyMatchesDesiredExactly() {
        let login = loginItem(id: "item-1")
        let desired = Reconciler.desired(spaceItems: [login])
        let publishedGrant = makeGrant(id: "grant-1", itemId: "item-1",
                                       capabilities: desired["item-1"]!.capabilities)
        let published = Reconciler.published(grants: [publishedGrant])

        let ops = Reconciler.plan(desired: desired, published: published)

        XCTAssertTrue(ops.isEmpty)
    }

    // MARK: plan() — empty Space

    func testPlanOverEmptyDesiredAndEmptyPublishedIsEmpty() {
        XCTAssertTrue(Reconciler.plan(desired: [:], published: [:]).isEmpty)
    }

    // MARK: Determinism / idempotence

    func testPlanIsDeterministicAcrossRepeatedCallsAndOutputIsSorted() {
        let items = (1...5).map { loginItem(id: "item-\($0)") }
        let desired = Reconciler.desired(spaceItems: items)
        // Mix: item-1 stable, item-2 stale caps (update), item-3..5 missing
        // (create), item-6 published but not in the Space (revoke).
        let published = Reconciler.published(grants: [
            makeGrant(id: "g1", itemId: "item-1", capabilities: desired["item-1"]!.capabilities),
            makeGrant(id: "g2", itemId: "item-2", capabilities: ["stale": .value(.shared)]),
            makeGrant(id: "g6", itemId: "item-6", capabilities: ["x": .value(.shared)]),
        ])

        let first = Reconciler.plan(desired: desired, published: published)
        let second = Reconciler.plan(desired: desired, published: published)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.creates.map(\.itemId), ["item-3", "item-4", "item-5"])
        XCTAssertEqual(first.updates.map(\.itemId), ["item-2"])
        XCTAssertEqual(first.revokes, ["g6"])
        // Sanity on the ordering guarantee itself (sorted, not dictionary
        // iteration order, which Swift does not guarantee stable run-to-run).
        XCTAssertEqual(first.creates.map(\.itemId), first.creates.map(\.itemId).sorted())
    }

    // MARK: Resumability — apply the plan, re-plan, must be empty

    /// Test-only simulation of what A3's executor does to the published set
    /// for each op kind (mint a new grant id for a create, keep the id for an
    /// update, drop the entry for a revoke) — pure bookkeeping so this test
    /// can prove resumability without any CloudKit/crypto dependency. A3 owns
    /// the real, CloudKit-backed version of this transition.
    private func applied(_ ops: Reconciler.Ops,
                         onto published: [String: Reconciler.PublishedGrant])
        -> [String: Reconciler.PublishedGrant] {
        var result = published
        for create in ops.creates {
            result[create.itemId] = Reconciler.PublishedGrant(
                grantId: "minted-\(create.itemId)", itemId: create.itemId,
                capabilities: create.capabilities)
        }
        for update in ops.updates {
            result[update.itemId] = Reconciler.PublishedGrant(
                grantId: update.existingGrantId, itemId: update.itemId,
                capabilities: update.desired.capabilities)
        }
        let revoked = Set(ops.revokes)
        return result.filter { !revoked.contains($0.value.grantId) }
    }

    func testApplyingThePlanThenReplanningYieldsAnEmptyPlan() {
        let items = [
            loginItem(id: "item-1"),                                   // → create
            loginItem(id: "item-2", fieldValues: [(.username, false)]), // → update
            loginItem(id: "item-3"),                                   // → stable
        ]
        let desired = Reconciler.desired(spaceItems: items)
        let published = Reconciler.published(grants: [
            makeGrant(id: "g2", itemId: "item-2",
                     capabilities: ["stale": .value(.shared), "extra": .value(.shared)]),
            makeGrant(id: "g3", itemId: "item-3", capabilities: desired["item-3"]!.capabilities),
            makeGrant(id: "g4", itemId: "item-4", capabilities: ["x": .value(.shared)]), // → revoke
        ])

        let firstPlan = Reconciler.plan(desired: desired, published: published)
        XCTAssertFalse(firstPlan.isEmpty, "sanity: the fixture must exercise all three op kinds")
        XCTAssertEqual(firstPlan.creates.map(\.itemId), ["item-1"])
        XCTAssertEqual(firstPlan.updates.map(\.itemId), ["item-2"])
        XCTAssertEqual(firstPlan.revokes, ["g4"])

        let resumedPublished = applied(firstPlan, onto: published)
        let secondPlan = Reconciler.plan(desired: desired, published: resumedPublished)

        XCTAssertTrue(secondPlan.isEmpty)
    }

    /// Idempotence under a crash-and-restart: replanning against the SAME
    /// (unresolved) published state a second time before applying anything
    /// yields the identical plan, not a partial/different one.
    func testReplanningBeforeApplyingAnythingYieldsTheIdenticalPlan() {
        let desired = Reconciler.desired(spaceItems: [loginItem(id: "item-1"), loginItem(id: "item-2")])
        let published = Reconciler.published(grants: [
            makeGrant(id: "g1", itemId: "item-1", capabilities: desired["item-1"]!.capabilities),
        ])

        let planA = Reconciler.plan(desired: desired, published: published)
        let planB = Reconciler.plan(desired: desired, published: published)

        XCTAssertEqual(planA, planB)
        XCTAssertEqual(planA.creates.map(\.itemId), ["item-2"])
    }

    // MARK: planManaged() — foreign-grant protection

    /// A standalone (per-item ceremony) passkey share living in the reused
    /// member zone must survive a Space fan-out that doesn't contain its item
    /// — the reconciler may revoke only grants the Space flow created.
    func testPlanManagedNeverRevokesAForeignGrantWhoseItemIsOutsideTheSpace() {
        let foreign = makeGrant(id: "grant-pk", itemId: "item-pk",
                                capabilities: ["slot": .passkey(.askEachTime)])
        let desired = Reconciler.desired(spaceItems: [loginItem(id: "item-1")])

        let ops = Reconciler.planManaged(
            desired: desired,
            published: Reconciler.published(grants: [foreign]),
            spaceManagedItemIds: [])

        XCTAssertTrue(ops.revokes.isEmpty)
        XCTAssertEqual(ops.creates.map(\.itemId), ["item-1"])
    }

    /// When the foreign grant's item IS in the Space, the reconciler must
    /// neither downgrade it to the safelist (stripping passkey capabilities)
    /// nor re-create over it — a flag-on publish for the same item would
    /// SUPERSEDE the ceremony grant, destroying it through another door.
    func testPlanManagedLeavesAForeignGrantInsideTheSpaceCompletelyUntouched() {
        let login = loginItem(id: "item-1")
        let desired = Reconciler.desired(spaceItems: [login])
        let foreign = makeGrant(id: "grant-1", itemId: "item-1",
                                capabilities: ["slot": .passkey(.shared)])

        let ops = Reconciler.planManaged(
            desired: desired,
            published: Reconciler.published(grants: [foreign]),
            spaceManagedItemIds: [])

        XCTAssertTrue(ops.isEmpty)
    }

    /// Grants in the ownership registry keep the full create/update/revoke
    /// lifecycle — the guard must not freeze the Space's own reconciliation.
    func testPlanManagedKeepsFullLifecycleForSpaceManagedGrants() {
        let desired = Reconciler.desired(spaceItems: [loginItem(id: "item-1")])
        let staleManaged = makeGrant(id: "grant-1", itemId: "item-1",
                                     capabilities: ["stale": .value(.shared)])
        let goneManaged = makeGrant(id: "grant-gone", itemId: "item-gone",
                                    capabilities: ["f": .value(.shared)])

        let ops = Reconciler.planManaged(
            desired: desired,
            published: Reconciler.published(grants: [staleManaged, goneManaged]),
            spaceManagedItemIds: ["item-1", "item-gone"])

        XCTAssertEqual(ops.updates.map(\.existingGrantId), ["grant-1"])
        XCTAssertEqual(ops.revokes, ["grant-gone"])
        XCTAssertTrue(ops.creates.isEmpty)
    }
}
