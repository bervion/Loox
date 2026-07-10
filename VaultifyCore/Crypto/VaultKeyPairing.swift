import CryptoKit
import Foundation

/// Device-pairing crypto: hand the Vault Key from a trusted device to a new one
/// with the key never leaving either device as plaintext.
///
/// Ceremony: the NEW device generates an ephemeral Curve25519 keypair and shows its
/// public key (+ a random pairing id) as a QR. The TRUSTED device scans it and
/// HPKE-seals the Vault Key to that ephemeral public key (same
/// `Curve25519_SHA256_ChachaPoly` suite as the passkey envelope), binding the
/// pairing id into the HPKE `info` so a response cannot be replayed for a different
/// pairing session. The sealed envelope travels via a CloudKit hand-off record in
/// the user's own private database; only the ephemeral private key — which never
/// leaves the new device — can open it.
nonisolated enum VaultKeyPairing {
    enum Failure: Error, LocalizedError {
        case invalidPayload, unknownVersion, invalidEnvelope

        var errorDescription: String? {
            switch self {
            case .invalidPayload: return appString("That QR code isn’t a Loox pairing code.")
            case .unknownVersion: return appString("This pairing code needs a newer app version.")
            case .invalidEnvelope: return appString("Pairing failed. Try again with a fresh QR code.")
            }
        }
    }

    private static let version: UInt8 = 1
    private static let payloadPrefix = "loox-pair"
    private static let encapsulatedKeyLength = 32
    private static let ciphersuite = HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly

    /// HPKE info binding: domain-separates pairing envelopes and ties one to its
    /// pairing session, so an envelope sealed for one QR can't be replayed for another.
    private static func info(pairingId: String) -> Data {
        Data("Vaultify device pairing v1|\(pairingId)".utf8)
    }

    // MARK: New-device side

    /// One pairing session on the NEW device: the ephemeral private key stays in
    /// memory only; `qrPayload` is what the trusted device scans.
    struct Session {
        let pairingId: String
        let privateKey: Curve25519.KeyAgreement.PrivateKey
        var qrPayload: String {
            let publicKey = privateKey.publicKey.rawRepresentation.base64URLEncoded
            return "\(payloadPrefix)/\(version)/\(pairingId)/\(publicKey)"
        }
    }

    static func makeSession() -> Session {
        Session(pairingId: Data(CryptoRandom.bytes(16)).base64URLEncoded,
                privateKey: Curve25519.KeyAgreement.PrivateKey())
    }

    /// Open a sealed hand-off envelope with the session's ephemeral private key.
    static func open(_ envelope: Data, session: Session) throws -> [UInt8] {
        guard envelope.count > 1 + encapsulatedKeyLength else { throw Failure.invalidEnvelope }
        guard envelope.first == version else { throw Failure.unknownVersion }
        let encapsulatedKey = envelope.dropFirst().prefix(encapsulatedKeyLength)
        let ciphertext = envelope.dropFirst(1 + encapsulatedKeyLength)
        var recipient = try HPKE.Recipient(privateKey: session.privateKey,
                                           ciphersuite: ciphersuite,
                                           info: info(pairingId: session.pairingId),
                                           encapsulatedKey: Data(encapsulatedKey))
        let plaintext = try recipient.open(Data(ciphertext))
        guard plaintext.count == KeyHierarchy.vaultKeyLength else { throw Failure.invalidEnvelope }
        return Array(plaintext)
    }

    // MARK: Trusted-device side

    /// A parsed pairing QR: where (which session) and to whom (which ephemeral key)
    /// the Vault Key should be sealed.
    struct Request {
        let pairingId: String
        let publicKey: Curve25519.KeyAgreement.PublicKey
    }

    /// Parse a scanned QR payload (`loox-pair/<version>/<id>/<pubkey-b64url>`).
    static func parse(qrPayload: String) throws -> Request {
        let parts = qrPayload.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == payloadPrefix else { throw Failure.invalidPayload }
        guard parts[1] == String(version) else { throw Failure.unknownVersion }
        let pairingId = String(parts[2])
        guard !pairingId.isEmpty,
              let keyData = Data(base64URLEncoded: String(parts[3])),
              let publicKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: keyData)
        else { throw Failure.invalidPayload }
        return Request(pairingId: pairingId, publicKey: publicKey)
    }

    /// HPKE-seal the Vault Key to the new device's ephemeral public key.
    static func seal(vaultKey: [UInt8], to request: Request) throws -> Data {
        var sender = try HPKE.Sender(recipientKey: request.publicKey,
                                     ciphersuite: ciphersuite,
                                     info: info(pairingId: request.pairingId))
        let ciphertext = try sender.seal(Data(vaultKey))
        var envelope = Data([version])
        envelope.append(sender.encapsulatedKey)
        envelope.append(ciphertext)
        return envelope
    }
}

// MARK: - base64url helpers (QR payload legibility — no `+`/`/`/`=`)

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        self.init(base64Encoded: base64)
    }
}
