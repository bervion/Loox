import XCTest
@testable import Vaultify

/// Store-level tests for the multi-device sync merge rules: tombstone propagation,
/// the two-gate content/meta LWW, change-tag short-circuit, the mark-synced snapshot
/// guard, and the pairing-crypto round trip.
@MainActor
final class CloudSyncMergeTests: XCTestCase {

    private func makeStore() -> VaultStore { VaultStore(inMemory: true) }

    private func makeRepo(store: VaultStore) -> VaultRepository {
        let session = VaultSession(settings: SettingsStore())
        session.adoptUnlocked(key: [UInt8](repeating: 0x2a, count: 32))
        let repo = VaultRepository(store: store, session: session)
        repo.reload()
        TestLifetimeRetainer.retain(repo)
        return repo
    }

    private func insertLocal(_ store: VaultStore, id: String = "item-1",
                             updatedAt: Date, metaUpdatedAt: Date = .distantPast) -> ItemRecord {
        let record = ItemRecord(id: id, sealed: Data([1, 2, 3]),
                                createdAt: updatedAt, updatedAt: updatedAt)
        record.metaUpdatedAt = metaUpdatedAt
        store.context.insert(record)
        try? store.context.save()
        return record
    }

    // MARK: Tombstone (delete must propagate, not resurrect)

    func testLocalDeleteBumpsUpdatedAtSoTombstonePropagates() throws {
        let store = makeStore()
        let repo = makeRepo(store: store)
        let item = VaultItem(category: .login, title: "Acme")
        try repo.add(item)
        let before = store.record(id: item.id)!.updatedAt

        try repo.delete(item)

        let record = store.record(id: item.id)!
        XCTAssertNotNil(record.deletedAt)
        XCTAssertGreaterThan(record.updatedAt, before, "tombstone must bump updatedAt or pull drops it")
        XCTAssertTrue(record.dirty)
    }

    func testRemoteTombstoneWinsOverOlderLocalContent() {
        let store = makeStore()
        let old = Date(timeIntervalSinceNow: -100)
        _ = insertLocal(store, updatedAt: old)

        store.upsertFromRemote(id: "item-1", sealed: Data([9]), favorite: false,
                               trashedAt: nil, deletedAt: .now,
                               createdAt: old, updatedAt: .now,
                               pinned: false, archived: false, metaUpdatedAt: .distantPast,
                               isDefaultIdentity: false, avatarSealed: nil, changeTag: "t1")

        XCTAssertNotNil(store.record(id: "item-1")?.deletedAt, "remote deletion must apply")
    }

    // MARK: Two-gate merge (content vs pinned/archived meta)

    func testNewerRemoteContentDoesNotClobberNewerLocalPin() {
        let store = makeStore()
        let base = Date(timeIntervalSinceNow: -100)
        let record = insertLocal(store, updatedAt: base, metaUpdatedAt: .now)
        record.pinned = true // local pin is NEWER than the remote's meta timestamp
        record.dirty = true
        try? store.context.save()

        store.upsertFromRemote(id: "item-1", sealed: Data([9]), favorite: true,
                               trashedAt: nil, deletedAt: nil,
                               createdAt: base, updatedAt: .now, // remote content newer
                               pinned: false, archived: false,
                               metaUpdatedAt: .distantPast,      // remote meta older
                               isDefaultIdentity: false, avatarSealed: nil, changeTag: "t1")

        let merged = store.record(id: "item-1")!
        XCTAssertEqual(merged.sealed, Data([9]), "newer remote content applies")
        XCTAssertTrue(merged.pinned, "newer local pin survives the content pull")
        XCTAssertTrue(merged.dirty, "one-sided apply keeps dirty so the local pin still pushes")
    }

    func testNewerRemotePinAppliesWithoutTouchingNewerLocalContent() {
        let store = makeStore()
        let record = insertLocal(store, updatedAt: .now, metaUpdatedAt: .distantPast)
        let localSealed = record.sealed

        store.upsertFromRemote(id: "item-1", sealed: Data([9]), favorite: false,
                               trashedAt: nil, deletedAt: nil,
                               createdAt: .distantPast,
                               updatedAt: Date(timeIntervalSinceNow: -50), // remote content older
                               pinned: true, archived: false,
                               metaUpdatedAt: .now,                         // remote meta newer
                               isDefaultIdentity: false, avatarSealed: nil, changeTag: "t1")

        let merged = store.record(id: "item-1")!
        XCTAssertEqual(merged.sealed, localSealed, "older remote content must not apply")
        XCTAssertTrue(merged.pinned, "newer remote pin applies")
    }

    // MARK: Change-tag short-circuit

    func testSameChangeTagSkipsReapply() {
        let store = makeStore()
        let record = insertLocal(store, updatedAt: Date(timeIntervalSinceNow: -100))
        record.ckChangeTag = "rev-1"
        record.pinned = true
        record.metaUpdatedAt = .now
        try? store.context.save()

        // Same server revision arrives again (e.g. next pull) — must be a no-op even
        // though its timestamps would win naively.
        store.upsertFromRemote(id: "item-1", sealed: Data([9]), favorite: false,
                               trashedAt: nil, deletedAt: nil,
                               createdAt: .distantPast, updatedAt: .distantFuture,
                               pinned: false, archived: false, metaUpdatedAt: .distantFuture,
                               isDefaultIdentity: false, avatarSealed: nil, changeTag: "rev-1")

        let merged = store.record(id: "item-1")!
        XCTAssertNotEqual(merged.sealed, Data([9]))
        XCTAssertTrue(merged.pinned, "already-merged revision must not clobber local state")
    }

    // MARK: Out-of-order push self-healing (blind overwrite must re-push the winner)

    func testLocalWinnerRemarkedDirtyWhenServerHoldsOlderRevision() {
        // Device A edited at 10:00 and pushed (clean, tag rev-A). Device B then blind-
        // pushed its OLDER 9:59 edit, so the server now holds rev-B@9:59. When A pulls
        // rev-B, nothing applies — but A must re-mark itself dirty so its newer edit
        // re-pushes; otherwise the 10:00 edit never propagates anywhere.
        let store = makeStore()
        let record = insertLocal(store, updatedAt: .now)
        record.ckChangeTag = "rev-A"
        record.dirty = false
        try? store.context.save()

        store.upsertFromRemote(id: "item-1", sealed: Data([9]), favorite: false,
                               trashedAt: nil, deletedAt: nil,
                               createdAt: .distantPast,
                               updatedAt: Date(timeIntervalSinceNow: -60),
                               pinned: false, archived: false, metaUpdatedAt: .distantPast,
                               isDefaultIdentity: false, avatarSealed: nil, changeTag: "rev-B")

        let merged = store.record(id: "item-1")!
        XCTAssertNotEqual(merged.sealed, Data([9]), "older remote content must not apply")
        XCTAssertTrue(merged.dirty, "local winner must re-push after a blind overwrite")
    }

    func testOneSidedRemoteWinForcesLocalWinnerDirty() {
        // Remote has newer meta but older content: apply the meta, and force dirty so
        // the strictly-newer local content re-pushes even though the record was clean.
        let store = makeStore()
        let record = insertLocal(store, updatedAt: .now, metaUpdatedAt: .distantPast)
        record.ckChangeTag = "rev-A"
        record.dirty = false
        try? store.context.save()

        store.upsertFromRemote(id: "item-1", sealed: Data([9]), favorite: false,
                               trashedAt: nil, deletedAt: nil,
                               createdAt: .distantPast,
                               updatedAt: Date(timeIntervalSinceNow: -60),
                               pinned: true, archived: false, metaUpdatedAt: .now,
                               isDefaultIdentity: false, avatarSealed: nil, changeTag: "rev-B")

        let merged = store.record(id: "item-1")!
        XCTAssertTrue(merged.pinned, "newer remote meta applies")
        XCTAssertTrue(merged.dirty, "newer local content must re-push")
    }

    // MARK: markSynced snapshot guard (edit during in-flight push stays dirty)

    func testMarkSyncedKeepsDirtyWhenEditedAfterSnapshot() {
        let store = makeStore()
        let record = insertLocal(store, updatedAt: .now)
        record.dirty = true
        let snapshotUpdatedAt = record.updatedAt
        let snapshotMetaUpdatedAt = record.metaUpdatedAt

        // Simulate an edit landing while modifyRecords was awaiting.
        record.updatedAt = record.updatedAt.addingTimeInterval(1)

        store.markSynced(record, changeTag: "rev-2",
                         snapshotUpdatedAt: snapshotUpdatedAt,
                         snapshotMetaUpdatedAt: snapshotMetaUpdatedAt)

        XCTAssertTrue(record.dirty, "mid-flight edit must stay dirty (would be lost otherwise)")
        XCTAssertEqual(record.ckChangeTag, "rev-2")
    }

    func testMarkSyncedClearsDirtyWhenUnchanged() {
        let store = makeStore()
        let record = insertLocal(store, updatedAt: .now)
        record.dirty = true

        store.markSynced(record, changeTag: "rev-2",
                         snapshotUpdatedAt: record.updatedAt,
                         snapshotMetaUpdatedAt: record.metaUpdatedAt)

        XCTAssertFalse(record.dirty)
    }

    // MARK: Device-local columns

    func testRemoteApplyPreservesLocalUseCount() {
        let store = makeStore()
        let record = insertLocal(store, updatedAt: Date(timeIntervalSinceNow: -100))
        record.useCount = 42
        try? store.context.save()

        store.upsertFromRemote(id: "item-1", sealed: Data([9]), favorite: false,
                               trashedAt: nil, deletedAt: nil,
                               createdAt: .distantPast, updatedAt: .now,
                               pinned: false, archived: false, metaUpdatedAt: .distantPast,
                               isDefaultIdentity: false, avatarSealed: nil, changeTag: "t1")

        XCTAssertEqual(store.record(id: "item-1")?.useCount, 42,
                       "useCount is device-local and must survive a content pull")
    }

    // MARK: Pairing crypto round-trip

    func testPairingSealOpenRoundTrip() throws {
        let session = VaultKeyPairing.makeSession()
        let vaultKey = KeyHierarchy.newVaultKey()

        let request = try VaultKeyPairing.parse(qrPayload: session.qrPayload)
        XCTAssertEqual(request.pairingId, session.pairingId)

        let sealed = try VaultKeyPairing.seal(vaultKey: vaultKey, to: request)
        let opened = try VaultKeyPairing.open(sealed, session: session)
        XCTAssertEqual(opened, vaultKey)
    }

    func testPairingEnvelopeBoundToSession() throws {
        // An envelope sealed for one session must not open under another (the
        // pairing id is bound into the HPKE info, and the keys differ).
        let sessionA = VaultKeyPairing.makeSession()
        let sessionB = VaultKeyPairing.makeSession()
        let vaultKey = KeyHierarchy.newVaultKey()

        let request = try VaultKeyPairing.parse(qrPayload: sessionA.qrPayload)
        let sealed = try VaultKeyPairing.seal(vaultKey: vaultKey, to: request)

        XCTAssertThrowsError(try VaultKeyPairing.open(sealed, session: sessionB))
    }

    func testPairingRejectsForeignPayloads() {
        XCTAssertThrowsError(try VaultKeyPairing.parse(qrPayload: "otpauth://totp/x?secret=abc"))
        XCTAssertThrowsError(try VaultKeyPairing.parse(qrPayload: "loox-pair/99/id/key"))
        XCTAssertThrowsError(try VaultKeyPairing.parse(qrPayload: "loox-pair/1//"))
    }

    // MARK: Duplicate seed-folder merge

    func testIdenticalSeedFoldersMergeAfterRemoteSyncOnly() throws {
        let store = makeStore()
        let repo = makeRepo(store: store)
        let keptId = try repo.addFolder(name: "My Vault", icon: "ic_lock_filled", color: .blue)
        let dupId = try repo.addFolder(name: "My Vault", icon: "ic_lock_filled", color: .blue)
        var item = VaultItem(category: .login, title: "Acme")
        item.folderId = dupId
        try repo.add(item)

        // Plain reloads (local activity) must NOT merge — a user may create
        // identical-looking folders on purpose; only a remote pull converges seeds.
        repo.reload()
        XCTAssertEqual(repo.folders.filter { $0.name == "My Vault" }.count, 2)

        repo.reloadAfterRemoteSync() // the post-pull path runs the merge pass

        XCTAssertEqual(repo.folders.filter { $0.name == "My Vault" }.count, 1,
                       "identical seed folders must converge to one after a pull")
        XCTAssertEqual(repo.folders.first { $0.name == "My Vault" }?.id, keptId,
                       "earliest-created folder wins")
        XCTAssertEqual(repo.items.first { $0.id == item.id }?.folderId, keptId,
                       "items re-point at the surviving folder")
    }
}
