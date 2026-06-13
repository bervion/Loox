import Foundation

extension VaultSession {
    /// Generate an Emergency Kit recovery key and add a recovery unlock path that
    /// wraps the current Vault Key. Returns the display key (show once, then forget).
    func generateRecoveryKit() async throws -> String {
        guard let vaultKey, let bundle = VaultKeyBundle.load() else { throw AuthError.locked }
        let display = RecoveryKey.generate()
        let salt = KeyHierarchy.newSalt()
        var keyBytes = vaultKey.bytes
        defer { secureZero(&keyBytes) }
        let wrapped = try await Self.wrap(vaultKey: keyBytes,
                                          password: RecoveryKey.normalize(display),
                                          salt: salt, params: bundle.kdf)
        var updated = bundle
        updated.recoverySalt = Data(salt)
        updated.wrappedByRecovery = wrapped
        try updated.save()
        return display
    }

    var hasRecoveryKit: Bool { VaultKeyBundle.load()?.wrappedByRecovery != nil }

    /// Recover using the Emergency Kit key and set a new master password.
    func recover(recoveryKey: String, newPassword: String) async throws {
        guard let bundle = VaultKeyBundle.load(),
              let wrapped = bundle.wrappedByRecovery,
              let recoverySalt = bundle.recoverySalt else { throw AuthError.recoveryFailed }
        var keyBytes: [UInt8]
        do {
            keyBytes = try await Self.unwrap(wrapped: wrapped,
                                             password: RecoveryKey.normalize(recoveryKey),
                                             salt: Array(recoverySalt), params: bundle.kdf)
        } catch {
            throw AuthError.recoveryFailed
        }
        defer { secureZero(&keyBytes) }
        try await rewrapWithPassword(newPassword, vaultKey: keyBytes, base: bundle)
        adoptUnlocked(key: keyBytes)
    }

    /// Re-key the master-password path after verifying the current password.
    func changeMasterPassword(current: String, new: String) async throws {
        guard let bundle = VaultKeyBundle.load() else { throw AuthError.noVault }
        var keyBytes: [UInt8]
        do {
            keyBytes = try await Self.unwrap(wrapped: bundle.wrappedByPassword,
                                             password: current,
                                             salt: Array(bundle.kdfSalt), params: bundle.kdf)
        } catch {
            throw AuthError.wrongPassword
        }
        defer { secureZero(&keyBytes) }
        try await rewrapWithPassword(new, vaultKey: keyBytes, base: bundle)
    }

    private func rewrapWithPassword(_ password: String, vaultKey: [UInt8], base: VaultKeyBundle) async throws {
        let salt = KeyHierarchy.newSalt()
        let params = KdfParams.standard
        let wrapped = try await Self.wrap(vaultKey: vaultKey, password: password, salt: salt, params: params)
        var updated = base
        updated.kdfSalt = Data(salt)
        updated.kdf = params
        updated.wrappedByPassword = wrapped
        try updated.save()
    }

    /// Destroy all key material and reset to onboarding. The caller must also
    /// erase the encrypted data store.
    func resetVault() {
        VaultKeyBundle.wipe()
        BiometricKeyStore.delete()
        settings.biometricUnlockEnabled = false
        settings.onboardingCompleted = false
        lockToOnboarding()
    }
}
