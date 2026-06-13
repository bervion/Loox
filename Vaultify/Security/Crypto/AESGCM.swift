import Foundation
import CryptoKit

/// AES-256-GCM sealing helpers.
///
/// The combined output layout is `nonce(12) || ciphertext || tag(16)` as
/// produced by CryptoKit's `AES.GCM.SealedBox.combined`.
nonisolated enum AESGCM {
    enum Failure: Error { case invalidKeyLength, sealFailed }

    static func seal(_ plaintext: Data, key: [UInt8]) throws -> Data {
        guard key.count == 32 else { throw Failure.invalidKeyLength }
        let box = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key))
        guard let combined = box.combined else { throw Failure.sealFailed }
        return combined
    }

    static func open(_ combined: Data, key: [UInt8]) throws -> Data {
        guard key.count == 32 else { throw Failure.invalidKeyLength }
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: SymmetricKey(data: key))
    }

    static func seal(_ plaintext: Data, key: SecureBytes) throws -> Data {
        try key.withUnsafeBytes { try seal(plaintext, key: Array($0)) }
    }

    static func open(_ combined: Data, key: SecureBytes) throws -> Data {
        try key.withUnsafeBytes { try open(combined, key: Array($0)) }
    }
}
