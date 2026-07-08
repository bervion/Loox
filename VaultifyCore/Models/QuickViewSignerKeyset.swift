import CryptoKit
import Foundation

/// Offline-signed endorsement of the Quick View worker's dedicated runtime
/// session-signer public key(s) — BE contract `LOOX-QUICK-VIEW-SIGNER-KEYSET-V1`
/// (frozen, parity vectors in
/// `VaultifyTests/Fixtures/quick-view-signer-keyset-vectors-v1.json`).
///
/// Same trust root and verify pipeline shape as the capability manifest /
/// domain registry (P-256 root key, canonical transcript, verify→cache→apply,
/// silent-failure client policy) but a DIFFERENT document family: its own
/// MAGIC (must never verify as a manifest or registry) and its own
/// independent monotonic anti-rollback counter (`keyset_version`,
/// independent of the manifest/registry's own version numbering).
///
/// This document endorses the QUICK VIEW WORKER's dedicated runtime
/// session-signer key(s) — signed OFFLINE by the same root that signs the
/// manifest/registry, but the keys it lists are a SEPARATE, online,
/// per-request signer (key separation: a compromised runtime signer cannot
/// forge this endorsement of itself). `env` sits INSIDE the signed payload so
/// a staging keyset can never be replayed on production. Rotation overlap is
/// expressed via each key's `status`: next → active → verify_only → revoked.
nonisolated struct QuickViewSignerKeysetDocument: Codable, Sendable, Equatable {

    enum Status: String, Codable, Sendable {
        case next, active
        case verifyOnly = "verify_only"
        case revoked
    }

    struct SignerKey: Codable, Sendable, Equatable {
        let keyID: String
        let alg: String
        /// X9.63/raw uncompressed P-256 point — base64 (std) on the wire
        /// (NOT the hex convention the session-envelope hash/nonce fields
        /// use; this mirrors the manifest/registry's own trusted-key bytes).
        let publicKey: Data
        let env: String
        let notBefore: Int64   // unix ms
        let notAfter: Int64    // unix ms
        let status: Status

        enum CodingKeys: String, CodingKey {
            case keyID = "key_id"
            case alg
            case publicKey = "public_key"
            case env
            case notBefore = "not_before"
            case notAfter = "not_after"
            case status
        }
    }

    let schemaVersion: Int
    let keysetVersion: UInt64
    /// Root key id — the offline trust-root key that signs THIS document
    /// (same key family as the capability manifest / domain registry).
    let keyID: String
    let env: String
    let issuedAt: Int64    // unix ms
    let expiresAt: Int64   // unix ms
    let keys: [SignerKey]
    let signature: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case keysetVersion = "keyset_version"
        case keyID = "key_id"
        case env
        case issuedAt = "issued_at"
        case expiresAt = "expires_at"
        case keys, signature
    }

    /// Canonical signing transcript (must match `loox-config/src/quick-view-signer-keyset.ts`
    /// byte-for-byte — parity-tested against the frozen vectors):
    ///   raw(MAGIC) ‖ byte(schema_version) ‖ u64(keyset_version) ‖ string(key_id) ‖
    ///   string(env) ‖ i64(issued_at) ‖ i64(expires_at) ‖ u32(#keys) ‖
    ///   ∀key sorted by key_id: string(key_id) ‖ string(alg) ‖ blob(public_key) ‖
    ///   string(env) ‖ i64(not_before) ‖ i64(not_after) ‖ string(status)
    var transcript: Data {
        var w = CanonicalWriter()
        w.raw(Data(QuickViewSignerKeysetVerifier.magic.utf8))
        w.byte(UInt8(truncatingIfNeeded: schemaVersion))
        w.u64(keysetVersion)
        w.string(keyID)
        w.string(env)
        w.i64(issuedAt)
        w.i64(expiresAt)
        let sorted = keys.sorted { $0.keyID < $1.keyID }
        w.u32(UInt32(sorted.count))
        for key in sorted {
            w.string(key.keyID)
            w.string(key.alg)
            w.blob(key.publicKey)
            w.string(key.env)
            w.i64(key.notBefore)
            w.i64(key.notAfter)
            w.string(key.status.rawValue)
        }
        return w.data
    }

    /// Resolve the endorsed runtime session-signer public key for `keyID` —
    /// must currently be `active` or `verifyOnly` (a short overlap after the
    /// backend stops signing with a retiring key), match `expectedEnv`, and
    /// fall within its own `[not_before, not_after)` window. Independent of
    /// this DOCUMENT's own issued/expires freshness (checked separately by
    /// `QuickViewSignerKeysetVerifier`).
    func endorsedPublicKey(keyID: String, expectedEnv: String, now: Date) -> Data? {
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        guard let key = keys.first(where: { $0.keyID == keyID }) else { return nil }
        guard key.status == .active || key.status == .verifyOnly else { return nil }
        guard key.env == expectedEnv else { return nil }
        guard nowMs >= key.notBefore, nowMs < key.notAfter else { return nil }
        return key.publicKey
    }
}

/// Pure verification, mirroring `DomainRegistryVerifier`: signature over the
/// canonical transcript (shared trusted key set — the capability-manifest
/// trust root), schema, env binding, freshness window, strict anti-rollback
/// on the keyset's OWN independent version counter.
nonisolated enum QuickViewSignerKeysetVerifier {
    static let magic = "LOOX-QUICK-VIEW-SIGNER-KEYSET-V1"
    static let supportedSchemaVersion = 1

    enum VerifyError: Error, Equatable {
        case malformedDocument
        case missingSignature
        case unknownKey(String)
        case badSignature
        case unsupportedSchema(Int)
        case wrongEnvironment(String)
        case notYetValid
        case expired
        case rollback(received: UInt64, highestAccepted: UInt64)
    }

    static func verify(documentData: Data,
                       trustedKeys: [String: Data],
                       expectedEnv: String,
                       now: Date,
                       highestAcceptedVersion: UInt64) throws -> QuickViewSignerKeysetDocument {
        guard let document = try? JSONDecoder().decode(QuickViewSignerKeysetDocument.self, from: documentData) else {
            throw VerifyError.malformedDocument
        }
        guard let signatureB64 = document.signature,
              let rawSignature = Data(base64Encoded: signatureB64) else {
            throw VerifyError.missingSignature
        }
        guard let keyBytes = trustedKeys[document.keyID] else {
            throw VerifyError.unknownKey(document.keyID)
        }
        guard let key = try? P256.Signing.PublicKey(x963Representation: keyBytes),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: rawSignature),
              key.isValidSignature(signature, for: document.transcript) else {
            throw VerifyError.badSignature
        }
        guard document.schemaVersion == supportedSchemaVersion else {
            throw VerifyError.unsupportedSchema(document.schemaVersion)
        }
        guard document.env == expectedEnv else {
            throw VerifyError.wrongEnvironment(document.env)
        }
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        guard nowMs >= document.issuedAt else { throw VerifyError.notYetValid }
        guard nowMs < document.expiresAt else { throw VerifyError.expired }
        // Reject only a strictly older version; an equal version is an idempotent
        // re-serve admitted for the client store's hash-gated recovery.
        guard document.keysetVersion >= highestAcceptedVersion else {
            throw VerifyError.rollback(received: document.keysetVersion,
                                       highestAccepted: highestAcceptedVersion)
        }
        return document
    }
}
