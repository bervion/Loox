import CloudKit
import XCTest
@testable import Vaultify

/// Project A phase A1 (per-grant sharing transport — see
/// `plans/260715-1848-family-devices-crypto/family-group-transport.md`):
/// per-grant record naming round-trip + the legacy-fallback dedupe that lets
/// a zone project more than one grant. The networked halves (`record(for:)`,
/// `ZoneDeltaFetch.pull`) are exercised by the two-account device checklist,
/// same convention as `SharedAccessAuthorizerTests` — only the PURE
/// decode/dedupe/verify reduction is unit-tested here.
final class FamilyShareTransportTests: XCTestCase {

    private let zoneID = CKRecordZone.ID(zoneName: "apz-test", ownerName: "_owner1")
    private let nowMs: Int64 = 1_783_256_400_000
    private let owner = DeviceSigningIdentity.ephemeral()

    private func makeGrant(id: String, itemId: String = "item-1",
                           owner: DeviceSigningIdentity) throws -> AccessGrant {
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

    /// Builds a grant record under an EXPLICIT name — independent of
    /// `FamilyShareTransport.perGrantEnabled`'s current value, so tests that
    /// simulate "a per-grant record alongside the legacy singleton" stay
    /// meaningful no matter which way the flag defaults.
    private func manualGrantRecord(_ grant: AccessGrant, name: String) -> CKRecord {
        let record = CKRecord(recordType: ApprovalConfig.grantRecordType,
                              recordID: CKRecord.ID(recordName: name, zoneID: zoneID))
        record[ApprovalRecordMapping.Field.blob] = grant.encoded() as CKRecordValue
        return record
    }

    // MARK: ApprovalConfig — per-grant naming (pure)

    func testPerGrantRecordNamesAreDeterministicAndDistinctPerGrantId() {
        XCTAssertEqual(ApprovalConfig.grantRecordName(grantId: "abc"), "grant:abc")
        XCTAssertEqual(ApprovalConfig.grantRecordName(grantId: "abc"),
                       ApprovalConfig.grantRecordName(grantId: "abc"))
        XCTAssertNotEqual(ApprovalConfig.grantRecordName(grantId: "abc"),
                          ApprovalConfig.grantRecordName(grantId: "xyz"))

        XCTAssertEqual(ApprovalConfig.displayEnvelopeRecordName(grantId: "abc"), "display:abc")
        XCTAssertNotEqual(ApprovalConfig.displayEnvelopeRecordName(grantId: "abc"),
                          ApprovalConfig.grantRecordName(grantId: "abc"))
    }

    /// Back-compat pin: renaming `grantRecordName`/`displayEnvelopeRecordName`
    /// to `legacyGrantRecordName`/`legacyDisplayEnvelopeRecordName` must never
    /// change the STRING an existing single-item share was published under.
    func testLegacyRecordNameConstantsUnchangedByRename() {
        XCTAssertEqual(ApprovalConfig.legacyGrantRecordName, "grant")
        XCTAssertEqual(ApprovalConfig.legacyDisplayEnvelopeRecordName, "display-envelope")
    }

    // MARK: ApprovalRecordMapping — record-name round-trip (pure)

    /// Acceptance criterion: with `FamilyShareTransport.perGrantEnabled`
    /// false (default), the owner write path is byte-for-byte what it was
    /// before this transport existed.
    func testGrantRecordUsesLegacyNameWhileFlagDisabled() throws {
        XCTAssertFalse(FamilyShareTransport.perGrantEnabled,
                       "default must stay off — flipping it is a deliberate, separate decision")
        let grant = try makeGrant(id: "grant-y", owner: owner)
        let record = ApprovalRecordMapping.grantRecord(grant, zoneID: zoneID)
        XCTAssertEqual(record.recordID.recordName, ApprovalConfig.legacyGrantRecordName)
    }

    func testDisplayEnvelopeRecordUsesLegacyNameWhileFlagDisabled() {
        let blob = Data("ciphertext".utf8)
        let record = ApprovalRecordMapping.displayEnvelopeRecord(
            sealedBlob: blob, grantId: "grant-z", zoneID: zoneID)
        XCTAssertEqual(record.recordID.recordName, ApprovalConfig.legacyDisplayEnvelopeRecordName)
        XCTAssertEqual(ApprovalRecordMapping.displayEnvelope(from: record)?.grantId, "grant-z")
        XCTAssertEqual(ApprovalRecordMapping.displayEnvelope(from: record)?.blob, blob)
    }

    /// INV-FAM-01 foundation: a grant record's identity is the AUTHENTICATED
    /// decoded blob, never the record name — decoding must be identical
    /// whether the record carries the legacy singleton name or a per-grant
    /// name.
    func testGrantRecordDecodeIsIndependentOfRecordName() throws {
        let grant = try makeGrant(id: "grant-x", owner: owner)
        let legacyNamed = manualGrantRecord(grant, name: ApprovalConfig.legacyGrantRecordName)
        let perGrantNamed = manualGrantRecord(grant, name: ApprovalConfig.grantRecordName(grantId: grant.id))

        XCTAssertEqual(ApprovalRecordMapping.grant(from: legacyNamed), grant)
        XCTAssertEqual(ApprovalRecordMapping.grant(from: perGrantNamed), grant)
    }

    // MARK: ApprovalRecipientService.dedupedLiveGrants — legacy-fallback projection (pure)

    /// The core A1 device-test scenario ("publish grant A then B in one zone
    /// → recipient projects both"), at the unit level: two DIFFERENT grants
    /// in the same zone both survive enumeration.
    func testDedupedLiveGrantsRecognizesTwoDistinctGrantsInOneZone() throws {
        let grantA = try makeGrant(id: "grant-a", itemId: "item-a", owner: owner)
        let grantB = try makeGrant(id: "grant-b", itemId: "item-b", owner: owner)
        let records = [manualGrantRecord(grantA, name: ApprovalConfig.grantRecordName(grantId: grantA.id)),
                       manualGrantRecord(grantB, name: ApprovalConfig.grantRecordName(grantId: grantB.id))]

        let live = ApprovalRecipientService.dedupedLiveGrants(
            from: records, pinnedOwnerSigningKey: owner.publicKeyRaw, nowUnixMs: nowMs)

        XCTAssertEqual(Set(live.map(\.id)), ["grant-a", "grant-b"])
    }

    /// A legacy singleton and a per-grant record describing the SAME grant
    /// (mixed-zone edge case) must project exactly once, not twice.
    func testDedupedLiveGrantsCollapsesSameGrantIdSeenUnderTwoRecordNames() throws {
        let grant = try makeGrant(id: "grant-shared", owner: owner)
        let legacyNamed = manualGrantRecord(grant, name: ApprovalConfig.legacyGrantRecordName)
        let perGrantNamed = manualGrantRecord(grant, name: ApprovalConfig.grantRecordName(grantId: grant.id))

        let live = ApprovalRecipientService.dedupedLiveGrants(
            from: [legacyNamed, perGrantNamed], pinnedOwnerSigningKey: owner.publicKeyRaw, nowUnixMs: nowMs)

        XCTAssertEqual(live.count, 1)
        XCTAssertEqual(live.first?.id, "grant-shared")
    }

    /// A legacy-only zone (today's shape: one grant under the singleton
    /// name) must still be recognized after this change.
    func testDedupedLiveGrantsRecognizesLegacySingletonAlone() throws {
        let grant = try makeGrant(id: "grant-legacy", owner: owner)
        let legacyNamed = manualGrantRecord(grant, name: ApprovalConfig.legacyGrantRecordName)

        let live = ApprovalRecipientService.dedupedLiveGrants(
            from: [legacyNamed], pinnedOwnerSigningKey: owner.publicKeyRaw, nowUnixMs: nowMs)

        XCTAssertEqual(live.map(\.id), ["grant-legacy"])
    }

    /// H1 regression: a bad-signature record sharing the SAME id as a good,
    /// legitimately signed grant must never evict it. `dedupedLiveGrants`
    /// verifies BEFORE inserting into the id→grant map, so a forged
    /// same-id record can never win the slot regardless of enumeration
    /// order — a compromised recipient device has write access to this
    /// zone, so this forgery is a real, expected threat, not a hypothetical.
    func testDedupedLiveGrantsSameIdCollisionKeepsTheVerifiableGrant() throws {
        let impostor = DeviceSigningIdentity.ephemeral()
        let good = try makeGrant(id: "grant-collide", owner: owner)
        var bad = good
        // Same id, same claimed owner pubkey, wrong signer — exactly what a
        // forged same-id record looks like (an owner-key mismatch alone
        // would trip the earlier `.ownerKeyUnpinned` check instead of
        // exercising the signature-verification path this test targets).
        bad.ownerSignature = try impostor.signature(for: bad.signingBody())
        // Bad record enumerated LAST — the exact order that used to evict
        // the good grant before verify-before-dedupe was fixed.
        let records = [manualGrantRecord(good, name: "record-good"),
                       manualGrantRecord(bad, name: "record-bad")]

        let live = ApprovalRecipientService.dedupedLiveGrants(
            from: records, pinnedOwnerSigningKey: owner.publicKeyRaw, nowUnixMs: nowMs)

        XCTAssertEqual(live.count, 1)
        XCTAssertEqual(live.first?.ownerSignature, good.ownerSignature)
    }

    /// A bad-signature grant under a DIFFERENT id must not hide a
    /// legitimate grant under another id either — distinct from the
    /// same-id collision above (no dedup collapse involved, just the
    /// verify filter).
    func testDedupedLiveGrantsDropsUnverifiableGrantAmongDifferentIds() throws {
        let impostor = DeviceSigningIdentity.ephemeral()
        let grantA = try makeGrant(id: "grant-a", owner: owner)
        let grantB = try makeGrant(id: "grant-b", owner: impostor) // not the pinned owner
        let records = [manualGrantRecord(grantA, name: ApprovalConfig.grantRecordName(grantId: grantA.id)),
                       manualGrantRecord(grantB, name: ApprovalConfig.grantRecordName(grantId: grantB.id))]

        let live = ApprovalRecipientService.dedupedLiveGrants(
            from: records, pinnedOwnerSigningKey: owner.publicKeyRaw, nowUnixMs: nowMs)

        XCTAssertEqual(live.map(\.id), ["grant-a"])
    }

    /// Non-grant / undecodable records in the same zone (shared-field blobs,
    /// corrupt records) are silently skipped, never crash the reduction.
    func testDedupedLiveGrantsIgnoresUndecodableRecords() throws {
        let grantA = try makeGrant(id: "grant-a", owner: owner)
        let garbage = CKRecord(recordType: ApprovalConfig.sharedFieldRecordType,
                               recordID: CKRecord.ID(recordName: "not-a-grant", zoneID: zoneID))
        let records = [manualGrantRecord(grantA, name: ApprovalConfig.grantRecordName(grantId: grantA.id)),
                       garbage]

        let live = ApprovalRecipientService.dedupedLiveGrants(
            from: records, pinnedOwnerSigningKey: owner.publicKeyRaw, nowUnixMs: nowMs)

        XCTAssertEqual(live.map(\.id), ["grant-a"])
    }

    /// Pre-fingerprint (no pin yet): grants are still returned for
    /// display/ceremony purposes — verification only enforces a PINNED
    /// key mismatch, it doesn't require one to exist yet.
    func testDedupedLiveGrantsAllowsDisplayBeforeOwnerKeyIsPinned() throws {
        let grantA = try makeGrant(id: "grant-a", owner: owner)
        let live = ApprovalRecipientService.dedupedLiveGrants(
            from: [manualGrantRecord(grantA, name: ApprovalConfig.grantRecordName(grantId: grantA.id))],
            pinnedOwnerSigningKey: nil, nowUnixMs: nowMs)
        XCTAssertEqual(live.map(\.id), ["grant-a"])
    }
}
