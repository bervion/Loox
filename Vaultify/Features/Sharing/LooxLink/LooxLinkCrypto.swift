import CryptoKit
import Foundation

/// On-device encryption result for one Loox Link share. The server only ever
/// sees `ciphertextB64` + `ivB64`; `fragmentKey` goes exclusively into the URL
/// fragment (`#k=…`), which browsers never send in HTTP requests.
nonisolated struct LooxLinkCiphertext: Sendable {
    /// base64( ciphertext ‖ 16-byte GCM tag ) — the Web Crypto layout the viewer expects.
    let ciphertextB64: String
    /// base64( 12-byte nonce ).
    let ivB64: String
    /// base64url( raw 32-byte content key ), no padding.
    let fragmentKey: String

    /// Raw (pre-base64) bytes, needed by the canonical request binding.
    let ciphertextRaw: Data
    let ivRaw: Data
}

nonisolated enum LooxLinkCrypto {
    /// AES-256-GCM with a fresh random key and fresh 12-byte nonce per share.
    static func encrypt(_ envelope: Data) throws -> LooxLinkCiphertext {
        let key = SymmetricKey(size: .bits256)
        let nonce = AES.GCM.Nonce()
        let box = try AES.GCM.seal(envelope, using: key, nonce: nonce)
        let ctPlusTag = box.ciphertext + box.tag
        let rawKey = key.withUnsafeBytes { Data($0) }
        return LooxLinkCiphertext(
            ciphertextB64: ctPlusTag.base64EncodedString(),
            ivB64: Data(nonce).base64EncodedString(),
            fragmentKey: base64url(rawKey),
            ciphertextRaw: ctPlusTag,
            ivRaw: Data(nonce))
    }

    /// Inverse of `encrypt`, used by tests to prove viewer-compatibility of the
    /// wire layout (tag appended, standard base64 body, base64url fragment key).
    static func decrypt(ciphertextB64: String, ivB64: String, fragmentKey: String) throws -> Data {
        guard let ctPlusTag = Data(base64Encoded: ciphertextB64), ctPlusTag.count > 16,
              let iv = Data(base64Encoded: ivB64),
              let rawKey = base64urlDecode(fragmentKey), rawKey.count == 32 else {
            throw CryptoKitError.authenticationFailure
        }
        let box = try AES.GCM.SealedBox(nonce: .init(data: iv),
                                        ciphertext: ctPlusTag.dropLast(16),
                                        tag: ctPlusTag.suffix(16))
        return try AES.GCM.open(box, using: SymmetricKey(data: rawKey))
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64urlDecode(_ string: String) -> Data? {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }
}
