import CryptoKit
import XCTest
@testable import Vaultify

/// The item-edit republish (`republishDisplayEnvelope` / `republishSharedValues`)
/// must seal a single-device grant per device, like `publishGrant` does, and
/// must keep the grant's passkeys in the display envelope. Both used to seal
/// to the participant key and drop passkeys, so one edit blanked every shared
/// value and passkey on a single-device recipient.
final class SharingRepublishSealTargetTests: XCTestCase {

    private func entry(_ device: DeviceHPKEIdentity, at ms: Int64 = 0) -> DeviceHPKEDirectoryEntry {
        DeviceHPKEDirectoryEntry(deviceKeyID: device.deviceKeyID, hpkePublicKey: device.publicKeyRaw,
                                 label: "device", addedAtUnixMs: ms)
    }

    private func grant(capabilities: [String: FieldCapability] = ["pw": .value(.shared)],
                       participant: ParticipantIdentity = .generate(),
                       bound: [DeviceHPKEIdentity] = []) -> AccessGrant {
        AccessGrant(id: "g1", itemId: "item", recipientId: "r1",
                    participantPubKey: participant.publicKeyRaw,
                    pinnedDeviceSigningKeys: [Data(repeating: 8, count: 65)],
                    capabilities: capabilities, epoch: 1,
                    createdAtUnixMs: 1_000, expiresAtUnixMs: nil,
                    ownerSigningPubKey: Data(repeating: 9, count: 65),
                    ownerSignature: Data([1]),
                    deviceScope: bound.isEmpty ? .multi : .single,
                    allowedDeviceKeyBindings: bound.map(\.binding))
    }

    // MARK: resolve (binding + key-hash match)

    func testDirectoryBindingMatchesTheRecipientsOwnBinding() {
        // The recipient accepts a v2 blob only when its live key hashes to the
        // bound hash; the owner-side binding must be that exact value.
        let device = DeviceHPKEIdentity.ephemeral()
        XCTAssertEqual(entry(device).binding, device.binding)
        XCTAssertEqual(entry(device).binding.hpkePublicKeyHash,
                       Data(SHA256.hash(data: device.publicKeyRaw)))
    }

    func testMultiDeviceGrantSealsToTheParticipantKey() {
        let participant = ParticipantIdentity.generate()
        let target = GrantSealTarget.resolve(
            grant: grant(participant: participant),
            directory: [entry(.ephemeral())])
        XCTAssertEqual(target, .participant(participant.publicKeyRaw))
    }

    func testSingleDeviceGrantSealsOnlyToBoundDirectoryEntries() {
        let bound = DeviceHPKEIdentity.ephemeral()
        let other = DeviceHPKEIdentity.ephemeral()
        let target = GrantSealTarget.resolve(
            grant: grant(bound: [bound]),
            directory: [entry(other), entry(bound)])
        XCTAssertEqual(target, .devices([entry(bound)]))
    }

    func testSwappedKeyUnderTheBoundDeviceIdIsNeverSealedTo() {
        // INV-12: same deviceKeyID, different public key.
        let bound = DeviceHPKEIdentity.ephemeral()
        var swapped = entry(bound)
        swapped.hpkePublicKey = DeviceHPKEIdentity.ephemeral().publicKeyRaw
        XCTAssertNil(GrantSealTarget.resolve(grant: grant(bound: [bound]), directory: [swapped]))
    }

    func testBoundDeviceGoneFromDirectoryNeverWidensToParticipant() {
        // INV-04: no bound device left means no target, never the synced key.
        let bound = DeviceHPKEIdentity.ephemeral()
        XCTAssertNil(GrantSealTarget.resolve(grant: grant(bound: [bound]), directory: []))
        XCTAssertNil(GrantSealTarget.resolve(grant: grant(bound: [bound]),
                                             directory: [entry(.ephemeral())]))
    }

    // MARK: Sealed contents

    func testPerDeviceFieldOpensOnTheBoundDeviceOnly() throws {
        let bound = DeviceHPKEIdentity.ephemeral()
        let participant = ParticipantIdentity.generate()
        let g = grant(participant: participant, bound: [bound])
        let target = try XCTUnwrap(GrantSealTarget.resolve(grant: g, directory: [entry(bound)]))
        let sealed = try target.sealField(Data("hunter2".utf8), grantId: g.id, fieldId: "pw")

        let blob = try PerDeviceSealedBlob.decode(sealed)
        let envelope = try XCTUnwrap(blob.envelope(forDeviceKeyID: bound.deviceKeyID))
        XCTAssertEqual(try ApprovalSeal.openSharedFieldForDevice(
            envelope, deviceIdentity: bound, grantId: g.id, fieldId: "pw"), Data("hunter2".utf8))
        XCTAssertNil(blob.envelope(forDeviceKeyID: DeviceHPKEIdentity.ephemeral().deviceKeyID))
        // The synced participant key can't open a v2 blob (INV-04).
        XCTAssertThrowsError(try ApprovalSeal.openSharedField(
            sealed, participantPrivateKey: participant.privateKey, grantId: g.id, fieldId: "pw"))
    }

    func testParticipantFieldOpensWithTheParticipantKey() throws {
        let participant = ParticipantIdentity.generate()
        let g = grant(participant: participant)
        let target = try XCTUnwrap(GrantSealTarget.resolve(grant: g, directory: []))
        let sealed = try target.sealField(Data("v".utf8), grantId: g.id, fieldId: "pw")
        XCTAssertEqual(try ApprovalSeal.openSharedField(
            sealed, participantPrivateKey: participant.privateKey, grantId: g.id, fieldId: "pw"),
                       Data("v".utf8))
    }

    func testPerDeviceDisplayEnvelopeOpensOnTheBoundDevice() throws {
        let bound = DeviceHPKEIdentity.ephemeral()
        let g = grant(bound: [bound])
        let target = try XCTUnwrap(GrantSealTarget.resolve(grant: g, directory: [entry(bound)]))
        let display = SharedDisplayEnvelope(title: "Bank", websiteHost: "bank.example",
                                            updatedAtUnixMs: 5_000, revision: 5)
        let blob = try PerDeviceSealedBlob.decode(target.sealDisplay(display, grantId: g.id))
        let envelope = try XCTUnwrap(blob.envelope(forDeviceKeyID: bound.deviceKeyID))
        XCTAssertEqual(try SharedDisplayEnvelope.openForDevice(envelope, deviceIdentity: bound,
                                                               grantId: g.id), display)
    }

    // MARK: Republished display envelope contents

    private func passkey(_ fill: UInt8) -> PasskeyInfo {
        PasskeyInfo(relyingParty: "rp\(fill).example", userName: "u\(fill)",
                    userHandle: Data([fill]), credentialID: Data([fill, fill]),
                    createdAt: Date(timeIntervalSince1970: 0), flags: 0x1D)
    }

    private func slot(_ passkey: PasskeyInfo) -> String {
        PasskeySlot.slotId(credentialID: passkey.credentialID)
    }

    func testRepublishedEnvelopeKeepsEveryGrantedPasskey() throws {
        let asked = passkey(1), handedOver = passkey(2), off = passkey(3), unshared = passkey(4)
        let g = grant(capabilities: [slot(asked): .passkey(.askEachTime),
                                     slot(handedOver): .passkey(.shared),
                                     slot(off): .passkey(.none)])
        let display = try XCTUnwrap(ApprovalShareService.republishedDisplayEnvelope(
            grant: g, title: "Bank", websiteHost: nil, displayFields: [:], category: "login",
            ownerPasskeys: [asked, handedOver, off, unshared], nowUnixMs: 9_000))
        let metas = try XCTUnwrap(display.passkeys)
        XCTAssertEqual(Set(metas.map(\.slotId)), [slot(asked), slot(handedOver)])
        let meta = try XCTUnwrap(metas.first { $0.slotId == slot(handedOver) })
        XCTAssertEqual(meta.relyingParty, handedOver.relyingParty)
        XCTAssertEqual(meta.userName, handedOver.userName)
        XCTAssertEqual(meta.userHandle, handedOver.userHandle)
        XCTAssertEqual(meta.credentialID, handedOver.credentialID)
        XCTAssertEqual(meta.flags, handedOver.flags)
    }

    func testRepublishedPasskeyMetaMatchesWhatTheSharePublished() throws {
        // The republish builds from `PasskeyInfo`, the publish from the
        // decrypted `PasskeySecret`; the recipient must see the same meta.
        let info = passkey(5)
        let secret = PasskeySecret(relyingParty: info.relyingParty, userName: info.userName,
                                   userHandle: info.userHandle, credentialID: info.credentialID,
                                   privateKeyRaw: Data([7]), counter: 0,
                                   createdAt: info.createdAt, flags: info.flags)
        let caps: [String: FieldCapability] = [slot(info): .passkey(.shared)]
        let published = SharedGrantComposer.passkeyArtifacts(
            secretsBySlot: [(slot(info), secret)], capabilities: caps).display
        XCTAssertEqual(SharedGrantComposer.displayPasskeys(capabilities: caps, passkeys: [info]),
                       published)
    }

    func testRepublishedEnvelopeRefusesWhenAGrantedPasskeyIsMissing() {
        // Resealing without it would hide that passkey on the recipient.
        let granted = passkey(1)
        let g = grant(capabilities: [slot(granted): .passkey(.askEachTime)])
        XCTAssertNil(ApprovalShareService.republishedDisplayEnvelope(
            grant: g, title: "Bank", websiteHost: nil, displayFields: [:], category: nil,
            ownerPasskeys: [passkey(2)], nowUnixMs: 9_000))
    }

    func testRepublishedEnvelopeCarriesOnlyGrantedFieldsAndTheItemsMetadata() throws {
        let meta = { (label: String) in SharedDisplayEnvelope.FieldMeta(label: label, kind: "password") }
        let g = grant(capabilities: ["pw": .value(.shared), "user": .value(.none),
                                     "otp": .totp(.askEachTime), "seed": .totp(.alwaysShowCode)])
        let display = try XCTUnwrap(ApprovalShareService.republishedDisplayEnvelope(
            grant: g, title: "Bank", websiteHost: "bank.example",
            displayFields: ["pw": meta("Password"), "user": meta("Username"),
                            "otp": meta("Code"), "seed": meta("2FA"), "note": meta("Notes")],
            category: "login", ownerPasskeys: [], nowUnixMs: 9_500))
        XCTAssertEqual(Set(try XCTUnwrap(display.fields).keys), ["pw", "otp", "seed"])
        XCTAssertEqual(display.title, "Bank")
        XCTAssertEqual(display.websiteHost, "bank.example")
        XCTAssertEqual(display.category, "login")
        XCTAssertEqual(display.revision, 9)
        XCTAssertEqual(display.updatedAtUnixMs, 9_500)
        XCTAssertNil(display.passkeys, "no granted passkey → no passkey section")
    }

    func testGrantedPasskeySlotsSkipsNoneAndFields() {
        let caps: [String: FieldCapability] = ["passkey::aa": .passkey(.askEachTime),
                                               "passkey::bb": .passkey(.none),
                                               "pw": .value(.shared)]
        XCTAssertEqual(SharedGrantComposer.grantedPasskeySlots(caps), ["passkey::aa"])
    }
}
