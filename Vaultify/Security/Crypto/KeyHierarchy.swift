import Foundation

/// Derives the key-encryption key (KEK) from a passphrase via Argon2id and
/// wraps/unwraps the random 256-bit Vault Key with it (AES-256-GCM).
///
/// The Vault Key is the root secret that encrypts every item payload. It is
/// generated once at vault creation and only ever stored *wrapped* — by the
/// password-derived KEK, by a recovery-key-derived KEK, and/or by the Secure
/// Enclave (biometric path).
nonisolated enum KeyHierarchy {
    static let vaultKeyLength = 32

    static func newVaultKey() -> [UInt8] { CryptoRandom.bytes(vaultKeyLength) }
    static func newSalt() -> [UInt8] { CryptoRandom.bytes(16) }

    /// KEK = Argon2id(passphrase, salt, params). Heavy — run off the main actor.
    static func deriveKEK(passphrase: String, salt: [UInt8], params: KdfParams) throws -> [UInt8] {
        try Argon2.deriveRaw(password: passphrase, salt: salt, params: params, length: 32)
    }

    /// Wrap `vaultKey` under a passphrase-derived KEK.
    static func wrap(vaultKey: [UInt8],
                     passphrase: String,
                     salt: [UInt8],
                     params: KdfParams) throws -> Data {
        var kek = try deriveKEK(passphrase: passphrase, salt: salt, params: params)
        defer { secureZero(&kek) }
        return try AESGCM.seal(Data(vaultKey), key: kek)
    }

    /// Recover `vaultKey` from a wrapped blob using the passphrase. Throws if the
    /// passphrase is wrong (GCM authentication fails).
    static func unwrap(wrapped: Data,
                       passphrase: String,
                       salt: [UInt8],
                       params: KdfParams) throws -> [UInt8] {
        var kek = try deriveKEK(passphrase: passphrase, salt: salt, params: params)
        defer { secureZero(&kek) }
        return Array(try AESGCM.open(wrapped, key: kek))
    }
}
