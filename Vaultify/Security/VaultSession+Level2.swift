import Foundation

/// App-wide Level-2 ("extra protection") password management. The Level-2 Secret
/// Key (L2SK) is random and wrapped by an Argon2id key from the Level-2 password,
/// so the password can change without re-encrypting protected fields.
extension VaultSession {
    var hasLevel2: Bool { VaultKeyBundle.load()?.wrappedL2SK != nil }
    var isLevel2Unlocked: Bool { level2Key != nil }

    /// Create the Level-2 password (first time). Leaves Level-2 unlocked.
    func setLevel2Password(_ password: String) async throws {
        guard var bundle = VaultKeyBundle.load() else { throw AuthError.noVault }
        var l2sk = CryptoRandom.bytes(32)
        defer { secureZero(&l2sk) }
        let salt = KeyHierarchy.newSalt()
        let params = KdfParams.standard
        let wrapped = try await Self.wrap(vaultKey: l2sk, password: password, salt: salt, params: params)
        bundle.l2Salt = Data(salt)
        bundle.l2Kdf = params
        bundle.wrappedL2SK = wrapped
        try bundle.save()
        setLevel2Key(l2sk)
    }

    /// Unlock Level-2 for this session (so `level2`-protected fields can be revealed).
    func unlockLevel2(password: String) async throws {
        guard let bundle = VaultKeyBundle.load(),
              let wrapped = bundle.wrappedL2SK, let salt = bundle.l2Salt, let kdf = bundle.l2Kdf
        else { throw AuthError.noVault }
        var l2sk: [UInt8]
        do {
            l2sk = try await Self.unwrap(wrapped: wrapped, password: password, salt: Array(salt), params: kdf)
        } catch {
            throw AuthError.wrongPassword
        }
        defer { secureZero(&l2sk) }
        setLevel2Key(l2sk)
    }

    /// Re-key the Level-2 password (verifies current, re-wraps the same L2SK).
    func changeLevel2Password(current: String, new: String) async throws {
        try await unlockLevel2(password: current)
        guard var bundle = VaultKeyBundle.load(), let key = level2Key else { throw AuthError.noVault }
        var l2sk = key.bytes
        defer { secureZero(&l2sk) }
        let salt = KeyHierarchy.newSalt()
        let params = KdfParams.standard
        bundle.l2Salt = Data(salt)
        bundle.l2Kdf = params
        bundle.wrappedL2SK = try await Self.wrap(vaultKey: l2sk, password: new, salt: salt, params: params)
        try bundle.save()
    }
}
