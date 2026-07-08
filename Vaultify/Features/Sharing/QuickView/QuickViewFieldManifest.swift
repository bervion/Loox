import CryptoKit
import Foundation

/// Shared big-endian, length-prefixed transcript primitives for EVERY Quick
/// View signed/authenticated artifact (field manifest hash, session-envelope
/// transcript, KDF transcript, AAD). Deliberately mirrors `LooxLinkCanonical`'s
/// inline closure convention (u16/u32/u64 big-endian, blobs u32-length-
/// prefixed) rather than `VaultifyCore`'s `CanonicalWriter` — F5: pick ONE
/// dialect for every Quick View transcript and never mix it with
/// `CanonicalWriter`'s. Kept as one small shared enum (not re-duplicated
/// per-file) so the dialect can only drift in one place.
nonisolated enum QuickViewWire {
    static func byte(_ value: UInt8) -> Data { Data([value]) }

    static func u32(_ value: Int) -> Data {
        var v = UInt32(truncatingIfNeeded: value).bigEndian
        return Data(bytes: &v, count: 4)
    }

    static func u64(_ value: UInt64) -> Data {
        var v = value.bigEndian
        return Data(bytes: &v, count: 8)
    }

    static func i64(_ value: Int64) -> Data { u64(UInt64(bitPattern: value)) }

    /// u32(len) ‖ bytes — the blob convention used for every string/hash
    /// field so a value's own bytes can never be mistaken for a length.
    static func lengthPrefixed(_ data: Data) -> Data { u32(data.count) + data }
    static func lengthPrefixed(_ string: String) -> Data { lengthPrefixed(Data(string.utf8)) }

    /// base64url (no padding) — the wire encoding the backend uses for every
    /// binary envelope field (session_id, key hashes, nonces): the live
    /// `/sessions` response and the `/open` reference client both use base64url,
    /// so the app MUST decode base64url (NOT hex — hex would fail on `-`/`_`).
    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64URLDecode(_ string: String) -> Data? {
        var b64 = string.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64.append("=") }
        return Data(base64Encoded: b64)
    }
}

/// Structural field-manifest hasher — `LOOX-QV-FIELD-MANIFEST-V1`
/// (DEC-QV-FIELD-01 / INV-QV-25). Hashes STRUCTURE only (`count` + per-field
/// `[stableID, kind, concealed, ordinal]`) over the FINAL ordered field array
/// (persisted approved fields in deterministic envelope order THEN virtual
/// fields, V1 `currentTOTP` last) — never secret values. AES-GCM already
/// guarantees ciphertext integrity; hashing values here would duplicate that
/// job and risk logging a derived hash of a secret.
nonisolated enum QuickViewFieldManifest {
    static let magic = "LOOX-QV-FIELD-MANIFEST-V1"

    /// - Parameter orderedFields: the FINAL array, already in frozen order
    ///   (persisted fields, then virtual fields). Callers must not reorder
    ///   after this call — the hash is a function of array position.
    static func hash(orderedFields: [QuickViewApprovedField]) -> Data {
        var transcript = Data(magic.utf8)
        transcript += QuickViewWire.u32(orderedFields.count)
        for (ordinal, field) in orderedFields.enumerated() {
            transcript += QuickViewWire.lengthPrefixed(field.stableID)
            transcript += QuickViewWire.lengthPrefixed(field.kind.rawValue)
            transcript += QuickViewWire.byte(field.concealed ? 1 : 0)
            transcript += QuickViewWire.u32(ordinal)
        }
        return Data(SHA256.hash(data: transcript))
    }
}
