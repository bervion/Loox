import CryptoKit
import Foundation

/// Signed session envelope minted by the browser/backend at `/open` —
/// `LOOX-QUICK-VIEW-SESSION-V1` (BE-parity proven against the frozen vectors
/// `VaultifyTests/Fixtures/quick-view-session-vectors-v1.json`). Follows the
/// `DomainRegistryDocument`/`CapabilityManifest` pattern: the wire is JSON,
/// and the signature covers a canonical BINARY transcript (not the JSON
/// bytes) built with `QuickViewWire`.
///
/// Wire quirk (shared by every hash/nonce field in this artifact family):
/// `session_id`/`enc_key_hash`/`sig_key_hash`/`browser_nonce`/`server_nonce`
/// are HEX strings in JSON but raw hex-DECODED bytes inside the signed
/// transcript — never base64, never the string's own UTF-8 bytes. This type
/// decodes those fields explicitly (Foundation's default `Data` Codable
/// strategy is base64 and would silently produce the WRONG bytes for a hex
/// string, since hex digits happen to also be valid base64 characters).
nonisolated struct QuickViewSessionEnvelope: Sendable, Equatable {
    let version: Int
    let keyID: String
    /// The wire hex string — kept verbatim as the app-level session
    /// identifier (URL path segments, upload AAD, history rows, UI).
    let sessionID: String
    /// `sessionID` hex-decoded to the raw 32 bytes every transcript
    /// (SESSION-V1, SAS, KDF, AAD) actually binds.
    let sessionIDBytes: Data
    let encKeyHash: Data
    let sigKeyHash: Data
    let browserNonce: Data
    let serverNonce: Data
    let issuedAt: Int64    // unix ms
    let expiresAt: Int64   // unix ms
    /// "staging" | "production" — INSIDE the signed payload (same convention
    /// as `DomainRegistryDocument.env`) so a staging envelope can never
    /// verify against a production install or vice versa.
    let env: String
    let signature: String?

    enum CodingKeys: String, CodingKey {
        case version
        case keyID = "key_id"
        case sessionID = "session_id"
        case encKeyHash = "enc_key_hash"
        case sigKeyHash = "sig_key_hash"
        case browserNonce = "browser_nonce"
        case serverNonce = "server_nonce"
        case issuedAt = "issued_at"
        case expiresAt = "expires_at"
        case env, signature
    }

    /// Canonical signing transcript (field order matters — `key_id` sits
    /// right after `version`, BEFORE `session_id`):
    ///   raw(magic) ‖ byte(version) ‖ string(key_id) ‖ blob(session_id bytes) ‖
    ///   blob(enc_key_hash) ‖ blob(sig_key_hash) ‖ blob(browser_nonce) ‖
    ///   blob(server_nonce) ‖ i64(issued_at) ‖ i64(expires_at) ‖ string(env)
    var transcript: Data {
        var out = Data(QuickViewSessionEnvelopeVerifier.magic.utf8)
        out += QuickViewWire.byte(UInt8(truncatingIfNeeded: version))
        out += QuickViewWire.lengthPrefixed(keyID)
        out += QuickViewWire.lengthPrefixed(sessionIDBytes)
        out += QuickViewWire.lengthPrefixed(encKeyHash)
        out += QuickViewWire.lengthPrefixed(sigKeyHash)
        out += QuickViewWire.lengthPrefixed(browserNonce)
        out += QuickViewWire.lengthPrefixed(serverNonce)
        out += QuickViewWire.i64(issuedAt)
        out += QuickViewWire.i64(expiresAt)
        out += QuickViewWire.lengthPrefixed(env)
        return out
    }
}

extension QuickViewSessionEnvelope: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        keyID = try c.decode(String.self, forKey: .keyID)
        let session = try c.decode(String.self, forKey: .sessionID)
        guard let sessionBytes = QuickViewWire.base64URLDecode(session) else {
            throw DecodingError.dataCorruptedError(forKey: .sessionID, in: c,
                                                   debugDescription: "session_id must be a base64url string")
        }
        sessionID = session
        sessionIDBytes = sessionBytes
        encKeyHash = try Self.b64urlField(c, .encKeyHash)
        sigKeyHash = try Self.b64urlField(c, .sigKeyHash)
        browserNonce = try Self.b64urlField(c, .browserNonce)
        serverNonce = try Self.b64urlField(c, .serverNonce)
        issuedAt = try c.decode(Int64.self, forKey: .issuedAt)
        expiresAt = try c.decode(Int64.self, forKey: .expiresAt)
        env = try c.decode(String.self, forKey: .env)
        signature = try c.decodeIfPresent(String.self, forKey: .signature)
    }

    private static func b64urlField(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> Data {
        let raw = try c.decode(String.self, forKey: key)
        guard let data = QuickViewWire.base64URLDecode(raw) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: c,
                                                   debugDescription: "\(key.rawValue) must be a base64url string")
        }
        return data
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(keyID, forKey: .keyID)
        try c.encode(sessionID, forKey: .sessionID)
        try c.encode(QuickViewWire.base64URLEncode(encKeyHash), forKey: .encKeyHash)
        try c.encode(QuickViewWire.base64URLEncode(sigKeyHash), forKey: .sigKeyHash)
        try c.encode(QuickViewWire.base64URLEncode(browserNonce), forKey: .browserNonce)
        try c.encode(QuickViewWire.base64URLEncode(serverNonce), forKey: .serverNonce)
        try c.encode(issuedAt, forKey: .issuedAt)
        try c.encode(expiresAt, forKey: .expiresAt)
        try c.encode(env, forKey: .env)
        try c.encodeIfPresent(signature, forKey: .signature)
    }
}

/// Pure verification, mirroring `DomainRegistryVerifier`/
/// `CapabilityManifestVerifier`: signature over the canonical transcript,
/// schema, env binding, freshness window, and key-hash consistency against
/// whatever the QR/code carrier delivered (closes the substitution gap a
/// locator-only carrier would otherwise leave open).
///
/// Trust source (DEC-QV-SIGN-01): the signing key is the QUICK VIEW WORKER's
/// dedicated runtime session-signer — NOT the bundled capability-manifest
/// trust root directly. Callers resolve `envelope.key_id` against an
/// ALREADY-VERIFIED `QuickViewSignerKeysetDocument` (itself signed by the
/// offline trust root, fetched/cached by `QuickViewSignerKeysetClient`) and
/// pass in only the resolved, currently-endorsed public key bytes.
nonisolated enum QuickViewSessionEnvelopeVerifier {
    static let magic = "LOOX-QUICK-VIEW-SESSION-V1"
    static let supportedVersion = 1

    enum VerifyError: Error, Equatable {
        case malformedEnvelope
        case missingSignature
        case unknownKey(String)
        case badSignature
        case unsupportedVersion(Int)
        case wrongEnvironment(String)
        case notYetValid
        case expired
        case keyHashMismatch
    }

    /// - Parameters:
    ///   - resolveSignerKey: maps `key_id` → the endorsed runtime
    ///     session-signer public key (x963 uncompressed P-256 point), or
    ///     `nil` if unknown/not currently endorsed. Callers pass
    ///     `QuickViewSignerKeysetDocument.endorsedPublicKey(keyID:expectedEnv:now:)`
    ///     — a key resolved from an ALREADY-VERIFIED signer keyset, never a
    ///     carrier-supplied or unverified key.
    ///   - expectedEncKeyHash/expectedSigKeyHash: hashes observed from the
    ///     QR/code carrier — MUST match the signed envelope's own hashes.
    static func verify(envelopeData: Data,
                       resolveSignerKey: (String) -> Data?,
                       expectedEnv: String,
                       expectedEncKeyHash: Data,
                       expectedSigKeyHash: Data,
                       now: Date = .now) throws -> QuickViewSessionEnvelope {
        guard let envelope = try? JSONDecoder().decode(QuickViewSessionEnvelope.self, from: envelopeData) else {
            throw VerifyError.malformedEnvelope
        }
        guard let signatureB64 = envelope.signature,
              let rawSignature = Data(base64Encoded: signatureB64) else {
            throw VerifyError.missingSignature
        }
        guard let signerPublicKey = resolveSignerKey(envelope.keyID) else {
            throw VerifyError.unknownKey(envelope.keyID)
        }
        guard let key = try? P256.Signing.PublicKey(x963Representation: signerPublicKey),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: rawSignature),
              key.isValidSignature(signature, for: envelope.transcript) else {
            throw VerifyError.badSignature
        }
        guard envelope.version == supportedVersion else {
            throw VerifyError.unsupportedVersion(envelope.version)
        }
        guard envelope.env == expectedEnv else {
            throw VerifyError.wrongEnvironment(envelope.env)
        }
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        guard nowMs >= envelope.issuedAt else { throw VerifyError.notYetValid }
        guard nowMs < envelope.expiresAt else { throw VerifyError.expired }
        // Mandatory substitution guard: the raw keys the carrier delivered must
        // hash to the values the signed envelope committed to (no optional skip).
        guard expectedEncKeyHash == envelope.encKeyHash else {
            throw VerifyError.keyHashMismatch
        }
        guard expectedSigKeyHash == envelope.sigKeyHash else {
            throw VerifyError.keyHashMismatch
        }
        return envelope
    }
}
