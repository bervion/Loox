import CryptoKit
import Foundation

/// Which key a grant's ciphertext is sealed to: the recipient's participant
/// key (multi-device grant), or one envelope per approved device inside a
/// `PerDeviceSealedBlob` (v2 single-device grant). The recipient opens a v2
/// grant's blobs with its own device key only and never consults the synced
/// participant key (INV-04), so a v2 blob sealed any other way reads as
/// "nothing shared" with no error anywhere.
///
/// Both owner write paths pick the key here: `publishGrant` and the
/// item-edit republish. The republish used to seal to the participant key
/// unconditionally, which blanked every shared value of a single-device
/// share after any edit.
nonisolated enum GrantSealTarget: Equatable {
    case participant(Data)
    case devices([DeviceHPKEDirectoryEntry])

    /// Pure (unit-tested). The directory entries the grant's SIGNED bindings
    /// name: same device id and `SHA256(hpkePublicKey) == hpkePublicKeyHash`,
    /// so a key swapped under the same id is never sealed to (INV-12). nil
    /// when the grant binds devices but none of them is in `directory` any
    /// more: widening to the participant key would void the single-device
    /// promise, and sealing to nobody would silently blank every value.
    static func resolve(grant: AccessGrant,
                        directory: [DeviceHPKEDirectoryEntry]) -> GrantSealTarget? {
        guard !grant.allowedDeviceKeyBindings.isEmpty else {
            return .participant(grant.participantPubKey)
        }
        let bound = directory.filter { grant.allowedDeviceKeyBindings.contains($0.binding) }
        return bound.isEmpty ? nil : .devices(bound)
    }

    func sealDisplay(_ display: SharedDisplayEnvelope, grantId: String) throws -> Data {
        switch self {
        case .participant(let key):
            return try display.sealed(toParticipantPubKey: key, grantId: grantId)
        case .devices(let devices):
            return try Self.perDevice(devices) {
                try display.sealedForDevice(toDevicePubKey: $0.hpkePublicKey,
                                            deviceKeyID: $0.deviceKeyID, grantId: grantId)
            }
        }
    }

    func sealField(_ plaintext: Data, grantId: String, fieldId: String) throws -> Data {
        switch self {
        case .participant(let key):
            return try ApprovalSeal.sealSharedField(plaintext, toParticipantPubKey: key,
                                                    grantId: grantId, fieldId: fieldId)
        case .devices(let devices):
            return try Self.perDevice(devices) {
                try ApprovalSeal.sealSharedFieldForDevice(
                    plaintext, toDevicePubKey: $0.hpkePublicKey, deviceKeyID: $0.deviceKeyID,
                    grantId: grantId, fieldId: fieldId)
            }
        }
    }

    private static func perDevice(_ devices: [DeviceHPKEDirectoryEntry],
                                  seal: (DeviceHPKEDirectoryEntry) throws -> Data) throws -> Data {
        var envelopes: [String: Data] = [:]
        for device in devices {
            envelopes[device.deviceKeyID.hexString] = try seal(device)
        }
        return try PerDeviceSealedBlob(envelopes: envelopes).encoded()
    }
}

extension DeviceHPKEDirectoryEntry {
    /// The grant binding naming this entry's device AND its current key.
    nonisolated var binding: DeviceKeyBinding {
        DeviceKeyBinding(deviceKeyID: deviceKeyID,
                         hpkePublicKeyHash: Data(SHA256.hash(data: hpkePublicKey)))
    }
}
