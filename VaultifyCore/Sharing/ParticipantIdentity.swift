import CryptoKit
import Foundation

/// The recipient's (B's) persistent HPKE identity for Approval Mode.
/// Static `shared` field blobs are sealed to `publicKeyRaw` (ADR-3).
///
/// Escrow model (ADR-2): the private key is sealed under B's OWN Vault Key
/// and stored in a dedicated synced record (Phase 3 transport, modeled on
/// `VaultKeyEscrowService`) so every unlocked device of B can decrypt shared
/// blobs. It does NOT ride vault-item sync and is never stored in plaintext.
/// Creation is transactional (Validation §3): vault ready → generate → seal
/// under Vault Key → persist → publish; never generate-then-wait.
nonisolated struct ParticipantIdentity: Sendable {
    let privateKey: Curve25519.KeyAgreement.PrivateKey

    var publicKeyRaw: Data { privateKey.publicKey.rawRepresentation }

    static func generate() -> ParticipantIdentity {
        ParticipantIdentity(privateKey: Curve25519.KeyAgreement.PrivateKey())
    }

    // MARK: Vault-Key escrow encoding

    enum EscrowFailure: Error, Equatable { case unknownVersion, invalidKeyMaterial }

    private static let escrowVersion: UInt8 = 1

    /// `[version] || AES-256-GCM(privateKeyRaw)` under the Vault Key.
    func escrowSealed(vaultKey: [UInt8]) throws -> Data {
        var envelope = Data([Self.escrowVersion])
        envelope.append(try AESGCM.seal(privateKey.rawRepresentation, key: vaultKey))
        return envelope
    }

    static func fromEscrow(_ envelope: Data, vaultKey: [UInt8]) throws -> ParticipantIdentity {
        guard envelope.first == escrowVersion else { throw EscrowFailure.unknownVersion }
        let raw = try AESGCM.open(envelope.dropFirst(), key: vaultKey)
        guard let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw) else {
            throw EscrowFailure.invalidKeyMaterial
        }
        return ParticipantIdentity(privateKey: key)
    }
}
