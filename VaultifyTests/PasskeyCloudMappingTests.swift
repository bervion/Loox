import CloudKit
import CryptoKit
import Foundation
import XCTest
@testable import Vaultify

/// The wire contract of the `VaultPasskey` plane: the exact CKRecord field names
/// and types the deployed CloudKit schema must carry, and the round trip from a
/// local record through that CKRecord into a second device's store.
///
/// This is the layer nothing covered: `PasskeySyncMergeTests` proves the store's
/// LWW rules, but a renamed, missing, or wrongly-typed field would have passed
/// every one of them while the plane failed against the server on every push.
/// Sync is hard-disabled under XCTest (`CloudSyncService.isHostingUnitTests`), so
/// the mapping is exercised directly and never reaches the network.
@MainActor
final class PasskeyCloudMappingTests: XCTestCase {

    /// The deployed schema, field by field. Changing this table means the CloudKit
    /// schema must change with it, in Development AND in Production.
    private enum SchemaType { case bytes, date, int64 }
    private static let schema: [(field: String, type: SchemaType)] = [
        ("sealed", .bytes),
        ("largeBlobSealed", .bytes),
        ("createdAt", .date),
        ("updatedAt", .date),
        ("deletedAtMs", .int64),
    ]

    private let key = [UInt8](repeating: 0x2a, count: 32)

    /// An isolated settings suite (never the shared app-group config) and a service
    /// that only ever runs its mapping functions — `sync()` is hard-disabled under
    /// XCTest, and nothing here touches `CKContainer`, which traps unsigned.
    private func makeService(_ store: VaultStore) -> CloudSyncService {
        let defaults = UserDefaults(suiteName: "passkey-mapping-\(UUID().uuidString)")!
        let service = CloudSyncService(store: store,
                                       settings: SettingsStore(defaults: defaults,
                                                               mirrorToSharedConfig: false))
        TestLifetimeRetainer.retain(store, service)
        return service
    }

    private func makeSecret() -> PasskeySecret {
        PasskeySecret(relyingParty: "example.com", userName: "kai", userHandle: Data([1]),
                      credentialID: Data((0 ..< 16).map { _ in UInt8.random(in: .min ... .max) }),
                      privateKeyRaw: P256.Signing.PrivateKey().rawRepresentation,
                      counter: 0, createdAt: .now)
    }

    /// A saved passkey plus the CKRecord this device would push for it. The store
    /// is retained past this call: the returned `PasskeyRecord` is a live SwiftData
    /// model, and reading it after its container deallocates faults.
    private func makePushedRecord(largeBlob: Data? = nil,
                                  tombstone: Bool = false) throws -> (local: PasskeyRecord, ck: CKRecord) {
        let store = VaultStore(inMemory: true)
        TestLifetimeRetainer.retain(store)
        let vault = PasskeyVault(store: store)
        let secret = makeSecret()
        _ = try vault.save(secret, key: key)
        if let largeBlob {
            XCTAssertTrue(vault.setLargeBlob(largeBlob, credentialID: secret.credentialID, key: key))
        }
        if tombstone { try vault.delete(credentialID: secret.credentialID) }
        let local = store.allPasskeyRecords().first!
        return (local, makeService(store).ckPasskeyRecord(from: local))
    }

    // MARK: Schema contract

    func testPushedRecordCarriesExactlyTheDeployedSchemaFields() throws {
        let (_, ck) = try makePushedRecord(largeBlob: Data([7, 7, 7]))

        XCTAssertEqual(ck.recordType, "VaultPasskey",
                       "the record type is deployed schema, not an implementation detail")
        XCTAssertEqual(Set(ck.allKeys()), Set(Self.schema.map(\.field)),
                       "a field added or renamed here must be deployed to CloudKit first")
    }

    func testFieldTypesMatchTheDeployedSchema() throws {
        let (_, ck) = try makePushedRecord(largeBlob: Data([7, 7, 7]))

        for (field, type) in Self.schema {
            switch type {
            case .bytes: XCTAssertNotNil(ck[field] as? Data, "\(field) must be Bytes")
            case .date: XCTAssertNotNil(ck[field] as? Date, "\(field) must be Date")
            case .int64: XCTAssertNotNil(ck[field] as? Int64, "\(field) must be Int64")
            }
        }
    }

    func testEveryFieldIsWrittenEvenWhenEmptySoChangedKeysCanClearIt() throws {
        // No blob, no tombstone: absence must ride in-band (empty Data / 0 ms),
        // because `.changedKeys` transmits only the keys present on the record.
        let (_, ck) = try makePushedRecord()

        XCTAssertEqual(Set(ck.allKeys()), Set(Self.schema.map(\.field)))
        XCTAssertEqual(ck["largeBlobSealed"] as? Data, Data())
        XCTAssertEqual(ck["deletedAtMs"] as? Int64, 0)
    }

    func testRecordNameIsTheCredentialIDWithinCloudKitsCap() throws {
        let (local, ck) = try makePushedRecord()

        XCTAssertEqual(ck.recordID.recordName, local.id)
        XCTAssertLessThanOrEqual(ck.recordID.recordName.utf8.count, CloudSyncService.maxRecordNameBytes)
    }

    // MARK: Round trip onto a second device

    func testRoundTripReproducesTheRecordFieldForFieldOnASecondStore() throws {
        let (local, ck) = try makePushedRecord(largeBlob: Data([1, 2, 3, 4]))

        let peerStore = VaultStore(inMemory: true)
        makeService(peerStore).applyPasskey(ck)

        let pulled = try XCTUnwrap(peerStore.passkeyRecord(id: local.id),
                                   "the pull must materialize the credential on the peer")
        XCTAssertEqual(pulled.sealed, local.sealed)
        XCTAssertEqual(pulled.largeBlobSealed, local.largeBlobSealed)
        XCTAssertEqual(pulled.createdAt.timeIntervalSince1970,
                       local.createdAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(pulled.updatedAt.timeIntervalSince1970,
                       local.updatedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertNil(pulled.deletedAt)
        XCTAssertFalse(pulled.dirty, "a pulled record is already in sync")
    }

    func testRoundTripUnsealsToTheSameSecretOnTheSecondStore() throws {
        let store = VaultStore(inMemory: true)
        let vault = PasskeyVault(store: store)
        let secret = makeSecret()
        _ = try vault.save(secret, key: key)
        let ck = makeService(store).ckPasskeyRecord(from: store.allPasskeyRecords().first!)

        let peerStore = VaultStore(inMemory: true)
        makeService(peerStore).applyPasskey(ck)

        let peer = PasskeyVault(store: peerStore).all(key: key)
        XCTAssertEqual(peer.map(\.credentialID), [secret.credentialID],
                       "the sealed blob must survive the wire intact")
        XCTAssertEqual(peer.first?.relyingParty, secret.relyingParty)
    }

    func testTombstoneRoundTripsThroughTheMillisecondField() throws {
        let (local, ck) = try makePushedRecord(tombstone: true)
        let deletedAt = try XCTUnwrap(local.deletedAt)
        XCTAssertGreaterThan(try XCTUnwrap(ck["deletedAtMs"] as? Int64), 0)

        let peerStore = VaultStore(inMemory: true)
        makeService(peerStore).applyPasskey(ck)

        let pulled = try XCTUnwrap(peerStore.passkeyRecord(id: local.id))
        XCTAssertEqual(try XCTUnwrap(pulled.deletedAt).timeIntervalSince1970,
                       deletedAt.timeIntervalSince1970, accuracy: 0.001,
                       "a deletion must arrive as a tombstone, not as live content")
        XCTAssertTrue(pulled.sealed.isEmpty, "a tombstone carries no key material")
    }

    func testEmptyBlobFieldArrivesAsNoBlobRatherThanEmptyData() throws {
        let (local, ck) = try makePushedRecord()

        let peerStore = VaultStore(inMemory: true)
        makeService(peerStore).applyPasskey(ck)

        XCTAssertNil(peerStore.passkeyRecord(id: local.id)?.largeBlobSealed)
    }

    func testARecordMissingASchemaFieldIsIgnoredInsteadOfLandingHalfWritten() throws {
        let (local, ck) = try makePushedRecord()
        // What a schema drift looks like on the wire: `updatedAt` never written.
        let partial = CKRecord(recordType: ck.recordType, recordID: ck.recordID)
        partial["sealed"] = ck["sealed"] as? Data
        partial["createdAt"] = ck["createdAt"] as? Date

        let peerStore = VaultStore(inMemory: true)
        makeService(peerStore).applyPasskey(partial)

        XCTAssertNil(peerStore.passkeyRecord(id: local.id),
                     "a record missing a schema field must not land as a partial credential")
    }
}
