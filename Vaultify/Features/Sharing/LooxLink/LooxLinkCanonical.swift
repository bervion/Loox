import CryptoKit
import Foundation

/// Canonical request binding for the App Attest assertion on create-share:
/// a length-prefixed **big-endian binary** transcript (NOT JSON) so Swift and
/// the Worker hash byte-identical transcripts. Layout is frozen (V2) and
/// parity-tested against `app-attest-create-share-vectors-v2.json` — never
/// change it without a new version tag on both sides. V2 = V1 layout plus
/// `byte(one_time ? 1 : 0)` appended as the FINAL field, so the burn-after-read
/// flag is covered by the assertion (an omitted `one_time` in the wire body
/// means false). The verifier accepts V1 only while in shadow; required is
/// V2-only.
///
/// Layout:
///     magic (UTF-8, no length prefix)
///     u16 len ‖ method (uppercased)     u16 len ‖ path     u16 len ‖ challengeId
///     SHA-256(ciphertextRaw)  (32 bytes, no length prefix)
///     u16 len ‖ ivRaw
///     u32 cryptoVersion       u64 expiresInSeconds
///     u32 len ‖ envelopeRaw   (length 0 when absent)
///     byte oneTime (0/1)
nonisolated enum LooxLinkCanonical {
    static let magic = "LOOX-APP-ATTEST-CREATE-SHARE-V2"
    static let createShareMethod = "POST"
    static let createSharePath = "/v1/shares"

    static func transcript(method: String, path: String, challengeId: String,
                           ciphertext: Data, iv: Data, cryptoVersion: UInt32,
                           expiresInSeconds: UInt64, envelope: Data?, oneTime: Bool) -> Data {
        func u16(_ n: Int) -> Data { var v = UInt16(n).bigEndian; return Data(bytes: &v, count: 2) }
        func u32(_ n: UInt32) -> Data { var v = n.bigEndian; return Data(bytes: &v, count: 4) }
        func u64(_ n: UInt64) -> Data { var v = n.bigEndian; return Data(bytes: &v, count: 8) }
        func lengthPrefixed(_ s: String) -> Data { let d = Data(s.utf8); return u16(d.count) + d }

        var out = Data(magic.utf8)
        out += lengthPrefixed(method.uppercased())
        out += lengthPrefixed(path)
        out += lengthPrefixed(challengeId)
        out += Data(SHA256.hash(data: ciphertext))
        out += u16(iv.count) + iv
        out += u32(cryptoVersion)
        out += u64(expiresInSeconds)
        let env = envelope ?? Data()
        out += u32(UInt32(env.count)) + env
        out += Data([oneTime ? 1 : 0])
        return out
    }

    /// `clientDataHash` for `generateAssertion` on create-share.
    static func requestHash(method: String = createShareMethod,
                            path: String = createSharePath,
                            challengeId: String,
                            ciphertext: Data, iv: Data, cryptoVersion: UInt32,
                            expiresInSeconds: UInt64, envelope: Data?, oneTime: Bool) -> Data {
        Data(SHA256.hash(data: transcript(
            method: method, path: path, challengeId: challengeId,
            ciphertext: ciphertext, iv: iv, cryptoVersion: cryptoVersion,
            expiresInSeconds: expiresInSeconds, envelope: envelope, oneTime: oneTime)))
    }
}
