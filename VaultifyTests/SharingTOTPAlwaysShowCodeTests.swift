import CloudKit
import XCTest
@testable import Vaultify

/// "Always show code" (`TOTPFieldCapability.alwaysShowCode`, owner decision
/// 261028): the recipient's device holds the seed so codes work offline, but
/// Loox never lets it out (no Reveal, no raw Copy, no search, no AutoFill
/// cache) and drops it once the grant stops carrying the mode.
@MainActor
final class SharingTOTPAlwaysShowCodeTests: XCTestCase {

    private let nowMs: Int64 = 1_783_256_400_000
    private let seed = "JBSWY3DPEHPK3PXP"
    private let origin = SharedOrigin(zoneName: "apz-abc", ownerName: "_owner1",
                                      grantId: "grant-1")

    private func makeGrant(capabilities: [String: FieldCapability]) throws -> AccessGrant {
        let owner = DeviceSigningIdentity.ephemeral()
        var grant = AccessGrant(
            id: "grant-1", itemId: "item-1", recipientId: "rcpt-1",
            participantPubKey: Data(repeating: 1, count: 32),
            pinnedDeviceSigningKeys: [Data(repeating: 2, count: 64)],
            capabilities: capabilities, epoch: 1,
            createdAtUnixMs: nowMs, expiresAtUnixMs: nil,
            ownerSigningPubKey: owner.publicKeyRaw, ownerSignature: Data())
        grant.ownerSignature = try owner.signature(for: grant.signingBody())
        return grant
    }

    private func ownerItem(totpProtected: Bool = true) -> VaultItem {
        VaultItem(id: "item-1", category: .login, title: "Acme", folderId: nil, fields: [
            DynamicField(id: "f-pass", label: "Password", kind: .password, value: "pw"),
            DynamicField(id: "f-totp", label: "One-time Code", kind: .totp, value: seed,
                         protected: totpProtected),
        ])
    }

    // MARK: Capability model + wire

    func testModeShipsTheSealedSeedWithoutTheHandOverGate() {
        let mode = FieldCapability.totp(.alwaysShowCode)
        XCTAssertTrue(mode.isSharedValue, "the seed rides the sealed shared-field path")
        XCTAssertFalse(mode.isHandOver, "no irreversible hand-over confirmation")
        XCTAssertFalse(mode.isAskEachTimeTOTP, "never answers an ask-each-time request")
        XCTAssertTrue(mode.grantsAnything)
        XCTAssertTrue(mode.requiresWireV2)
    }

    func testGrantRoundTripsOnWireV2Only() throws {
        let grant = try makeGrant(capabilities: ["f-totp": .totp(.alwaysShowCode)])
        XCTAssertEqual(grant.signingBody().first, ApprovalWire.versionV2)
        XCTAssertEqual(try AccessGrant.decode(grant.encoded()), grant)

        var relabelled = grant.encoded()
        relabelled[relabelled.startIndex] = ApprovalWire.version
        XCTAssertThrowsError(try AccessGrant.decode(relabelled), "a v1 grant can't carry the mode")
    }

    /// What an app one version behind sees: a TOTP mode byte it does not
    /// know. The whole grant must fail to decode (fail closed), never decode
    /// with the field silently downgraded.
    func testUnknownTOTPModeFailsTheWholeGrantClosed() throws {
        // Fixed key bytes (no fresh signing identity), so the two encodings
        // differ in the mode byte alone.
        func encoded(_ mode: TOTPFieldCapability) -> Data {
            AccessGrant(id: "g1", itemId: "item", recipientId: "r1",
                        participantPubKey: Data(repeating: 7, count: 32),
                        pinnedDeviceSigningKeys: [Data(repeating: 8, count: 65)],
                        capabilities: ["f-totp": .totp(mode)], epoch: 1,
                        createdAtUnixMs: 1_000, expiresAtUnixMs: nil,
                        ownerSigningPubKey: Data(repeating: 9, count: 65),
                        ownerSignature: Data([1, 2, 3])).encoded()
        }
        let known = encoded(.alwaysShowCode)
        let other = encoded(.shared)
        XCTAssertEqual(known.count, other.count)
        let modeIndex = try XCTUnwrap(zip(known.indices, zip(known, other))
            .first { $0.1.0 != $0.1.1 }?.0)
        XCTAssertEqual(known[modeIndex], TOTPFieldCapability.alwaysShowCode.rawValue)
        var future = known
        future[modeIndex] = 0x7F
        XCTAssertThrowsError(try AccessGrant.decode(future))
    }

    // MARK: Owner side

    func testComposerSealsTheSeedForTheMode() {
        let values = SharedGrantComposer.sharedFieldValues(
            item: ownerItem(), capabilities: ["f-totp": .totp(.alwaysShowCode)])
        XCTAssertEqual(values["f-totp"], Data(seed.utf8))
        XCTAssertNil(values["f-pass"], "an off field never ships")
    }

    func testPickingTheModeAppliesWithoutConfirmation() {
        var draft = ShareCapabilityDraft(published: ["f-totp": .totp(.askEachTime)])
        draft.select(.totp(.alwaysShowCode), for: "f-totp")
        XCTAssertNil(draft.pendingHandOver)
        XCTAssertEqual(draft.capability(for: "f-totp"), .totp(.alwaysShowCode))
        XCTAssertTrue(draft.hasChanges)
    }

    /// Changing away from the mode is what makes the recipient's copy go:
    /// the next grant no longer seals the seed, so their projection rebuilds
    /// without it.
    func testMovingAwayFromTheModeStopsShippingTheSeed() {
        for next: TOTPFieldCapability in [.none, .askEachTime] {
            let values = SharedGrantComposer.sharedFieldValues(
                item: ownerItem(), capabilities: ["f-totp": .totp(next)])
            XCTAssertNil(values["f-totp"], "\(next) must not ship the seed")
        }
    }

    // MARK: Recipient side

    func testSeedProjectsAsAProtectedCodeFieldWhateverTheEnvelopeSays() throws {
        let grant = try makeGrant(capabilities: ["f-totp": .totp(.alwaysShowCode)])
        // A wrong kind and an unprotected policy in the (unsigned) envelope.
        var display = SharedDisplayEnvelope(title: "Acme", websiteHost: nil,
                                            updatedAtUnixMs: nowMs, revision: 1)
        display.fields = ["f-totp": .init(label: "Code", kind: FieldKind.password.rawValue,
                                          protected: false)]
        for envelope in [display, nil] {
            let item = SharedItemsProjection.buildItem(
                origin: origin, grant: grant, display: envelope,
                values: ["f-totp": Data(seed.utf8)])
            let field = try XCTUnwrap(item.fields.first { $0.id == "f-totp" })
            XCTAssertEqual(field.kind, .totp, "renders as a live code, no Reveal")
            XCTAssertTrue(field.protected)
            XCTAssertFalse(item.searchText.contains(seed.lowercased()),
                           "the secret must not be searchable")
        }
    }

    func testCodeOnlySeedNeverReachesTheAutoFillCache() throws {
        let values = ["f-totp": Data(seed.utf8)]
        let codeOnly = try makeGrant(capabilities: ["f-totp": .totp(.alwaysShowCode)])
        let codeOnlyEntry = SharedItemsProjection.cacheEntry(
            item: SharedItemsProjection.buildItem(origin: origin, grant: codeOnly,
                                                  display: nil, values: values),
            grant: codeOnly, passkeys: nil)
        let entry = try XCTUnwrap(codeOnlyEntry, "the item itself still reaches AutoFill")
        XCTAssertNil(entry.sharedTOTPSecret)
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(entry), encoding: .utf8))
        XCTAssertFalse(encoded.contains(seed), "the seed must not be anywhere in the cached entry")

        // Control: a handed-over seed is cached, as before.
        let handedOver = try makeGrant(capabilities: ["f-totp": .totp(.shared)])
        let handedOverEntry = SharedItemsProjection.cacheEntry(
            item: SharedItemsProjection.buildItem(origin: origin, grant: handedOver,
                                                  display: nil, values: values),
            grant: handedOver, passkeys: nil)
        XCTAssertEqual(handedOverEntry?.sharedTOTPSecret, seed)
    }

    func testReadOnlyCopyNeverFallsBackToTheSecret() {
        let code = DetailFieldRow.totpCopyValue(storedValue: seed, readOnly: true)
        XCTAssertEqual(code.count, 6)
        XCTAssertTrue(code.allSatisfy(\.isNumber))
        XCTAssertEqual(DetailFieldRow.totpCopyValue(storedValue: "not base32 !", readOnly: true), "")
        // The owner's own item keeps its fallback (copy a malformed secret out to fix it).
        XCTAssertEqual(DetailFieldRow.totpCopyValue(storedValue: "not base32 !", readOnly: false),
                       "not base32 !")
    }

    // MARK: Purge on revoke / change

    /// An item edit re-seals item-field values and deletes the grant's old
    /// ones, including a field the owner removed. Passkey hand-over blobs
    /// share the record type and must survive that cleanup.
    func testItemEditCleanupTargetsItemFieldBlobsOnly() {
        let zone = CKRecordZone.ID(zoneName: "apz-abc")
        func blob(_ fieldId: String) -> CKRecord {
            ApprovalRecordMapping.sharedFieldRecord(sealedBlob: Data([1]), grantId: "grant-1",
                                                    fieldId: fieldId, zoneID: zone)
        }
        XCTAssertTrue(ApprovalShareService.isItemFieldBlob(blob("f-totp")))
        XCTAssertFalse(ApprovalShareService.isItemFieldBlob(
            blob(PasskeySlot.slotId(credentialID: Data([0xAB, 0xCD])))))
        XCTAssertFalse(ApprovalShareService.isItemFieldBlob(
            CKRecord(recordType: "SomethingElse", recordID: CKRecord.ID(recordName: "x", zoneID: zone))))
    }

    func testZoneWithoutALiveGrantDropsItsItems() {
        XCTAssertFalse(SharedItemsProjection.keepsZoneItems(
            afterGrantFetchError: ApprovalRecipientService.Failure.grantMissing),
            "per-item Stop sharing leaves the zone but no grant: purge")
        XCTAssertFalse(SharedItemsProjection.keepsZoneItems(
            afterGrantFetchError: CKError(.zoneNotFound)))
        XCTAssertFalse(SharedItemsProjection.keepsZoneItems(
            afterGrantFetchError: CKError(.userDeletedZone)))
        // Transient: keep what was shown.
        XCTAssertTrue(SharedItemsProjection.keepsZoneItems(
            afterGrantFetchError: CKError(.networkUnavailable)))
        XCTAssertTrue(SharedItemsProjection.keepsZoneItems(
            afterGrantFetchError: CKError(.requestRateLimited)))
    }

    func testOpeningAnItemWhoseGrantIsGoneRefreshesTheProjection() {
        typealias Live = Result<(id: String, epoch: UInt32), any Error>
        // The gate itself stays fail-closed; the refresh does the purging.
        XCTAssertEqual(SharedAccessAuthorizer.outcome(
            expectedGrantId: "grant-1", expectedEpoch: 1,
            live: Live.failure(ApprovalRecipientService.Failure.grantMissing)), .unavailable)
        XCTAssertTrue(SharedAccessAuthorizer.projectionIsStale(
            Live.failure(ApprovalRecipientService.Failure.grantMissing)))
        XCTAssertTrue(SharedAccessAuthorizer.projectionIsStale(Live.success(("grant-2", 1))))
        XCTAssertFalse(SharedAccessAuthorizer.projectionIsStale(
            Live.failure(CKError(.networkFailure))))
        XCTAssertFalse(SharedAccessAuthorizer.projectionIsStale(Live.failure(CancellationError())))
    }
}
