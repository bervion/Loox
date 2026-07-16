import CloudKit
import XCTest
@testable import Vaultify

/// Project A phase A3 stage 1, Part 1: `ApprovalShareService`'s pure
/// same-item-supersede + per-grant-revoke record-footprint reduction. The
/// CloudKit-touching wrappers (`fetchAllGrants`, `revokeGrant`,
/// `supersededGrantRecordIDs`, and `publishGrant`'s flag-on replace path
/// itself) are exercised by the two-account device checklist, same
/// convention as `FamilyShareTransportTests` — only the PURE decode/match/
/// footprint reduction is unit-tested here.
final class ApprovalShareServiceSupersedeTests: XCTestCase {

    private let zoneID = CKRecordZone.ID(zoneName: "apz-test", ownerName: "_owner1")
    private let nowMs: Int64 = 1_783_256_400_000
    private let owner = DeviceSigningIdentity.ephemeral()

    private func makeGrant(id: String, itemId: String, owner: DeviceSigningIdentity) throws -> AccessGrant {
        var grant = AccessGrant(
            id: id, itemId: itemId, recipientId: "rcpt-1",
            participantPubKey: Data(repeating: 1, count: 32),
            pinnedDeviceSigningKeys: [Data(repeating: 2, count: 64)],
            capabilities: ["f": .value(.shared)], epoch: 1,
            createdAtUnixMs: nowMs, expiresAtUnixMs: nil,
            ownerSigningPubKey: owner.publicKeyRaw, ownerSignature: Data())
        grant.ownerSignature = try owner.signature(for: grant.signingBody())
        return grant
    }

    /// Builds a grant record under an EXPLICIT name, independent of
    /// `FamilyShareTransport.perGrantEnabled`'s current value — same
    /// rationale as `FamilyShareTransportTests.manualGrantRecord`.
    private func manualGrantRecord(_ grant: AccessGrant, name: String) -> CKRecord {
        let record = CKRecord(recordType: ApprovalConfig.grantRecordType,
                              recordID: CKRecord.ID(recordName: name, zoneID: zoneID))
        record[ApprovalRecordMapping.Field.blob] = grant.encoded() as CKRecordValue
        return record
    }

    private func fieldRecord(grantId: String, fieldId: String) -> CKRecord {
        ApprovalRecordMapping.sharedFieldRecord(
            sealedBlob: Data("ciphertext".utf8), grantId: grantId, fieldId: fieldId, zoneID: zoneID)
    }

    private func displayRecordID(grantId: String) -> CKRecord.ID {
        CKRecord.ID(recordName: ApprovalConfig.displayEnvelopeRecordName(grantId: grantId), zoneID: zoneID)
    }

    private var legacyGrantRecordID: CKRecord.ID {
        CKRecord.ID(recordName: ApprovalConfig.legacyGrantRecordName, zoneID: zoneID)
    }

    private var legacyDisplayRecordID: CKRecord.ID {
        CKRecord.ID(recordName: ApprovalConfig.legacyDisplayEnvelopeRecordName, zoneID: zoneID)
    }

    // MARK: supersededRecordIDs(forItemId:in:) — Part 1 (publishGrant replace-on-republish)

    func testFindsPriorGrantForSameItemByAuthenticatedItemId() throws {
        let prior = try makeGrant(id: "grant-old", itemId: "item-1", owner: owner)
        let priorRecord = manualGrantRecord(prior, name: ApprovalConfig.grantRecordName(grantId: prior.id))

        let ids = ApprovalShareService.supersededRecordIDs(forItemId: "item-1", in: [priorRecord])

        XCTAssertTrue(ids.contains(priorRecord.recordID))
        XCTAssertTrue(ids.contains(displayRecordID(grantId: "grant-old")))
    }

    func testIgnoresGrantsForOtherItems() throws {
        let other = try makeGrant(id: "grant-other", itemId: "item-2", owner: owner)
        let record = manualGrantRecord(other, name: ApprovalConfig.grantRecordName(grantId: other.id))

        let ids = ApprovalShareService.supersededRecordIDs(forItemId: "item-1", in: [record])

        XCTAssertTrue(ids.isEmpty)
    }

    /// A legacy-named prior grant (item shared before the flag ever turned
    /// on, or before Family sharing existed) must be findable and its
    /// LEGACY display name removed too — the legacy grant + display were
    /// always written together.
    func testIncludesLegacyDisplayNameWhenThePriorGrantWasLegacyNamed() throws {
        let prior = try makeGrant(id: "grant-legacy", itemId: "item-1", owner: owner)
        let legacyRecord = manualGrantRecord(prior, name: ApprovalConfig.legacyGrantRecordName)

        let ids = ApprovalShareService.supersededRecordIDs(forItemId: "item-1", in: [legacyRecord])

        XCTAssertTrue(ids.contains(legacyGrantRecordID))
        XCTAssertTrue(ids.contains(legacyDisplayRecordID))
    }

    func testDoesNotAddTheLegacyDisplayNameForAPerGrantNamedPriorGrant() throws {
        let prior = try makeGrant(id: "grant-x", itemId: "item-1", owner: owner)
        let perGrantRecord = manualGrantRecord(prior, name: ApprovalConfig.grantRecordName(grantId: prior.id))

        let ids = ApprovalShareService.supersededRecordIDs(forItemId: "item-1", in: [perGrantRecord])

        XCTAssertFalse(ids.contains(legacyDisplayRecordID))
    }

    func testIncludesOnlyFieldRecordsScopedToThePriorGrantsId() throws {
        let prior = try makeGrant(id: "grant-old", itemId: "item-1", owner: owner)
        let priorRecord = manualGrantRecord(prior, name: ApprovalConfig.grantRecordName(grantId: prior.id))
        let matchingField = fieldRecord(grantId: "grant-old", fieldId: "f1")
        let siblingField = fieldRecord(grantId: "grant-sibling", fieldId: "f1")

        let ids = ApprovalShareService.supersededRecordIDs(
            forItemId: "item-1", in: [priorRecord, matchingField, siblingField])

        XCTAssertTrue(ids.contains(matchingField.recordID))
        XCTAssertFalse(ids.contains(siblingField.recordID))
    }

    /// A malformed/transitional zone where the SAME grant appears under two
    /// names (legacy singleton + per-grant record) must not yield the same
    /// record id twice — a duplicate in one CloudKit delete batch.
    func testDeduplicatesWhenTheSameGrantAppearsUnderTwoRecordNames() throws {
        let prior = try makeGrant(id: "grant-dup", itemId: "item-1", owner: owner)
        let legacyRecord = manualGrantRecord(prior, name: ApprovalConfig.legacyGrantRecordName)
        let perGrantRecord = manualGrantRecord(prior, name: ApprovalConfig.grantRecordName(grantId: prior.id))

        let ids = ApprovalShareService.supersededRecordIDs(
            forItemId: "item-1", in: [legacyRecord, perGrantRecord])

        let displayID = displayRecordID(grantId: "grant-dup")
        XCTAssertEqual(ids.filter { $0 == displayID }.count, 1)
    }

    func testReturnsEmptyOverAnEmptyRecordSet() {
        XCTAssertTrue(ApprovalShareService.supersededRecordIDs(forItemId: "item-1", in: []).isEmpty)
    }

    // MARK: recordIDs(forGrantId:in:) — Part 2 (executor per-item revoke)

    func testRecordIDsForGrantIdFindsTheExactGrantRegardlessOfRecordName() throws {
        let grant = try makeGrant(id: "grant-y", itemId: "item-1", owner: owner)
        let legacyRecord = manualGrantRecord(grant, name: ApprovalConfig.legacyGrantRecordName)

        let ids = ApprovalShareService.recordIDs(forGrantId: "grant-y", in: [legacyRecord])

        XCTAssertTrue(ids.contains(legacyRecord.recordID))
        XCTAssertTrue(ids.contains(legacyDisplayRecordID))
    }

    func testRecordIDsForGrantIdIncludesOnlyItsOwnFieldRecords() throws {
        let grant = try makeGrant(id: "grant-y", itemId: "item-1", owner: owner)
        let record = manualGrantRecord(grant, name: ApprovalConfig.grantRecordName(grantId: grant.id))
        let ownField = fieldRecord(grantId: "grant-y", fieldId: "f1")
        let otherField = fieldRecord(grantId: "grant-z", fieldId: "f1")

        let ids = ApprovalShareService.recordIDs(forGrantId: "grant-y", in: [record, ownField, otherField])

        XCTAssertTrue(ids.contains(ownField.recordID))
        XCTAssertFalse(ids.contains(otherField.recordID))
    }

    func testRecordIDsForGrantIdIgnoresAGrantWithADifferentId() throws {
        let grant = try makeGrant(id: "grant-y", itemId: "item-1", owner: owner)
        let record = manualGrantRecord(grant, name: ApprovalConfig.grantRecordName(grantId: grant.id))

        let ids = ApprovalShareService.recordIDs(forGrantId: "grant-does-not-exist", in: [record])

        XCTAssertTrue(ids.isEmpty)
    }

    func testRecordIDsForGrantIdReturnsEmptyOverAnEmptyRecordSet() {
        XCTAssertTrue(ApprovalShareService.recordIDs(forGrantId: "missing", in: []).isEmpty)
    }
}
