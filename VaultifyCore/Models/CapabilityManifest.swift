import CryptoKit
import Foundation

/// Signed capability manifest — the DISTRIBUTION layer for operator policy
/// (the workers' `capability_*` gate stays the enforcement layer; a stale or
/// forged manifest can never widen what the server allows).
///
/// Wire envelope (frozen, proposed to BE as B3):
///   { "payload_b64": <b64 raw JSON payload>, "signature_b64": <b64 raw 64-byte
///     P256 ECDSA over the EXACT payload bytes>, "key_id": "k1" }
/// Signing the raw payload bytes removes any canonicalization question: the
/// client verifies the bytes it received, then decodes them.
nonisolated struct CapabilityManifestEnvelope: Codable, Sendable {
    let payloadB64: String
    let signatureB64: String
    let keyID: String

    enum CodingKeys: String, CodingKey {
        case payloadB64 = "payload_b64"
        case signatureB64 = "signature_b64"
        case keyID = "key_id"
    }
}

/// Decoded manifest payload. Unknown capability keys are ignored (forward
/// compatible); a capability absent from the manifest keeps its last state.
nonisolated struct CapabilityManifest: Codable, Sendable, Equatable {
    struct Entry: Codable, Sendable, Equatable {
        let mode: CapabilityServiceMode
        let retryAfter: Int?

        enum CodingKeys: String, CodingKey {
            case mode
            case retryAfter = "retry_after"
        }
    }

    let schemaVersion: Int
    let manifestVersion: UInt64
    let issuedAtUnixMs: Int64
    let expiresAtUnixMs: Int64
    let capabilities: [String: Entry]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case manifestVersion = "manifest_version"
        case issuedAtUnixMs = "issued_at_unix_ms"
        case expiresAtUnixMs = "expires_at_unix_ms"
        case capabilities
    }

    func entry(for id: CapabilityID) -> Entry? { capabilities[id.rawValue] }
}

/// Pure manifest verification: signature (trusted key set by `key_id` — key
/// rotation is a set update, not a new mechanism), schema, timestamp window,
/// and anti-rollback against the highest previously accepted version.
nonisolated enum CapabilityManifestVerifier {
    static let supportedSchemaVersion = 1

    enum VerifyError: Error, Equatable {
        case malformedEnvelope
        case unknownKey(String)
        case badSignature
        case malformedPayload
        case unsupportedSchema(Int)
        case notYetValid
        case expired
        case rollback(received: UInt64, highestAccepted: UInt64)
    }

    /// Trusted verification keys, keyed by `key_id` (x963 P256 public keys).
    /// BUNDLED set is empty until the BE freezes B3 and hands over real keys —
    /// with no trusted key every fetched manifest is rejected and the app
    /// stays on cache → bundled defaults (all-active), which is fail-safe.
    static let bundledTrustedKeys: [String: Data] = [:]

    static func verify(envelopeData: Data,
                       trustedKeys: [String: Data],
                       now: Date,
                       highestAcceptedVersion: UInt64) throws -> CapabilityManifest {
        guard let envelope = try? JSONDecoder().decode(CapabilityManifestEnvelope.self, from: envelopeData),
              let payload = Data(base64Encoded: envelope.payloadB64),
              let rawSignature = Data(base64Encoded: envelope.signatureB64) else {
            throw VerifyError.malformedEnvelope
        }
        guard let keyBytes = trustedKeys[envelope.keyID] else {
            throw VerifyError.unknownKey(envelope.keyID)
        }
        guard let key = try? P256.Signing.PublicKey(x963Representation: keyBytes),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: rawSignature),
              key.isValidSignature(signature, for: payload) else {
            throw VerifyError.badSignature
        }
        guard let manifest = try? JSONDecoder().decode(CapabilityManifest.self, from: payload) else {
            throw VerifyError.malformedPayload
        }
        guard manifest.schemaVersion == supportedSchemaVersion else {
            throw VerifyError.unsupportedSchema(manifest.schemaVersion)
        }
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        guard nowMs >= manifest.issuedAtUnixMs else { throw VerifyError.notYetValid }
        guard nowMs < manifest.expiresAtUnixMs else { throw VerifyError.expired }
        guard manifest.manifestVersion >= highestAcceptedVersion else {
            throw VerifyError.rollback(received: manifest.manifestVersion,
                                       highestAccepted: highestAcceptedVersion)
        }
        return manifest
    }
}
