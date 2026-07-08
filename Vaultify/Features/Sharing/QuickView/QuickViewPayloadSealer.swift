import CryptoKit
import Foundation

/// Seals a Quick View payload to the browser's ephemeral P-256 encryption
/// key: fresh app ephemeral keypair (generated per seal, never reused) →
/// ECDH(app_eph, browser_enc_pub) → HKDF-Extract(salt = SHA256(kdf
/// transcript)) → HKDF-Expand(info = payload_key_info) → AES-256-GCM,
/// additionally authenticating the AAD transcript. Deliberately NOT
/// `ApprovalCrypto`'s HPKE (`Curve25519_SHA256_ChachaPoly`) — Quick View is a
/// separate, owner-locked, WebCrypto-compatible suite.
///
/// BE-parity proven (`workers/loox-quick-view/src/contracts/payload-transcript.ts`,
/// frozen vectors `VaultifyTests/Fixtures/quick-view-payload-vectors-v1.json`).
/// `session_id`/`approval_id` are raw hex-DECODED bytes in both the KDF
/// transcript and the AAD — never UTF-8 strings — so callers pass the
/// already-decoded `Data` forms (see `QuickViewSessionEnvelope.sessionIDBytes`).
nonisolated enum QuickViewPayloadSealer {
    /// Distinct magic for the HKDF-Extract salt transcript (KDF context) —
    /// never the same bytes as `payloadMagic` (AAD / key-info), so a value
    /// from one can never be reinterpreted as the other.
    static let kdfMagic = "LOOX-QUICK-VIEW-KDF-V1"
    /// Shared by the AAD transcript AND the HKDF-Expand info label.
    static let payloadMagic = "LOOX-QUICK-VIEW-PAYLOAD-V1"
    static let cryptoVersion: UInt8 = 1
    /// AES-GCM nonce length prepended to the opaque wire ciphertext.
    static let nonceLength = 12

    enum SealError: Error, Equatable {
        case invalidBrowserKey
        case sealFailed
    }

    enum OpenError: Error, Equatable {
        case invalidKey
        case malformedCiphertext
        case openFailed
    }

    /// Result of one seal — everything the upload body (Phase 3) needs.
    nonisolated struct SealedPayload: Sendable, Equatable {
        /// Opaque wire blob: 12-byte AES-GCM nonce ‖ ciphertext ‖ 16-byte tag.
        /// No separate wire IV field — the contract deliberately keeps the
        /// upload `ciphertext` fully opaque to the server; the reader splits
        /// the first 12 bytes off before decrypting.
        let ciphertext: Data
        /// x963-uncompressed app ephemeral public key — travels alongside
        /// the ciphertext so the browser can redo the ECDH.
        let appEphemeralPublicKey: Data
    }

    /// `kdf_transcript = raw(KDF_MAGIC) ‖ byte(version) ‖ blob(session_id) ‖
    ///   blob(browser_enc_key_hash) ‖ blob(browser_sig_key_hash) ‖
    ///   blob(SHA256(app_eph_pub)) ‖ string(env)` — SHA-256'd and used as the
    /// HKDF-Extract salt.
    static func kdfTranscript(sessionID: Data, browserEncKeyHash: Data,
                             browserSigKeyHash: Data, appEphemeralPublicKey: Data,
                             env: String) -> Data {
        var out = Data(kdfMagic.utf8)
        out += QuickViewWire.byte(cryptoVersion)
        out += QuickViewWire.lengthPrefixed(sessionID)
        out += QuickViewWire.lengthPrefixed(browserEncKeyHash)
        out += QuickViewWire.lengthPrefixed(browserSigKeyHash)
        out += QuickViewWire.lengthPrefixed(Data(SHA256.hash(data: appEphemeralPublicKey)))
        out += QuickViewWire.lengthPrefixed(env)
        return out
    }

    /// `aad = raw(PAYLOAD_MAGIC) ‖ blob(session_id) ‖ blob(enc_key_hash) ‖
    ///   blob(approval_id) ‖ blob(field_manifest_hash) ‖ i64(issued_at) ‖
    ///   i64(expires_at)` — the AES-256-GCM additional authenticated data.
    static func aad(sessionID: Data, encKeyHash: Data, approvalID: Data,
                    fieldManifestHash: Data, issuedAt: Int64, expiresAt: Int64) -> Data {
        var out = Data(payloadMagic.utf8)
        out += QuickViewWire.lengthPrefixed(sessionID)
        out += QuickViewWire.lengthPrefixed(encKeyHash)
        out += QuickViewWire.lengthPrefixed(approvalID)
        out += QuickViewWire.lengthPrefixed(fieldManifestHash)
        out += QuickViewWire.i64(issuedAt)
        out += QuickViewWire.i64(expiresAt)
        return out
    }

    /// HKDF-Expand info for the AES-256-GCM key: `raw(PAYLOAD_MAGIC) ‖
    /// byte(version) ‖ raw("aead-key")`. Frozen — both the app (CryptoKit)
    /// and the browser (WebCrypto) MUST use these exact bytes or decryption
    /// fails.
    private static let payloadKeyRole = "aead-key"

    private static func payloadKeyInfo() -> Data {
        Data(payloadMagic.utf8) + QuickViewWire.byte(cryptoVersion) + Data(payloadKeyRole.utf8)
    }

    private static func derivedKey(sharedSecret: SharedSecret, kdfTranscript: Data) -> SymmetricKey {
        sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(SHA256.hash(data: kdfTranscript)),
            sharedInfo: payloadKeyInfo(),
            outputByteCount: 32)
    }

    /// Seal `plaintext` to `browserEncPublicKey` (x963-uncompressed P256
    /// point). `appEphemeralPrivateKey`/`nonce` are injectable seams for
    /// deterministic tests only — production callers omit both and get a
    /// fresh random key + nonce per call.
    static func seal(plaintext: Data,
                     browserEncPublicKey: Data,
                     browserEncKeyHash: Data,
                     browserSigKeyHash: Data,
                     sessionID: Data,
                     env: String,
                     approvalID: Data,
                     fieldManifestHash: Data,
                     issuedAt: Int64,
                     expiresAt: Int64,
                     appEphemeralPrivateKey: P256.KeyAgreement.PrivateKey = .init(),
                     nonce: AES.GCM.Nonce = AES.GCM.Nonce()) throws -> SealedPayload {
        guard let browserKey = try? P256.KeyAgreement.PublicKey(x963Representation: browserEncPublicKey) else {
            throw SealError.invalidBrowserKey
        }
        let appEphemeralPublicKey = appEphemeralPrivateKey.publicKey.x963Representation
        guard let sharedSecret = try? appEphemeralPrivateKey.sharedSecretFromKeyAgreement(with: browserKey) else {
            throw SealError.sealFailed
        }
        let transcript = kdfTranscript(sessionID: sessionID, browserEncKeyHash: browserEncKeyHash,
                                       browserSigKeyHash: browserSigKeyHash,
                                       appEphemeralPublicKey: appEphemeralPublicKey, env: env)
        let symmetricKey = derivedKey(sharedSecret: sharedSecret, kdfTranscript: transcript)
        let additionalData = aad(sessionID: sessionID, encKeyHash: browserEncKeyHash, approvalID: approvalID,
                                 fieldManifestHash: fieldManifestHash, issuedAt: issuedAt, expiresAt: expiresAt)
        guard let box = try? AES.GCM.seal(plaintext, using: symmetricKey, nonce: nonce,
                                          authenticating: additionalData) else {
            throw SealError.sealFailed
        }
        return SealedPayload(ciphertext: Data(nonce) + box.ciphertext + box.tag,
                             appEphemeralPublicKey: appEphemeralPublicKey)
    }

    /// Inverse of `seal` — used by tests to prove round-trip correctness
    /// with the counterpart (browser) private key. Production code never
    /// runs this path (the app only ever seals; the browser opens).
    static func open(_ sealed: SealedPayload,
                     browserEncPrivateKey: P256.KeyAgreement.PrivateKey,
                     browserEncKeyHash: Data,
                     browserSigKeyHash: Data,
                     sessionID: Data,
                     env: String,
                     approvalID: Data,
                     fieldManifestHash: Data,
                     issuedAt: Int64,
                     expiresAt: Int64) throws -> Data {
        guard let appEphemeralPublicKey = try? P256.KeyAgreement.PublicKey(
                x963Representation: sealed.appEphemeralPublicKey) else {
            throw OpenError.invalidKey
        }
        guard let sharedSecret = try? browserEncPrivateKey.sharedSecretFromKeyAgreement(with: appEphemeralPublicKey) else {
            throw OpenError.invalidKey
        }
        let transcript = kdfTranscript(sessionID: sessionID, browserEncKeyHash: browserEncKeyHash,
                                       browserSigKeyHash: browserSigKeyHash,
                                       appEphemeralPublicKey: sealed.appEphemeralPublicKey, env: env)
        let symmetricKey = derivedKey(sharedSecret: sharedSecret, kdfTranscript: transcript)
        let additionalData = aad(sessionID: sessionID, encKeyHash: browserEncKeyHash, approvalID: approvalID,
                                 fieldManifestHash: fieldManifestHash, issuedAt: issuedAt, expiresAt: expiresAt)
        guard sealed.ciphertext.count > nonceLength + 16 else { throw OpenError.malformedCiphertext }
        let nonceData = sealed.ciphertext.prefix(nonceLength)
        let rest = sealed.ciphertext.dropFirst(nonceLength)
        guard let box = try? AES.GCM.SealedBox(nonce: .init(data: nonceData),
                                               ciphertext: rest.dropLast(16),
                                               tag: rest.suffix(16)) else {
            throw OpenError.malformedCiphertext
        }
        guard let plaintext = try? AES.GCM.open(box, using: symmetricKey, authenticating: additionalData) else {
            throw OpenError.openFailed
        }
        return plaintext
    }
}
