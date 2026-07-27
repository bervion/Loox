import Foundation

/// App-wide Level-2 ("extra protection") password management. The Level-2 Secret
/// Key (L2SK) is random and wrapped by an Argon2id key from the Level-2 password,
/// so the password can change without re-encrypting protected fields.
///
/// Biometrics: when the vault's own biometric unlock is on, the L2SK is ALSO
/// stored behind `.biometryCurrentSet` (`Level2BiometricKeyStore`) so a protected
/// field can be opened with Face ID instead of retyping the Extra Password. The
/// typed password always keeps working — biometrics are a shortcut, never the
/// only way in. There is no separate toggle: the Extra Password rides the vault's
/// `biometricUnlockEnabled` setting, which means that on such a device the second
/// factor collapses into the same factor that opens the vault.
extension VaultSession {
    var hasLevel2: Bool { VaultKeyBundle.load()?.wrappedL2SK != nil }
    var isLevel2Unlocked: Bool { level2Key != nil }

    /// Whether Face ID can release the L2SK right now, WITHOUT raising a prompt —
    /// so the UI can decide what to offer before the user commits to anything.
    /// All three conditions matter: a provisioned item, a Level-2 wrap that item
    /// belongs to, and the vault biometric setting this feature is bound to.
    var isLevel2BiometricEnrolled: Bool {
        settings.biometricUnlockEnabled && hasLevel2 && Level2BiometricKeyStore.isEnrolled
    }

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
        enrolLevel2Biometrics(l2sk)
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
            throw AuthError.wrongExtraPassword
        }
        defer { secureZero(&l2sk) }
        setLevel2Key(l2sk)
        // The only moment an ALREADY-established Extra Password user proves the
        // password, so it is the only point at which they can be enrolled. Without
        // it, biometric Level-2 would reach new passwords only.
        enrolLevel2Biometrics(l2sk)
    }

    /// Release the L2SK with Face ID / Touch ID. Mirrors `unlockWithBiometrics()`
    /// and throws the underlying `Level2BiometricKeyStore.Failure` unchanged so
    /// callers can tell a dismissed prompt from a rejected face.
    ///
    /// `Level2BiometricKeyStore.retrieve` raises the system prompt itself, so the
    /// outcome is reported to the app-wide policy here rather than routed through
    /// `requireBiometrics` (which would prompt a second time).
    func unlockLevel2WithBiometrics() async throws {
        do {
            var l2sk = try await Level2BiometricKeyStore.retrieve(
                reason: appString("Unlock protected fields"))
            defer { secureZero(&l2sk) }
            setLevel2Key(l2sk)
        } catch {
            noteBiometricOutcome(error)
            throw error
        }
    }

    /// Turn Extra Protection off entirely. The caller must have already
    /// unsealed every `.level2` field back to plaintext — after this the L2SK
    /// is gone for good and any remaining sealed payload is unrecoverable.
    func removeLevel2Wrap() {
        // Unconditional and FIRST: turning protection off must not leave a
        // Face-ID-releasable copy of the key behind, even on a device whose key
        // bundle failed to load.
        Level2BiometricKeyStore.delete()
        guard var bundle = VaultKeyBundle.load() else { clearLevel2Key(); return }
        bundle.wrappedL2SK = nil
        bundle.l2Salt = nil
        bundle.l2Kdf = nil
        try? bundle.save()
        clearLevel2Key()
    }

    /// Restore path: adopt a backup's Level-2 wrap when this device has none —
    /// without it, restored level2-sealed fields could never be opened again.
    /// Never overwrites an existing wrap (the local Extra Password keeps working;
    /// fields sealed under a DIFFERENT L2SK stay unreadable either way, and
    /// clobbering the local wrap would break this device's own sealed fields).
    func adoptLevel2WrapIfAbsent(wrappedL2SK: Data, salt: Data, kdf: KdfParams) {
        guard let bundle = VaultKeyBundle.load(),
              let updated = Self.level2AdoptedBundle(from: bundle, wrappedL2SK: wrappedL2SK,
                                                     salt: salt, kdf: kdf)
        else { return }
        try? updated.save()
        // The wrap just adopted is FOREIGN. Any biometric L2SK on this device
        // belongs to whatever wrap used to be here and would decrypt nothing, so
        // it is dead weight that can only release a useless key.
        Level2BiometricKeyStore.delete()
    }

    /// Pure adoption step: `base` carrying the backup's Level-2 wrap, or nil when
    /// this device already has one. Internal (not private) so tests can exercise
    /// the never-overwrite rule without a provisioned key bundle on disk.
    nonisolated static func level2AdoptedBundle(from base: VaultKeyBundle, wrappedL2SK: Data,
                                                salt: Data, kdf: KdfParams) -> VaultKeyBundle? {
        guard base.wrappedL2SK == nil else { return nil }
        var updated = base
        updated.wrappedL2SK = wrappedL2SK
        updated.l2Salt = salt
        updated.l2Kdf = kdf
        return updated
    }

    /// Re-key the Level-2 password (verifies current, re-wraps the same L2SK).
    /// Leaves Level-2 LOCKED: proving the current password here is a verification
    /// step, not a request to open every protected field in the app.
    func changeLevel2Password(current: String, new: String) async throws {
        try await unlockLevel2(password: current)
        defer { clearLevel2Key() }
        guard var bundle = VaultKeyBundle.load(), let key = level2Key else { throw AuthError.noVault }
        var l2sk = key.bytes
        defer { secureZero(&l2sk) }
        let salt = KeyHierarchy.newSalt()
        let params = KdfParams.standard
        bundle.l2Salt = Data(salt)
        bundle.l2Kdf = params
        bundle.wrappedL2SK = try await Self.wrap(vaultKey: l2sk, password: new, salt: salt, params: params)
        try bundle.save()
        // The L2SK itself is unchanged — only its wrap is — so this is a cheap
        // re-store that keeps the keychain item fresh under `.biometryCurrentSet`.
        enrolLevel2Biometrics(l2sk)
    }

    /// Provision the biometric L2SK whenever the plaintext key is legitimately in
    /// hand and the vault's own biometric unlock is on.
    ///
    /// Best-effort by design: a Keychain failure must never break setting or
    /// changing the Extra Password. The typed password stays the source of truth,
    /// so the worst case is simply that Face ID is not offered.
    private func enrolLevel2Biometrics(_ l2sk: [UInt8]) {
        guard settings.biometricUnlockEnabled else { return }
        try? Level2BiometricKeyStore.store(level2Key: l2sk)
    }
}
