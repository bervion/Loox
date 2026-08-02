import CloudKit
import Foundation
import XCTest
@testable import Vaultify

/// The wire contract of the (flag-gated) `ArtifactV2` CloudKit plane: exact
/// field names/types, in-band absence sentinels (the `.changedKeys` clear
/// rule), tombstone shape, parse strictness against half-written records,
/// and the tombstone-wins LWW merge table.
@MainActor
final class ArtifactCloudMappingTests: XCTestCase {

    /// The schema this plane will deploy, field by field. Changing the table
    /// means changing the CloudKit schema first (Development AND Production).
    private enum SchemaType { case string, bytes, date, int64, asset }
    private static let schema: [(field: String, type: SchemaType)] = [
        ("ownerItemId", .string),
        ("wrappedDEK", .bytes),
        ("sealedManifest", .bytes),
        ("byteCount", .int64),
        ("ciphertextHash", .bytes),
        ("createdAt", .date),
        ("updatedAt", .date),
        ("deletedAtMs", .int64),
        ("asset", .asset),
    ]

    private let zoneID = CKRecordZone(zoneName: "Vault").zoneID

    private func makeRecord(tombstoned: Bool = false) -> ArtifactRecord {
        let record = ArtifactRecord(id: UUID().uuidString,
                                    ownerItemId: "owner-1",
                                    wrappedDEK: Data([1, 2, 3]),
                                    sealedManifest: Data([4, 5, 6]),
                                    relativePath: "x.enc",
                                    byteCount: 42,
                                    ciphertextHash: Data([7, 8, 9]),
                                    createdAt: Date(timeIntervalSince1970: 100),
                                    updatedAt: Date(timeIntervalSince1970: 200))
        if tombstoned { record.deletedAt = Date(timeIntervalSince1970: 300) }
        // Records live in a container during mapping in production; mirror that.
        let store = VaultStore(inMemory: true)
        store.context.insert(record)
        TestLifetimeRetainer.retain(store)
        return record
    }

    private func makeAssetFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "artifact-mapping-\(UUID().uuidString).enc")
        try Data([0xAA, 0xBB]).write(to: url)
        return url
    }

    // MARK: Schema contract

    func testLiveRecordCarriesExactlyTheSchemaFieldsWithTheRightTypes() throws {
        let ck = ArtifactCloudMapping.ckRecord(from: makeRecord(), zoneID: zoneID,
                                               assetFileURL: try makeAssetFile())

        XCTAssertEqual(ck.recordType, "ArtifactV2")
        XCTAssertEqual(Set(ck.allKeys()), Set(Self.schema.map(\.field)),
                       "a field added or renamed here must be deployed to CloudKit first")
        for (field, type) in Self.schema {
            switch type {
            case .string: XCTAssertNotNil(ck[field] as? String, "\(field) must be String")
            case .bytes: XCTAssertNotNil(ck[field] as? Data, "\(field) must be Bytes")
            case .date: XCTAssertNotNil(ck[field] as? Date, "\(field) must be Date")
            case .int64: XCTAssertNotNil(ck[field] as? Int64, "\(field) must be Int64")
            case .asset: XCTAssertNotNil(ck[field] as? CKAsset, "\(field) must be Asset")
            }
        }
    }

    func testRecordNameIsTheArtifactIdWithinCloudKitsCap() throws {
        let record = makeRecord()
        let ck = ArtifactCloudMapping.ckRecord(from: record, zoneID: zoneID, assetFileURL: nil)

        XCTAssertEqual(ck.recordID.recordName, record.id)
        XCTAssertLessThanOrEqual(ck.recordID.recordName.utf8.count,
                                 CloudSyncService.maxRecordNameBytes)
    }

    // MARK: Sentinels (`.changedKeys` clear rule)

    func testLiveRecordWritesZeroTombstoneSentinel() throws {
        let ck = ArtifactCloudMapping.ckRecord(from: makeRecord(), zoneID: zoneID,
                                               assetFileURL: try makeAssetFile())
        XCTAssertEqual(ck["deletedAtMs"] as? Int64, 0,
                       "absence rides in-band as 0 so a revived record can clear a cloud tombstone")
    }

    func testLiveRecordWithoutLocalBytesOmitsOnlyTheAsset() {
        let ck = ArtifactCloudMapping.ckRecord(from: makeRecord(), zoneID: zoneID,
                                               assetFileURL: nil)
        XCTAssertEqual(Set(ck.allKeys()),
                       Set(Self.schema.map(\.field)).subtracting(["asset"]),
                       "missing bytes must not fake an asset; every other field still writes")
    }

    func testTombstoneEmptiesSealedFieldsAndDropsTheAsset() throws {
        let ck = ArtifactCloudMapping.ckRecord(from: makeRecord(tombstoned: true), zoneID: zoneID,
                                               assetFileURL: try makeAssetFile())

        XCTAssertEqual(ck["wrappedDEK"] as? Data, Data(), "a tombstone carries no key material")
        XCTAssertEqual(ck["sealedManifest"] as? Data, Data())
        XCTAssertEqual(ck["ciphertextHash"] as? Data, Data())
        XCTAssertEqual(ck["byteCount"] as? Int64, 0)
        XCTAssertEqual(ck["deletedAtMs"] as? Int64, Int64(300 * 1000))
        XCTAssertNil(ck["asset"], "a tombstone never uploads ciphertext")
    }

    // MARK: Parse

    func testParseRoundTripsALiveRecordFieldForField() throws {
        let record = makeRecord()
        let assetURL = try makeAssetFile()
        let ck = ArtifactCloudMapping.ckRecord(from: record, zoneID: zoneID, assetFileURL: assetURL)

        let parsed = try XCTUnwrap(ArtifactCloudMapping.parse(ck))
        XCTAssertEqual(parsed.id, record.id)
        XCTAssertEqual(parsed.ownerItemId, record.ownerItemId)
        XCTAssertEqual(parsed.wrappedDEK, record.wrappedDEK)
        XCTAssertEqual(parsed.sealedManifest, record.sealedManifest)
        XCTAssertEqual(parsed.byteCount, record.byteCount)
        XCTAssertEqual(parsed.ciphertextHash, record.ciphertextHash)
        XCTAssertNil(parsed.deletedAt)
        XCTAssertEqual(parsed.createdAt.timeIntervalSince1970,
                       record.createdAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(parsed.updatedAt.timeIntervalSince1970,
                       record.updatedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(parsed.assetFileURL, assetURL)
    }

    func testParseTombstoneYieldsDeletedAtAndIgnoresAnyStrayAsset() throws {
        let ck = ArtifactCloudMapping.ckRecord(from: makeRecord(tombstoned: true),
                                               zoneID: zoneID, assetFileURL: nil)
        // A stale asset a server-side race left behind must be dead weight.
        ck["asset"] = CKAsset(fileURL: try makeAssetFile())

        let parsed = try XCTUnwrap(ArtifactCloudMapping.parse(ck))
        XCTAssertEqual(try XCTUnwrap(parsed.deletedAt).timeIntervalSince1970, 300, accuracy: 0.001)
        XCTAssertNil(parsed.assetFileURL)
    }

    func testParseRejectsARecordMissingASchemaField() throws {
        let full = ArtifactCloudMapping.ckRecord(from: makeRecord(), zoneID: zoneID,
                                                 assetFileURL: nil)
        // Schema drift on the wire: `updatedAt` never written.
        let partial = CKRecord(recordType: full.recordType, recordID: full.recordID)
        for key in full.allKeys() where key != "updatedAt" {
            partial[key] = full[key]
        }

        XCTAssertNil(ArtifactCloudMapping.parse(partial),
                     "a half-written record must not land as a partial artifact")
    }

    // MARK: Merge policy (single-owner LWW, tombstone wins)

    func testMergeTable() {
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        func merge(_ local: Date, _ localDeleted: Date?,
                   _ remote: Date, _ remoteDeleted: Date?) -> ArtifactCloudMapping.MergeDecision {
            ArtifactCloudMapping.merge(localUpdatedAt: local, localDeletedAt: localDeleted,
                                       remoteUpdatedAt: remote, remoteDeletedAt: remoteDeleted)
        }

        // Both live: strict LWW by updatedAt; equal keeps local (no ping-pong).
        XCTAssertEqual(merge(older, nil, newer, nil), .applyRemote)
        XCTAssertEqual(merge(newer, nil, older, nil), .keepLocal)
        XCTAssertEqual(merge(newer, nil, newer, nil), .keepLocal)

        // Tombstone wins in both directions, regardless of clocks.
        XCTAssertEqual(merge(newer, nil, older, older), .applyRemote,
                       "a skewed clock must never resurrect a deleted artifact")
        XCTAssertEqual(merge(older, older, newer, nil), .keepLocal)

        // Both tombstoned: plain LWW again.
        XCTAssertEqual(merge(older, older, newer, newer), .applyRemote)
        XCTAssertEqual(merge(newer, newer, older, older), .keepLocal)
    }

    // MARK: Plane constants

    func testCursorKeyIsThePlanesOwnPersistedContract() {
        XCTAssertEqual(ArtifactCloudMapping.cursorKey, "cloudkit_artifact_zone_change_token",
                       "the cursor key is persisted device state — renaming it re-syncs every artifact")
        XCTAssertNotEqual(ArtifactCloudMapping.cursorKey, "cloudkit_vault_zone_change_token",
                          "the artifact plane must never share the vault planes' cursor")
        XCTAssertGreaterThan(ArtifactCloudMapping.tombstoneRetentionSeconds, 0)
    }
}
