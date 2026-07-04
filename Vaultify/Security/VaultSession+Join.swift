import Foundation

extension VaultSession {
    /// Join an EXISTING vault on a new device: adopt a Vault Key received via QR
    /// pairing or unwrapped from the synced recovery envelope, wrapping it under a
    /// locally-chosen master password (each device keeps its own password + salt).
    ///
    /// Deliberately does NO first-run seeding ("My Vault" folder / default identity)
    /// — the real content pulls from CloudKit, so seeding here would recreate the
    /// duplicate-seed merge problem this flow exists to avoid.
    ///
    /// When the user joined by typing the recovery key, pass it along so this device
    /// re-wraps the same key locally — the one Emergency Kit keeps working here too.
    func joinVault(vaultKey: [UInt8], masterPassword: String, recoveryKey: String? = nil) async throws {
        let salt = KeyHierarchy.newSalt()
        let params = KdfParams.standard
        let wrapped = try await Self.wrap(vaultKey: vaultKey,
                                          password: masterPassword,
                                          salt: salt, params: params)
        var bundle = VaultKeyBundle(version: VaultKeyBundle.currentVersion,
                                    createdAt: .now,
                                    kdfSalt: Data(salt), kdf: params,
                                    wrappedByPassword: wrapped,
                                    recoverySalt: nil, wrappedByRecovery: nil)
        if let recoveryKey {
            let recoverySalt = KeyHierarchy.newSalt()
            bundle.recoverySalt = Data(recoverySalt)
            bundle.wrappedByRecovery = try await Self.wrap(
                vaultKey: vaultKey,
                password: RecoveryKey.normalize(recoveryKey),
                salt: recoverySalt, params: params)
        }
        try bundle.save()
        adoptUnlocked(key: vaultKey)
    }
}
