import CryptoKit
import XCTest
@testable import Vaultify

/// P03a: per-device HPKE identity, key/id binding, and the multi-device
/// profile merge rules (a republish from one device must never erase the
/// others from the singleton profile record).
final class DeviceHPKEIdentityTests: XCTestCase {

    func testBindingHashesCurrentPublicKeyAndKeepsStableID() {
        let identity = DeviceHPKEIdentity.ephemeral()
        let binding = identity.binding
        XCTAssertEqual(binding.deviceKeyID.count, 32)
        XCTAssertEqual(binding.hpkePublicKeyHash,
                       Data(SHA256.hash(data: identity.publicKeyRaw)))
        // The id names the DEVICE, not the key — it must not be derivable
        // from the public key (otherwise key swap under same id is invisible).
        XCTAssertNotEqual(binding.deviceKeyID, binding.hpkePublicKeyHash)
    }

    func testDirectoryCodecRoundTripAndLenientDecode() throws {
        let entry = DeviceHPKEDirectoryEntry(
            deviceKeyID: Data(repeating: 1, count: 32),
            hpkePublicKey: Data(repeating: 2, count: 32),
            label: "iPhone", addedAtUnixMs: 1_000)
        let data = try DeviceHPKEDirectoryEntry.encodeDirectory([entry])
        XCTAssertEqual(DeviceHPKEDirectoryEntry.decodeDirectory(data), [entry])
        // Legacy profiles have no directory field; garbage must not throw.
        XCTAssertEqual(DeviceHPKEDirectoryEntry.decodeDirectory(nil), [])
        XCTAssertEqual(DeviceHPKEDirectoryEntry.decodeDirectory(Data("junk".utf8)), [])
    }

    func testDirectoryMergeUpsertsByDeviceAndKeepsSiblings() {
        let deviceA = DeviceHPKEDirectoryEntry(deviceKeyID: Data(repeating: 0xA, count: 32),
                                               hpkePublicKey: Data([1]), label: "A",
                                               addedAtUnixMs: 100)
        let deviceB = DeviceHPKEDirectoryEntry(deviceKeyID: Data(repeating: 0xB, count: 32),
                                               hpkePublicKey: Data([2]), label: "B",
                                               addedAtUnixMs: 200)
        // Device B republishes with a refreshed label — A must survive.
        var refreshedB = deviceB
        refreshedB.label = "B renamed"
        let merged = ParticipantProfileMerge.directory(existing: [deviceA, deviceB],
                                                       upserting: refreshedB)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first?.label, "A")
        XCTAssertEqual(merged.last?.label, "B renamed")
    }

    func testSigningKeyMergeIsAUnion() {
        let k1 = Data([1]), k2 = Data([2])
        XCTAssertEqual(ParticipantProfileMerge.signingKeys(existing: [k1], adding: k2), [k1, k2])
        XCTAssertEqual(ParticipantProfileMerge.signingKeys(existing: [k1, k2], adding: k1), [k1, k2])
    }
}
