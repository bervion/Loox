import CryptoKit
import XCTest
@testable import Vaultify

/// Grant wire v2 (P03b): version selection, round-trips, strict canonical
/// ordering, version/feature agreement, and per-device sealing including the
/// INV-04 "legacy synced key can never open v2 blobs" property.
final class GrantWireV2Tests: XCTestCase {

    private func makeGrant(capabilities: [String: FieldCapability],
                           deviceScope: DeviceScope = .multi,
                           bindings: [DeviceKeyBinding] = []) -> AccessGrant {
        AccessGrant(id: "g1", itemId: "item", recipientId: "r1",
                    participantPubKey: Data(repeating: 7, count: 32),
                    pinnedDeviceSigningKeys: [Data(repeating: 8, count: 65)],
                    capabilities: capabilities, epoch: 1,
                    createdAtUnixMs: 1_000, expiresAtUnixMs: nil,
                    ownerSigningPubKey: Data(repeating: 9, count: 65),
                    ownerSignature: Data([1, 2, 3]),
                    deviceScope: deviceScope, allowedDeviceKeyBindings: bindings)
    }

    private func binding(_ fill: UInt8) -> DeviceKeyBinding {
        DeviceKeyBinding(deviceKeyID: Data(repeating: fill, count: 32),
                         hpkePublicKeyHash: Data(repeating: fill &+ 1, count: 32))
    }

    // MARK: Wire version selection + round-trips

    func testPlainGrantStaysOnWireV1() throws {
        let grant = makeGrant(capabilities: ["f": .value(.shared)])
        XCTAssertFalse(grant.requiresWireV2)
        XCTAssertEqual(grant.signingBody().first, ApprovalWire.version)
        XCTAssertEqual(try AccessGrant.decode(grant.encoded()), grant)
    }

    func testSingleDeviceGrantRoundTripsOnWireV2() throws {
        let grant = makeGrant(capabilities: ["f": .value(.shared)],
                              deviceScope: .single,
                              bindings: [binding(0xB), binding(0xA)]) // init sorts
        XCTAssertTrue(grant.requiresWireV2)
        XCTAssertEqual(grant.signingBody().first, ApprovalWire.versionV2)
        let decoded = try AccessGrant.decode(grant.encoded())
        XCTAssertEqual(decoded, grant)
        XCTAssertEqual(decoded.allowedDeviceKeyBindings.map(\.deviceKeyID),
                       [Data(repeating: 0xA, count: 32), Data(repeating: 0xB, count: 32)])
    }

    func testPasskeyAndSharedTOTPCapabilitiesForceWireV2() throws {
        for caps: [String: FieldCapability] in [["p": .passkey(.askEachTime)],
                                                ["t": .totp(.shared)]] {
            let grant = makeGrant(capabilities: caps)
            XCTAssertTrue(grant.requiresWireV2)
            XCTAssertEqual(grant.signingBody().first, ApprovalWire.versionV2)
            XCTAssertEqual(try AccessGrant.decode(grant.encoded()), grant)
        }
    }

    // MARK: Canonical strictness (INV-12)

    func testDuplicateDeviceBindingRejectedAtDecode() {
        let dup = binding(0xC)
        let grant = makeGrant(capabilities: ["f": .value(.shared)],
                              deviceScope: .single, bindings: [dup, dup])
        XCTAssertThrowsError(try AccessGrant.decode(grant.encoded()))
    }

    func testVersionByteFlipRejected() {
        // A v2 payload re-labelled v1 (and vice versa) must never decode:
        // either the layout mismatch trips, or the version/feature agreement
        // guard does.
        let v2 = makeGrant(capabilities: ["f": .value(.shared)],
                           deviceScope: .single, bindings: [binding(0xD)])
        var relabelled = v2.encoded()
        relabelled[relabelled.startIndex] = ApprovalWire.version
        XCTAssertThrowsError(try AccessGrant.decode(relabelled))

        let v1 = makeGrant(capabilities: ["f": .value(.shared)])
        var upLabelled = v1.encoded()
        upLabelled[upLabelled.startIndex] = ApprovalWire.versionV2
        XCTAssertThrowsError(try AccessGrant.decode(upLabelled))
    }

    func testTrailingBytesRejected() {
        let grant = makeGrant(capabilities: ["f": .value(.shared)],
                              deviceScope: .single, bindings: [binding(0xE)])
        XCTAssertThrowsError(try AccessGrant.decode(grant.encoded() + Data([0])))
    }

    // MARK: Per-device sealing (INV-04)

    func testPerDeviceSealOpensOnlyOnTheBoundDevice() throws {
        let deviceA = DeviceHPKEIdentity.ephemeral()
        let deviceB = DeviceHPKEIdentity.ephemeral()
        let secret = Data("hunter2".utf8)
        let envelope = try ApprovalSeal.sealSharedFieldForDevice(
            secret, toDevicePubKey: deviceA.publicKeyRaw,
            deviceKeyID: deviceA.deviceKeyID, grantId: "g1", fieldId: "f1")

        XCTAssertEqual(try ApprovalSeal.openSharedFieldForDevice(
            envelope, deviceIdentity: deviceA, grantId: "g1", fieldId: "f1"), secret)
        XCTAssertThrowsError(try ApprovalSeal.openSharedFieldForDevice(
            envelope, deviceIdentity: deviceB, grantId: "g1", fieldId: "f1"))
        // Legacy synced participant identity must NEVER open v2 envelopes,
        // even given the same envelope bytes (INV-04): different info domain.
        let legacy = ParticipantIdentity.generate()
        XCTAssertThrowsError(try ApprovalSeal.openSharedField(
            envelope, participantPrivateKey: legacy.privateKey,
            grantId: "g1", fieldId: "f1"))
    }

    func testPerDeviceBlobPicksOwnEntryAndMissingDeviceGetsNothing() throws {
        let deviceA = DeviceHPKEIdentity.ephemeral()
        let outsider = DeviceHPKEIdentity.ephemeral()
        let envelope = try ApprovalSeal.sealSharedFieldForDevice(
            Data("s".utf8), toDevicePubKey: deviceA.publicKeyRaw,
            deviceKeyID: deviceA.deviceKeyID, grantId: "g", fieldId: "f")
        let blob = PerDeviceSealedBlob(envelopes: [deviceA.deviceKeyID.hexString: envelope])
        let encoded = try blob.encoded()
        let decoded = try PerDeviceSealedBlob.decode(encoded)
        XCTAssertNotNil(decoded.envelope(forDeviceKeyID: deviceA.deviceKeyID))
        XCTAssertNil(decoded.envelope(forDeviceKeyID: outsider.deviceKeyID))
    }
}
