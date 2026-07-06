import CryptoKit
import Foundation

/// The Relay Principal: a long-lived, user-owned P256 signing key that authorizes
/// email-relay commands. It is deliberately DISTINCT from App Attest (which
/// attests a genuine app instance on a device) — the principal answers "who owns
/// this relay namespace across devices", App Attest answers "is this a real app
/// instance". A relay command is authorized by the principal AND independently
/// admitted by App Attest (two layers, never folded together).
///
/// One logical principal per vault. Signing-only (no key agreement / HPKE — the
/// principal authorizes, it doesn't decrypt). The private key exists only sealed
/// under the Vault Key or in memory while unlocked; it is escrowed to a CloudKit
/// singleton (a later phase) so it survives reinstall / new device / recovery.
nonisolated struct RelayPrincipalIdentity: Sendable {
    private let privateKey: P256.Signing.PrivateKey
    /// FROZEN at genesis and carried, never recomputed from the current key — the
    /// backend pins `principal_id` stable while the public key + epoch rotate.
    let principalID: Data
    let epoch: UInt64

    enum EscrowFailure: Error, Equatable { case unknownVersion, invalidKeyMaterial, identityMismatch }

    private static let escrowVersion: UInt8 = 1

    /// The current public key, X9.63 form (the fingerprint input + what the
    /// backend stores as `current_public_key`).
    var signingPublicKey: Data { privateKey.publicKey.x963Representation }

    /// Public projection (D5): stable id + rotating key/epoch.
    var state: RelayPrincipalState {
        RelayPrincipalState(principalID: principalID, epoch: epoch, signingPublicKey: signingPublicKey)
    }

    // MARK: Genesis + fingerprint

    /// Mint a brand-new principal at genesis (epoch 1). The id is derived once
    /// from this key's X9.63 public key and then frozen.
    static func generate() -> RelayPrincipalIdentity {
        let key = P256.Signing.PrivateKey()
        return RelayPrincipalIdentity(
            privateKey: key,
            principalID: derivePrincipalID(x963Pub: key.publicKey.x963Representation),
            epoch: 1)
    }

    /// `SHA256( MAGIC ‖ x963Pub )` via the canonical (length-prefixed) writer, so
    /// the fingerprint is injective and reproducible byte-for-byte by the worker.
    static func derivePrincipalID(x963Pub: Data) -> Data {
        var w = CanonicalWriter()
        w.string(RelayConfig.principalMagic)
        w.blob(x963Pub)
        return Data(SHA256.hash(data: w.data))
    }

    // MARK: Signing (ECDSA-P256/SHA-256, 64-byte raw signature — matches DeviceSigningIdentity)

    func signature(for data: Data) throws -> Data {
        try privateKey.signature(for: data).rawRepresentation
    }

    static func verify(_ data: Data, signature: Data, x963PublicKey: Data) -> Bool {
        guard let publicKey = try? P256.Signing.PublicKey(x963Representation: x963PublicKey),
              let ecdsa = try? P256.Signing.ECDSASignature(rawRepresentation: signature) else {
            return false
        }
        return publicKey.isValidSignature(ecdsa, for: data)
    }

    // MARK: Rotation (pure — escrow overwrite is a later phase)

    /// A fresh signing key at the next epoch, keeping the SAME principalID. The
    /// old key/epoch are superseded; the backend accepts the new key only via a
    /// signed rotate command that carries the previous epoch.
    func rotated() -> RelayPrincipalIdentity {
        RelayPrincipalIdentity(privateKey: P256.Signing.PrivateKey(),
                               principalID: principalID, epoch: epoch + 1)
    }

    // MARK: Vault-Key escrow codec — `[version] ‖ AES-256-GCM(body)`

    /// Body = canonical `blob(principalID) ‖ u64(epoch) ‖ blob(privateKeyRaw)`.
    func escrowSealed(vaultKey: [UInt8]) throws -> Data {
        var body = CanonicalWriter()
        body.blob(principalID)
        body.u64(epoch)
        body.blob(privateKey.rawRepresentation)
        var envelope = Data([Self.escrowVersion])
        envelope.append(try AESGCM.seal(body.data, key: vaultKey))
        return envelope
    }

    /// Reconstruct from a sealed envelope. Bad key material THROWS (never a silent
    /// regen — a new key would change principalID and break every backend pin).
    /// At genesis (epoch 1) the stored id is re-derived and verified against the
    /// key; after rotation the public key has changed, so the stored id is trusted.
    static func fromEscrow(_ envelope: Data, vaultKey: [UInt8]) throws -> RelayPrincipalIdentity {
        guard envelope.first == escrowVersion else { throw EscrowFailure.unknownVersion }
        let body = try AESGCM.open(envelope.dropFirst(), key: vaultKey)
        var r = CanonicalReader(body)
        let principalID = try r.blob()
        let epoch = try r.u64()
        let rawKey = try r.blob()
        guard let key = try? P256.Signing.PrivateKey(rawRepresentation: rawKey) else {
            throw EscrowFailure.invalidKeyMaterial
        }
        if epoch == 1 {
            let derived = derivePrincipalID(x963Pub: key.publicKey.x963Representation)
            guard derived == principalID else { throw EscrowFailure.identityMismatch }
        }
        return RelayPrincipalIdentity(privateKey: key, principalID: principalID, epoch: epoch)
    }

    private init(privateKey: P256.Signing.PrivateKey, principalID: Data, epoch: UInt64) {
        self.privateKey = privateKey
        self.principalID = principalID
        self.epoch = epoch
    }
}
