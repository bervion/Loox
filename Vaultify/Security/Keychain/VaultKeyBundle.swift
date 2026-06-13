import Foundation

/// The wrapped-key envelope persisted in the Keychain. Holds the Vault Key
/// sealed under each available unlock path. The plaintext Vault Key is never
/// persisted — only these wrapped copies plus the salts/params to reproduce
/// the wrapping keys.
nonisolated struct VaultKeyBundle: Codable, Sendable {
    var version: Int
    var createdAt: Date

    /// Argon2id salt + params for the master-password path.
    var kdfSalt: Data
    var kdf: KdfParams
    /// AES-256-GCM(VaultKey) under the password-derived KEK.
    var wrappedByPassword: Data

    /// Recovery (Emergency Kit) path — independent salt + wrapped key.
    var recoverySalt: Data?
    var wrappedByRecovery: Data?

    /// Level-2 (extra protection) path: random Level-2 Secret Key wrapped by an
    /// Argon2id key derived from the app-wide Level-2 password. Optional →
    /// backward-compatible with vaults created before this feature.
    var l2Salt: Data?
    var l2Kdf: KdfParams?
    var wrappedL2SK: Data?

    static let currentVersion = 1

    /// Stored as ciphertext in the shared App Group container (with complete
    /// file protection) so the AutoFill extension can read it after the user
    /// authenticates. The wrapped keys are useless without the master password.
    static func load() -> VaultKeyBundle? {
        guard let data = try? Data(contentsOf: SharedConfig.keyBundleURL) else { return nil }
        return try? JSONDecoder().decode(VaultKeyBundle.self, from: data)
    }

    func save() throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: SharedConfig.keyBundleURL, options: [.atomic, .completeFileProtection])
    }

    static func wipe() { try? FileManager.default.removeItem(at: SharedConfig.keyBundleURL) }

    /// Whether a vault has been provisioned on this device.
    static var exists: Bool { FileManager.default.fileExists(atPath: SharedConfig.keyBundleURL.path) }
}
