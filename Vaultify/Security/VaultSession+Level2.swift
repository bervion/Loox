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

    /// What a restore did with the backup's Level-2 wrap. Adoption is silent by
    /// nature — it writes a Keychain bundle nobody sees — and each outcome leaves
    /// the user in a different place, so the caller has to be able to say which.
    nonisolated enum Level2AdoptionResult: Equatable, Sendable {
        /// This device had no Extra Password and now carries the backup's wrap,
        /// so its sealed fields open with the password that backup was made with.
        case adopted
        /// This device already has its own Extra Password. Its wrap is kept, and
        /// every level2-sealed field in the backup stays permanently unopenable —
        /// a successful-looking import that stranded data.
        case skippedDeviceHasOwnWrap
        /// The wrap was not fit to persist: out-of-policy Argon2 parameters, a
        /// salt too short for Argon2, an empty wrap, or no key bundle to write
        /// into. Nothing was changed, and the sealed fields do not open.
        case refusedInvalidPolicy
    }

    /// Restore path: adopt a backup's Level-2 wrap when this device has none —
    /// without it, restored level2-sealed fields could never be opened again.
    /// Never overwrites an existing wrap (the local Extra Password keeps working;
    /// fields sealed under a DIFFERENT L2SK stay unreadable either way, and
    /// clobbering the local wrap would break this device's own sealed fields).
    ///
    /// The result is not optional to ignore: both non-adopting outcomes leave
    /// imported sealed fields unreadable, and the user only finds out days later
    /// unless the caller tells them.
    func adoptLevel2WrapIfAbsent(wrappedL2SK: Data, salt: Data,
                                 kdf: KdfParams) -> Level2AdoptionResult {
        let bundle = VaultKeyBundle.load()
        let outcome = Self.level2Adoption(for: bundle, wrappedL2SK: wrappedL2SK, salt: salt, kdf: kdf)
        guard outcome == .adopted, let bundle,
              let updated = Self.level2AdoptedBundle(from: bundle, wrappedL2SK: wrappedL2SK,
                                                     salt: salt, kdf: kdf)
        else { return outcome }
        do {
            try updated.save()
        } catch {
            // Nothing persisted, so nothing was adopted — reporting success here
            // would be the same silent stranding this result type exists to end.
            return .refusedInvalidPolicy
        }
        // The wrap just adopted is FOREIGN. Any biometric L2SK on this device
        // belongs to whatever wrap used to be here and would decrypt nothing, so
        // it is dead weight that can only release a useless key.
        Level2BiometricKeyStore.delete()
        return .adopted
    }

    /// Pure decision step, so the outcome can be reasoned about (and tested)
    /// without a provisioned key bundle on disk. `base` is nil when this device
    /// has no vault at all, which is not an adoptable state either.
    nonisolated static func level2Adoption(for base: VaultKeyBundle?, wrappedL2SK: Data,
                                           salt: Data, kdf: KdfParams) -> Level2AdoptionResult {
        guard isAdoptableLevel2Wrap(wrappedL2SK: wrappedL2SK, salt: salt, kdf: kdf) else {
            return .refusedInvalidPolicy
        }
        guard let base else { return .refusedInvalidPolicy }
        guard base.wrappedL2SK == nil else { return .skippedDeviceHasOwnWrap }
        return .adopted
    }

    /// Whether a Level-2 wrap read from a backup may be written into this
    /// device's key bundle at all.
    ///
    /// The bundle is the app's OWN state: once these parameters are persisted,
    /// every later reveal of a protected field derives with them, with no
    /// attacker file in play. Turning Extra Protection off requires the password
    /// that wrap belongs to, so the user cannot undo a bad adoption.
    nonisolated static func isAdoptableLevel2Wrap(wrappedL2SK: Data, salt: Data,
                                                  kdf: KdfParams) -> Bool {
        // An empty wrap would still make `hasLevel2` true forever while no
        // password could ever open it.
        !wrappedL2SK.isEmpty && KdfParams.isAcceptableSalt(salt) && kdf.isWithinPolicy
    }

    /// Pure adoption step: `base` carrying the backup's Level-2 wrap, or nil when
    /// this device already has one or the wrap is not fit to persist. Internal
    /// (not private) so tests can exercise the never-overwrite and policy rules
    /// without a provisioned key bundle on disk.
    nonisolated static func level2AdoptedBundle(from base: VaultKeyBundle, wrappedL2SK: Data,
                                                salt: Data, kdf: KdfParams) -> VaultKeyBundle? {
        guard base.wrappedL2SK == nil else { return nil }
        guard isAdoptableLevel2Wrap(wrappedL2SK: wrappedL2SK, salt: salt, kdf: kdf) else { return nil }
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
