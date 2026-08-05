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
        // Record the wrap profile: the password-path `kdf` can be re-tuned later,
        // but this envelope can only ever be opened with the params used right now.
        updated.recoveryKdf = bundle.kdf
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
            // The recovery envelope keeps the params from kit-generation time;
            // bundles predating `recoveryKdf` always shared the password-path
            // profile, so falling back to `kdf` is exact for them.
            keyBytes = try await Self.unwrap(wrapped: wrapped,
                                             password: RecoveryKey.normalize(recoveryKey),
                                             salt: Array(recoverySalt),
                                             params: bundle.recoveryKdf ?? bundle.kdf)
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
        // Extension-safe profile: the AutoFill extension must be able to run this
        // derivation under its memory budget (see `KdfParams.constrained`).
        let params = KdfParams.constrained
        let wrapped = try await Self.wrap(vaultKey: vaultKey, password: password, salt: salt, params: params)
        var updated = base
        if updated.wrappedByRecovery != nil, updated.recoveryKdf == nil {
            // The recovery envelope was wrapped under the pre-change profile;
            // record it BEFORE the password profile moves away from it, or the
            // paper recovery key stops unwrapping.
            updated.recoveryKdf = updated.kdf
        }
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
        // The Extra Protection key is destroyed alongside the Vault Key: the wrap
        // it belonged to is being wiped, so a surviving Face-ID-releasable copy
        // could only hand out a key with nothing left to open.
        Level2BiometricKeyStore.delete()
        settings.biometricUnlockEnabled = false
        settings.onboardingCompleted = false
        // Full re-onboarding replays the story intro (and drops any pending
        // arrival-bridge hint from the previous vault's run).
        settings.storyIntroCompleted = false
        settings.storyIntroWantsFirstItem = false
        lockToOnboarding()
    }
}
