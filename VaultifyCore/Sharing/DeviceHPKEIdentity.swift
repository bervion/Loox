import CryptoKit
import Foundation

/// Per-device HPKE identity: each device holds its OWN Curve25519
/// key-agreement keypair in the LOCAL keychain — the private key never
/// syncs anywhere (that non-syncing property is exactly what makes v2
/// single-device grants meaningful, INV-04/05). The legacy synced
/// `ParticipantIdentity` remains solely to decrypt v1 grants.
nonisolated struct DeviceHPKEIdentity: Sendable {
    private let privateKey: Curve25519.KeyAgreement.PrivateKey
    /// Stable, random 32-byte id minted once per device. Deliberately NOT a
    /// hash of the public key: the id names the DEVICE, the binding's
    /// `hpkePublicKeyHash` names the KEY — swapping the key under the same
    /// id must be detectable (and rejected) by grant verifiers (INV-12 test:
    /// "same deviceKeyID with different pubkey → reject").
    let deviceKeyID: Data

    static let keyKeychainAccount = "approval_device_hpke_key_v1"
    static let idKeychainAccount = "approval_device_hpke_key_id_v1"

    enum Failure: Error { case corruptKeyMaterial }

    var publicKeyRaw: Data { privateKey.publicKey.rawRepresentation }
    var publicKeyHash: Data { Data(SHA256.hash(data: publicKeyRaw)) }
    var binding: DeviceKeyBinding {
        DeviceKeyBinding(deviceKeyID: deviceKeyID, hpkePublicKeyHash: publicKeyHash)
    }
    /// For HPKE open (P03b) — same agreement-key type ApprovalCrypto uses.
    var agreementPrivateKey: Curve25519.KeyAgreement.PrivateKey { privateKey }

    /// Loads the existing identity or creates one on first use. Key and id
    /// are a PAIR: exactly one present means corrupted state — throw instead
    /// of silently minting a fresh half (a new id would orphan every grant
    /// binding that references this device; mirror of DeviceSigningIdentity).
    ///
    /// SHARED keychain group (same rationale as DeviceSigningIdentity): the
    /// extension opens per-device sealed blobs and approval responses with
    /// the same key the app enrolled. Pre-move pairs migrate from the
    /// app-private group on the app's next load.
    static func loadOrCreate() throws -> DeviceHPKEIdentity {
        let group = SharedConfig.keychainAccessGroup
        let storedKey = try KeychainStore.get(account: keyKeychainAccount, accessGroup: group)
        let storedID = try KeychainStore.get(account: idKeychainAccount, accessGroup: group)
        switch (storedKey, storedID) {
        case let (raw?, id?):
            guard let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw),
                  id.count == 32 else { throw Failure.corruptKeyMaterial }
            return DeviceHPKEIdentity(privateKey: key, deviceKeyID: id)
        case (nil, nil):
            // Migrate an app-private pair minted before the shared-group move.
            if let legacyKey = try? KeychainStore.get(account: keyKeychainAccount),
               let legacyID = try? KeychainStore.get(account: idKeychainAccount),
               let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: legacyKey),
               legacyID.count == 32 {
                try KeychainStore.set(legacyKey, account: keyKeychainAccount, accessGroup: group)
                try KeychainStore.set(legacyID, account: idKeychainAccount, accessGroup: group)
                KeychainStore.delete(account: keyKeychainAccount)
                KeychainStore.delete(account: idKeychainAccount)
                return DeviceHPKEIdentity(privateKey: key, deviceKeyID: legacyID)
            }
            let key = Curve25519.KeyAgreement.PrivateKey()
            let id = CryptoRandom.data(32)
            try KeychainStore.set(key.rawRepresentation, account: keyKeychainAccount, accessGroup: group)
            try KeychainStore.set(id, account: idKeychainAccount, accessGroup: group)
            return DeviceHPKEIdentity(privateKey: key, deviceKeyID: id)
        default:
            throw Failure.corruptKeyMaterial
        }
    }

    /// In-memory identity for tests / ephemeral flows (never persisted).
    static func ephemeral() -> DeviceHPKEIdentity {
        DeviceHPKEIdentity(privateKey: Curve25519.KeyAgreement.PrivateKey(),
                           deviceKeyID: CryptoRandom.data(32))
    }
}
