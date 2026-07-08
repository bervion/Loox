import CryptoKit
import Foundation

/// Canonical wire body + App Attest assertion transcript for the Quick View
/// upload endpoint — `LOOX-APP-ATTEST-QUICK-VIEW-V1` (BE-parity proven,
/// frozen vectors `VaultifyTests/Fixtures/quick-view-upload-assertion-vectors-v1.json`).
///
/// Uses the u16-length-prefixed framing style of loox-link's
/// `shortenRequestHash` (method/path/challengeId are text fields, session_id
/// is a raw-byte field, and the encrypted body is folded in as a single
/// SHA-256 digest rather than inlined). Domain separation for this artifact
/// comes from the endpoint path itself being bound into the transcript — NO
/// magic byte-string prefix (unlike the create-share/shorten-link families):
/// this transcript structurally begins with `u16(len)` (first byte `0x00`)
/// while every magic-prefixed family begins with ASCII `'L'` (`0x4C`), so the
/// two can never collide.
nonisolated enum QuickViewCanonical {
    static let uploadMethod = "POST"

    /// Endpoint path is pinned INSIDE the assertion transcript — a path
    /// change post-freeze breaks attestation (the shorten-link lesson). Kept
    /// as a single function referenced by both the API client and the
    /// transcript builder so it can only drift in one place.
    static func uploadPath(sessionID: String) -> String {
        "\(QuickViewConfig.servicePathPrefix)/sessions/\(sessionID)/payload"
    }

    /// `canonicalUploadBody = blob(aad) ‖ blob(ciphertext) ‖ blob(app_eph_pub)`
    /// — `ciphertext` here is the FULL opaque wire blob (12-byte nonce ‖
    /// AES-GCM ciphertext ‖ tag; see `QuickViewPayloadSealer.SealedPayload`),
    /// and `aad` is `QuickViewPayloadSealer.aad(...)`'s output bytes.
    static func canonicalUploadBody(aad: Data, ciphertext: Data, appEphemeralPublicKey: Data) -> Data {
        var out = QuickViewWire.lengthPrefixed(aad)
        out += QuickViewWire.lengthPrefixed(ciphertext)
        out += QuickViewWire.lengthPrefixed(appEphemeralPublicKey)
        return out
    }

    /// `clientData = u16len(method) ‖ method(uppercased) ‖ u16len(path) ‖
    ///   path ‖ u16len(challengeId) ‖ challengeId ‖ u16len(session_id) ‖
    ///   session_id(raw bytes) ‖ SHA256(canonicalUploadBody)` (fixed 32
    ///   bytes, no length prefix). `session_id` is the hex-DECODED bytes
    ///   (`QuickViewSessionEnvelope.sessionIDBytes`), never the hex string's
    ///   own UTF-8 bytes.
    static func assertionClientData(method: String = uploadMethod, path: String,
                                    challengeID: String, sessionIDBytes: Data,
                                    uploadBody: Data) -> Data {
        var out = u16LengthPrefixed(method.uppercased())
        out += u16LengthPrefixed(path)
        out += u16LengthPrefixed(challengeID)
        out += u16LengthPrefixed(sessionIDBytes)
        out += Data(SHA256.hash(data: uploadBody))
        return out
    }

    /// `clientDataHash` for `generateAssertion` on the upload — SHA-256 of
    /// `assertionClientData`.
    static func assertionClientDataHash(method: String = uploadMethod, path: String,
                                        challengeID: String, sessionIDBytes: Data,
                                        uploadBody: Data) -> Data {
        Data(SHA256.hash(data: assertionClientData(
            method: method, path: path, challengeID: challengeID,
            sessionIDBytes: sessionIDBytes, uploadBody: uploadBody)))
    }

    /// u16 (big-endian) length-prefixed framing — distinct from the u32
    /// `blob`/`string` convention `QuickViewWire` uses everywhere else; this
    /// ONE transcript mirrors loox-link's `shortenRequestHash` byte layout.
    private static func u16LengthPrefixed(_ data: Data) -> Data {
        var length = UInt16(data.count).bigEndian
        return Data(bytes: &length, count: 2) + data
    }

    private static func u16LengthPrefixed(_ string: String) -> Data {
        u16LengthPrefixed(Data(string.utf8))
    }
}
