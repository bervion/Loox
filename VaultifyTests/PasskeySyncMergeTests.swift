import CryptoKit
import Foundation
import XCTest
@testable import Vaultify

/// Store-level rules for the VaultPasskey sync plane: LWW apply, change-tag
/// short-circuit, tombstone wipe + propagation, the mark-synced snapshot guard,
/// and the dirty discipline every `PasskeyVault` mutation must follow (usedAt
/// never syncs; locked-write envelopes never enter the push set).
@MainActor
final class PasskeySyncMergeTests: XCTestCase {

    private let key = [UInt8](repeating: 0x2a, count: 32)

    private func makeStore() -> VaultStore { VaultStore(inMemory: true) }

    private func makeSecret(rp: String = "example.com", user: String = "kai",
                            userHandle: Data = Data([1]),
                            credentialID: Data? = nil) -> PasskeySecret {
        PasskeySecret(relyingParty: rp, userName: user, userHandle: userHandle,
                      credentialID: credentialID ?? Data((0..<16).map { _ in UInt8.random(in: .min ... .max) }),
                      privateKeyRaw: P256.Signing.PrivateKey().rawRepresentation,
                      counter: 0, createdAt: .now)
    }

    private func pushSet(_ store: VaultStore) -> [PasskeyRecord] {
        store.allPasskeyRecords().filter { $0.dirty && $0.envelopeSealed == nil }
    }

    // MARK: Dirty discipline

    func testSaveMarksDirtyAndEntersThePushSet() throws {
        let store = makeStore()
        let vault = PasskeyVault(store: store)

        _ = try vault.save(makeSecret(), key: key)

        XCTAssertEqual(pushSet(store).count, 1)
        XCTAssertNil(pushSet(store).first?.deletedAt)
    }

    func testTouchLastUsedNeverRedirtiesASyncedRecord() throws {
        let store = makeStore()
        let vault = PasskeyVault(store: store)
        let secret = makeSecret()
        _ = try vault.save(secret, key: key)
        let record = store.allPasskeyRecords().first!
        store.markPasskeySynced(record, changeTag: "t1", snapshotUpdatedAt: record.updatedAt)
        XCTAssertFalse(record.dirty)

        vault.touchLastUsed(credentialID: secret.credentialID)

        XCTAssertFalse(record.dirty, "usedAt is device-local — it must not re-push")
        XCTAssertNotNil(record.usedAt)
    }

    func testEnvelopeStagingIsExcludedFromThePushSet() throws {
        let store = makeStore()
        let vault = PasskeyVault(store: store)

        try vault.saveEnvelope(makeSecret(), envelopeSealed: Data([9, 9, 9]))

        XCTAssertTrue(pushSet(store).isEmpty, "locked writes must stay device-local until promoted")
        XCTAssertFalse(store.allPasskeyRecords().isEmpty)
    }

    // MARK: Tombstones (delete must propagate AND wipe, never resurrect)

    func testDeleteTombstonesWipesMaterialAndStaysInTheSyncSet() throws {
        let store = makeStore()
        let vault = PasskeyVault(store: store)
        let secret = makeSecret()
        _ = try vault.save(secret, key: key)
        let before = store.allPasskeyRecords().first!.updatedAt

        try vault.delete(credentialID: secret.credentialID)

        let record = store.allPasskeyRecords().first!
        XCTAssertNotNil(record.deletedAt)
        XCTAssertTrue(record.sealed.isEmpty, "deletion must destroy the private key material")
        XCTAssertGreaterThan(record.updatedAt, before, "tombstone must bump updatedAt or pull drops it")
        XCTAssertTrue(record.dirty)
        XCTAssertTrue(vault.all(key: key).isEmpty, "tombstones are invisible to reads")
        XCTAssertFalse(vault.hasRecord(credentialID: secret.credentialID))
    }

    func testReplacementTombstonesTheSupersededSyncedCredential() throws {
        let store = makeStore()
        let vault = PasskeyVault(store: store)
        let old = makeSecret(userHandle: Data([7]))
        _ = try vault.save(old, key: key)
        let new = makeSecret(userHandle: Data([7]))

        _ = try vault.save(new, key: key)

        let records = store.allPasskeyRecords()
        XCTAssertEqual(records.count, 2)
        let oldRecord = records.first { $0.id == old.credentialID.base64URLEncodedString() }!
        XCTAssertNotNil(oldRecord.deletedAt, "a synced replaced credential must tombstone, not vanish")
        XCTAssertTrue(oldRecord.sealed.isEmpty)
        XCTAssertEqual(vault.all(key: key).map(\.credentialID), [new.credentialID])
    }

    func testRemoteTombstoneWinsOverOlderLocalContentAndWipes() throws {
        let store = makeStore()
        let vault = PasskeyVault(store: store)
        let secret = makeSecret()
        _ = try vault.save(secret, key: key)
        let record = store.allPasskeyRecords().first!
        store.markPasskeySynced(record, changeTag: "t1", snapshotUpdatedAt: record.updatedAt)

        store.upsertPasskeyFromRemote(id: record.id, sealed: Data(), largeBlobSealed: nil,
                                      deletedAt: .now, createdAt: record.createdAt,
                                      updatedAt: record.updatedAt.addingTimeInterval(10),
                                      changeTag: "t2")

        XCTAssertNotNil(store.allPasskeyRecords().first?.deletedAt)
        XCTAssertTrue(store.allPasskeyRecords().first!.sealed.isEmpty)
        XCTAssertTrue(vault.all(key: key).isEmpty)
    }

    // MARK: LWW apply

    func testRemoteNewerAppliesCleanAndStoresChangeTag() {
        let store = makeStore()
        let now = Date.now

        store.upsertPasskeyFromRemote(id: "pk-1", sealed: Data([1]), largeBlobSealed: Data([2]),
                                      deletedAt: nil, createdAt: now, updatedAt: now,
                                      changeTag: "t1")

        let record = store.passkeyRecord(id: "pk-1")!
        XCTAssertFalse(record.dirty, "a remote apply is already in sync")
        XCTAssertEqual(record.ckChangeTag, "t1")
        XCTAssertEqual(record.largeBlobSealed, Data([2]))
    }

    func testLocalWinnerIsKeptAndRemarkedDirtyWhenServerHoldsOlderRevision() throws {
        let store = makeStore()
        let vault = PasskeyVault(store: store)
        let secret = makeSecret()
        _ = try vault.save(secret, key: key)
        let record = store.allPasskeyRecords().first!
        store.markPasskeySynced(record, changeTag: "t1", snapshotUpdatedAt: record.updatedAt)
        let localSealed = record.sealed

        store.upsertPasskeyFromRemote(id: record.id, sealed: Data([9]), largeBlobSealed: nil,
                                      deletedAt: nil, createdAt: record.createdAt,
                                      updatedAt: record.updatedAt.addingTimeInterval(-100),
                                      changeTag: "t0")

        XCTAssertEqual(record.sealed, localSealed, "older server revision must not clobber")
        XCTAssertTrue(record.dirty, "the local winner must re-push")
    }

    func testSameChangeTagSkipsReapply() throws {
        let store = makeStore()
        let vault = PasskeyVault(store: store)
        let secret = makeSecret()
        _ = try vault.save(secret, key: key)
        let record = store.allPasskeyRecords().first!
        store.markPasskeySynced(record, changeTag: "t1", snapshotUpdatedAt: record.updatedAt)
        let localSealed = record.sealed

        store.upsertPasskeyFromRemote(id: record.id, sealed: Data([9]), largeBlobSealed: nil,
                                      deletedAt: nil, createdAt: record.createdAt,
                                      updatedAt: record.updatedAt.addingTimeInterval(100),
                                      changeTag: "t1")

        XCTAssertEqual(record.sealed, localSealed, "same server revision must be a no-op")
        XCTAssertFalse(record.dirty)
    }

    func testRemoteApplyPreservesLocalUsedAt() throws {
        let store = makeStore()
        let vault = PasskeyVault(store: store)
        let secret = makeSecret()
        _ = try vault.save(secret, key: key)
        vault.touchLastUsed(credentialID: secret.credentialID)
        let record = store.allPasskeyRecords().first!
        let used = record.usedAt
        XCTAssertNotNil(used)

        store.upsertPasskeyFromRemote(id: record.id, sealed: record.sealed, largeBlobSealed: nil,
                                      deletedAt: nil, createdAt: record.createdAt,
                                      updatedAt: record.updatedAt.addingTimeInterval(10),
                                      changeTag: "t2")

        XCTAssertEqual(record.usedAt, used, "usedAt is device-local and survives remote applies")
    }

    // MARK: Mark-synced snapshot guard

    func testMarkSyncedClearsDirtyOnlyWhenUnchangedSinceSnapshot() throws {
        let store = makeStore()
        let vault = PasskeyVault(store: store)
        let secret = makeSecret()
        _ = try vault.save(secret, key: key)
        let record = store.allPasskeyRecords().first!
        let snapshot = record.updatedAt

        // Edited mid-flight (large-blob write after the push snapshot) → stays dirty.
        XCTAssertTrue(vault.setLargeBlob(Data([5]), credentialID: secret.credentialID, key: key))
        store.markPasskeySynced(record, changeTag: "t1", snapshotUpdatedAt: snapshot)
        XCTAssertTrue(record.dirty, "an edit after the snapshot must survive the mark")

        // Clean mark with the CURRENT revision → clears.
        store.markPasskeySynced(record, changeTag: "t2", snapshotUpdatedAt: record.updatedAt)
        XCTAssertFalse(record.dirty)
    }
}
