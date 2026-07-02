import CryptoKit
import Foundation

/// HPKE envelope for iOS 18 automatic passkey upgrades. The extension can seal
/// while locked with the public key; only an unlocked vault can open or migrate.
nonisolated enum PasskeyEnvelope {
    enum Failure: Error { case noVault, unknownVersion, invalidKey, oversized, invalidSecret }
    enum PublicKeyState: Equatable { case generated, valid, mismatch }

    private static let version: UInt8 = 1
    private static let publicKeyLength = 32
    private static let privateKeyLength = 32
    private static let encapsulatedKeyLength = 32
    private static let maxEnvelopeBytes = 16_384
    private static let info = Data("Vaultify passkey envelope v1".utf8)
    private static let ciphersuite = HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly

    static func publicKey() -> Data? {
        guard let key = VaultKeyBundle.load()?.envelopePublicKey,
              (try? publicKey(from: key)) != nil else { return nil }
        return key
    }

    @discardableResult
    static func provisionOrVerify(vaultKey: [UInt8]) throws -> PublicKeyState {
        guard var bundle = VaultKeyBundle.load() else { throw Failure.noVault }
        if let publicKey = bundle.envelopePublicKey,
           let sealedPrivate = bundle.envelopePrivateKeySealed {
            do {
                let privateKey = try privateKey(fromSealed: sealedPrivate, vaultKey: vaultKey)
                let derivedPublic = versioned(privateKey.publicKey.rawRepresentation)
                guard derivedPublic == publicKey else { throw Failure.invalidKey }
                return .valid
            } catch {
                try generate(in: &bundle, vaultKey: vaultKey)
                return .mismatch
            }
        }
        try generate(in: &bundle, vaultKey: vaultKey)
        return .generated
    }

    static func provisionOrVerify(vaultKey: SecureBytes) throws -> PublicKeyState {
        try vaultKey.withUnsafeBytes { try provisionOrVerify(vaultKey: Array($0)) }
    }

    static func seal(_ secret: PasskeySecret, to versionedPublicKey: Data) throws -> Data {
        try validate(secret)
        let recipient = try publicKey(from: versionedPublicKey)
        var sender = try HPKE.Sender(recipientKey: recipient, ciphersuite: ciphersuite, info: info)
        let ciphertext = try sender.seal(JSONEncoder().encode(secret))
        var envelope = Data([version])
        envelope.append(sender.encapsulatedKey)
        envelope.append(ciphertext)
        guard envelope.count <= maxEnvelopeBytes else { throw Failure.oversized }
        return envelope
    }

    static func open(_ envelope: Data, vaultKey: [UInt8]) throws -> PasskeySecret {
        guard envelope.count <= maxEnvelopeBytes else { throw Failure.oversized }
        guard envelope.count > 1 + encapsulatedKeyLength else { throw Failure.invalidKey }
        guard envelope.first == version else { throw Failure.unknownVersion }
        guard let bundle = VaultKeyBundle.load(),
              let sealedPrivate = bundle.envelopePrivateKeySealed else { throw Failure.noVault }
        let privateKey = try privateKey(fromSealed: sealedPrivate, vaultKey: vaultKey)
        let encapsulatedKey = envelope.dropFirst().prefix(encapsulatedKeyLength)
        let ciphertext = envelope.dropFirst(1 + encapsulatedKeyLength)
        var recipient = try HPKE.Recipient(privateKey: privateKey, ciphersuite: ciphersuite,
                                           info: info, encapsulatedKey: Data(encapsulatedKey))
        let plaintext = try recipient.open(Data(ciphertext))
        let secret = try JSONDecoder().decode(PasskeySecret.self, from: plaintext)
        try validate(secret)
        return secret
    }

    static func open(_ envelope: Data, vaultKey: SecureBytes) throws -> PasskeySecret {
        try vaultKey.withUnsafeBytes { try open(envelope, vaultKey: Array($0)) }
    }

    static func validate(_ secret: PasskeySecret) throws {
        guard !secret.relyingParty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !secret.userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !secret.userHandle.isEmpty,
              !secret.credentialID.isEmpty,
              secret.credentialID.count <= 1024 else { throw Failure.invalidSecret }
        _ = try P256.Signing.PrivateKey(rawRepresentation: secret.privateKeyRaw)
    }

    private static func generate(in bundle: inout VaultKeyBundle, vaultKey: [UInt8]) throws {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let privatePayload = versioned(privateKey.rawRepresentation)
        bundle.envelopePublicKey = versioned(privateKey.publicKey.rawRepresentation)
        bundle.envelopePrivateKeySealed = try AESGCM.seal(privatePayload, key: vaultKey)
        try bundle.save()
    }

    private static func publicKey(from versionedKey: Data) throws -> Curve25519.KeyAgreement.PublicKey {
        guard versionedKey.count == 1 + publicKeyLength,
              versionedKey.first == version else { throw Failure.invalidKey }
        return try Curve25519.KeyAgreement.PublicKey(rawRepresentation: versionedKey.dropFirst())
    }

    private static func privateKey(fromSealed sealed: Data, vaultKey: [UInt8]) throws -> Curve25519.KeyAgreement.PrivateKey {
        let plaintext = try AESGCM.open(sealed, key: vaultKey)
        guard plaintext.count == 1 + privateKeyLength,
              plaintext.first == version else { throw Failure.invalidKey }
        return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: plaintext.dropFirst())
    }

    private static func versioned(_ raw: Data) -> Data {
        var data = Data([version])
        data.append(raw)
        return data
    }
}
