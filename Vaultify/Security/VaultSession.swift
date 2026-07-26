import Foundation
import os

/// Diagnostic logger for biometric-key migration to the shared keychain group.
/// Filter Console by subsystem `com.bervion.vaultify`, category `biometric`. Non-sensitive only.
private let biometricLog = Logger(subsystem: "com.bervion.vaultify", category: "biometric")

/// Diagnostic logger for the KDF-profile re-wrap of the key bundle. Boolean
/// outcomes only — never salts, params-with-context, or wrap material.
private let kdfLog = Logger(subsystem: "com.bervion.vaultify", category: "kdf")

enum AuthError: Error, LocalizedError {
    case noVault, wrongPassword, locked, biometricFailed, recoveryFailed

    var errorDescription: String? {
        switch self {
        case .noVault: return appString("No vault found on this device.")
        case .wrongPassword: return appString("Incorrect master password.")
        case .locked: return appString("The vault is locked.")
        case .biometricFailed: return appString("Biometric unlock failed.")
        case .recoveryFailed: return appString("That recovery key didn’t work.")
        }
    }
}

/// Owns the vault lock lifecycle and the in-memory Vault Key. The plaintext key
/// exists only while `state == .unlocked`; `lock()` drops it (zeroising memory).
@MainActor @Observable final class VaultSession {
    enum State: Equatable { case onboarding, locked, unlocked }

    private(set) var state: State
    /// Present iff unlocked. Read by the repository to seal/open item payloads.
    private(set) var vaultKey: SecureBytes?
    /// App-wide Level-2 Secret Key (extra protection). Present only after a
    /// Level-2 unlock this session; cleared on lock.
    private(set) var level2Key: SecureBytes?
    /// Timestamp of last user activity — drives foreground inactivity auto-lock.
    var lastActivity: Date = .now
    /// When the app last entered the background. Drives the scene-based auto-lock on return.
    /// `nil` while in the foreground. Crucially, the Face ID system prompt only drives the app
    /// to `.inactive` (never `.background`), so it never sets this — preventing a re-lock /
    /// re-prompt loop when the biometric sheet closes.
    private var backgroundedAt: Date?
    /// True when the last lock was a deliberate user action (panic shake or the
    /// Settings "Lock Now" button). The lock screen reads this to require a
    /// slide-to-unlock before any Face ID prompt — a deliberate lock must not be
    /// instantly re-opened by the owner's face still being in front of the camera.
    /// Auto-locks (timeout/background) keep the frictionless Face ID auto-prompt.
    private(set) var deliberatelyLocked = false
    /// `UserDefaults` key for the persisted deliberate-lock flag. The flag is
    /// plain lock-state metadata — never key material — so `UserDefaults` is
    /// the right store; the vault key itself stays keychain-guarded.
    static let deliberateLockDefaultsKey = "deliberateLockPending"
    private let defaults: UserDefaults

    #if DEBUG
    private var uiTestCredential: (password: String, key: [UInt8])?
    #endif

    let settings: SettingsStore

    init(
        settings: SettingsStore,
        uiTestConfiguration: UITestConfiguration = .disabled,
        persistentKeyMaterialEnabled: Bool = true,
        defaults: UserDefaults = .standard
    ) {
        self.settings = settings
        self.defaults = defaults
        #if DEBUG
        if uiTestConfiguration.isEnabled {
            let credential = (UITestConfiguration.fixturePassword, UITestConfiguration.fixtureKey)
            uiTestCredential = credential
            vaultKey = SecureBytes(credential.1)
            if defaults.bool(forKey: Self.deliberateLockDefaultsKey) {
                // A relaunch after a deliberate lock comes back locked behind
                // the slide gate, exactly like production.
                deliberatelyLocked = true
                state = .locked
            } else {
                state = .unlocked
            }
            return
        }
        #endif
        guard persistentKeyMaterialEnabled else {
            state = .onboarding
            return
        }
        state = VaultKeyBundle.exists ? .locked : .onboarding
        if state == .locked {
            // A force-quit must not demote a deliberate lock back to the
            // frictionless biometric path.
            deliberatelyLocked = defaults.bool(forKey: Self.deliberateLockDefaultsKey)
        }
    }

    var biometricEnrolled: Bool {
        #if DEBUG
        if uiTestCredential != nil { return false }
        #endif
        return BiometricKeyStore.isEnrolled
    }

    // MARK: Create

    /// Provision a brand-new vault from a master password.
    func createVault(masterPassword: String) async throws {
        let salt = KeyHierarchy.newSalt()
        // Extension-safe profile: the AutoFill extension must be able to run this
        // derivation under its memory budget (see `KdfParams.constrained`).
        let params = KdfParams.constrained
        var vaultKeyBytes = KeyHierarchy.newVaultKey()
        defer { secureZero(&vaultKeyBytes) }

        let wrapped = try await Self.wrap(vaultKey: vaultKeyBytes,
                                          password: masterPassword,
                                          salt: salt, params: params)
        let bundle = VaultKeyBundle(version: VaultKeyBundle.currentVersion,
                                    createdAt: .now,
                                    kdfSalt: Data(salt), kdf: params,
                                    wrappedByPassword: wrapped,
                                    recoverySalt: nil, wrappedByRecovery: nil)
        try bundle.save()
        adoptUnlocked(key: vaultKeyBytes)
    }

    // MARK: Unlock

    /// `beforeAdopt` runs after the password is proven correct but before the
    /// session flips to `.unlocked` — the lock screen uses it to play its
    /// success choreography while the vault key never leaves this function.
    func unlock(password: String, beforeAdopt: (() async -> Void)? = nil) async throws {
        #if DEBUG
        if let credential = uiTestCredential {
            guard password == credential.password else { throw AuthError.wrongPassword }
            await beforeAdopt?()
            adoptUnlocked(key: credential.key, publishSharedSession: false)
            return
        }
        #endif
        guard let bundle = VaultKeyBundle.load() else {
            state = .onboarding
            throw AuthError.noVault
        }
        var keyBytes: [UInt8]
        do {
            keyBytes = try await Self.unwrap(wrapped: bundle.wrappedByPassword,
                                             password: password,
                                             salt: Array(bundle.kdfSalt),
                                             params: bundle.kdf)
        } catch {
            throw AuthError.wrongPassword
        }
        defer { secureZero(&keyBytes) }
        // The password was just proven correct and the plaintext key is in hand —
        // the one safe moment to re-wrap an older bundle under the extension-safe
        // KDF profile with the full app memory budget. Best-effort: unlock
        // proceeds regardless of the outcome.
        await migrateKdfProfileIfNeeded(bundle: bundle, key: keyBytes, password: password)
        await beforeAdopt?()
        adoptUnlocked(key: keyBytes)
    }

    func unlockWithBiometrics() async throws {
        var keyBytes: [UInt8]
        do {
            keyBytes = try await BiometricKeyStore.retrieve(
                reason: appString("Unlock your vault"))
        } catch {
            throw AuthError.biometricFailed
        }
        defer { secureZero(&keyBytes) }
        adoptUnlocked(key: keyBytes)
    }

    // MARK: Biometric enrolment

    func enableBiometricUnlock() async throws {
        guard let vaultKey else { throw AuthError.locked }
        // Evaluate biometrics first — this surfaces the system permission prompt
        // and confirms the user can authenticate. Storing the key alone never
        // exercises Face ID, so the prompt would otherwise be deferred to the
        // first unlock.
        do {
            try await BiometricAuth.authenticate(reason: appString("Confirm to enable biometric unlock"))
        } catch {
            throw AuthError.biometricFailed
        }
        var bytes = vaultKey.bytes
        defer { secureZero(&bytes) }
        try BiometricKeyStore.store(vaultKey: bytes)
        settings.biometricUnlockEnabled = true
        // Fresh enrolment writes straight to the shared group — already "migrated", so the
        // one-time migration on next unlock is a no-op.
        settings.biometricKeyMigratedToSharedGroup = true
    }

    func disableBiometricUnlock() {
        BiometricKeyStore.delete()
        settings.biometricUnlockEnabled = false
    }

    // MARK: Lock

    func lock(deliberate: Bool = false) {
        vaultKey = nil
        level2Key = nil
        backgroundedAt = nil
        deliberatelyLocked = deliberate
        // Persisted flag (metadata only, never key material) so the slide
        // requirement survives an app restart; auto-locks clear it.
        if deliberate {
            defaults.set(true, forKey: Self.deliberateLockDefaultsKey)
        } else {
            defaults.removeObject(forKey: Self.deliberateLockDefaultsKey)
        }
        state = .locked
        // Locking the app revokes the Safari extension's unlocked session too —
        // the two share one lock lifecycle.
        #if DEBUG
        if uiTestCredential != nil { return }
        #endif
        ExtensionSessionStore.clear()
    }

    /// Drop the key and return to onboarding (used by full vault reset).
    func lockToOnboarding() {
        vaultKey = nil
        level2Key = nil
        state = .onboarding
        defaults.removeObject(forKey: Self.deliberateLockDefaultsKey)
        ExtensionSessionStore.clear()
    }

    /// Adopt the Level-2 Secret Key after a Level-2 unlock. Internal so
    /// `VaultSession+Level2` can set it across files.
    func setLevel2Key(_ bytes: [UInt8]) { level2Key = SecureBytes(bytes) }

    func registerActivity() { lastActivity = .now }

    /// Adopt a freshly-derived Vault Key and transition to unlocked. Internal so
    /// `VaultSession+Recovery` can reuse it across files.
    func adoptUnlocked(key: [UInt8], publishSharedSession: Bool = true) {
        vaultKey = SecureBytes(key)
        state = .unlocked
        lastActivity = .now
        deliberatelyLocked = false
        defaults.removeObject(forKey: Self.deliberateLockDefaultsKey)
        guard publishSharedSession else { return }
        migrateBiometricKeyToSharedGroupIfNeeded(key: key)
        // An unlocked app also unlocks the Safari extension (same window, same
        // 15-minute cap; "immediate" writes nothing). Seeded AFTER the biometric
        // migration: `BiometricKeyStore.store` clears the session item as part
        // of its leading delete, which would drop a just-written seed.
        ExtensionSessionStore.save(vaultKey: key, ttl: settings.autoLock.seconds)
    }

    /// One-time: move the biometric Vault Key from the legacy per-app keychain group into the
    /// shared group so the AutoFill extension can unlock with Face ID. Runs after an in-app unlock;
    /// guarded by a flag so it never repeats. Storing never prompts (only `retrieve` does), so this is
    /// silent. Already-enrolled users fall back to the master password in the extension until this runs
    /// once. Best-effort — on failure the flag stays unset and the legacy key is retried next unlock.
    private func migrateBiometricKeyToSharedGroupIfNeeded(key: [UInt8]) {
        guard settings.biometricUnlockEnabled, !settings.biometricKeyMigratedToSharedGroup else {
            biometricLog.log("migrate skip: enabled=\(self.settings.biometricUnlockEnabled, privacy: .public) migrated=\(self.settings.biometricKeyMigratedToSharedGroup, privacy: .public)")
            return
        }
        do {
            // `store` clears both groups then writes to the shared group, so the legacy copy is
            // dropped as part of this call — no orphan left.
            try BiometricKeyStore.store(vaultKey: key)
            settings.biometricKeyMigratedToSharedGroup = true
            biometricLog.log("migrate OK: biometric key written to shared group")
        } catch {
            // Leave the flag unset; retry on the next successful unlock.
            biometricLog.error("migrate FAILED: \(String(describing: error), privacy: .public) — retry next unlock")
        }
    }

    // MARK: KDF-profile migration

    /// Re-wrap the password envelope of a pre-`constrained` bundle so the AutoFill
    /// extension's master-password unlock fits its memory budget. Best-effort like
    /// the biometric-key migration: any failure keeps the old bundle fully intact
    /// (the save is atomic) and is retried on the next successful password unlock.
    private func migrateKdfProfileIfNeeded(bundle: VaultKeyBundle, key: [UInt8],
                                           password: String) async {
        do {
            guard let updated = try await Self.kdfMigratedBundle(from: bundle,
                                                                 vaultKey: key,
                                                                 password: password)
            else { return }
            try updated.save()
            kdfLog.log("kdf profile migrate OK")
        } catch {
            // Boolean outcome only — no params, salts, or error payloads.
            kdfLog.error("kdf profile migrate failed — retry next password unlock")
        }
    }

    /// Pure re-wrap step: the bundle with `wrappedByPassword` re-wrapped under
    /// `KdfParams.constrained` (fresh salt), or nil when already on that profile.
    /// The recovery envelope is deliberately untouched — the paper recovery key
    /// is not in hand — so the profile it was wrapped with is recorded in
    /// `recoveryKdf` BEFORE `kdf` diverges from it; otherwise the Emergency Kit
    /// would stop unwrapping. Internal (not private) so tests can exercise it.
    nonisolated static func kdfMigratedBundle(from bundle: VaultKeyBundle,
                                              vaultKey: [UInt8],
                                              password: String) async throws -> VaultKeyBundle? {
        guard bundle.kdf != .constrained else { return nil }
        var updated = bundle
        if updated.wrappedByRecovery != nil, updated.recoveryKdf == nil {
            updated.recoveryKdf = updated.kdf
        }
        let salt = KeyHierarchy.newSalt()
        updated.wrappedByPassword = try await Self.wrap(vaultKey: vaultKey,
                                                        password: password,
                                                        salt: salt,
                                                        params: .constrained)
        updated.kdfSalt = Data(salt)
        updated.kdf = .constrained
        return updated
    }

    /// Lock if the configured inactivity window has elapsed (foreground idle timer).
    /// `.immediate` means "lock the moment the app is hidden", not "idle 0s" —
    /// applying it here would lock mid-use on every timer tick.
    func lockIfTimedOut(now: Date = .now) {
        guard state == .unlocked, settings.autoLock != .immediate else { return }
        if now.timeIntervalSince(lastActivity) >= settings.autoLock.seconds {
            lock()
        }
    }

    /// Record that the app entered the background (scene-based auto-lock baseline).
    func markBackgrounded(now: Date = .now) {
        guard state == .unlocked else { return }
        backgroundedAt = now
    }

    /// On returning to the foreground, lock if the time spent in the background met the
    /// auto-lock window. Measured against the background timestamp (not `lastActivity`), so a
    /// fresh biometric unlock isn't immediately re-locked, and the Face ID prompt's
    /// `.inactive → .active` bounce — which never sets `backgroundedAt` — is a no-op.
    func lockIfBackgroundExpired(now: Date = .now) {
        guard state == .unlocked, let backgroundedAt else { return }
        self.backgroundedAt = nil
        if now.timeIntervalSince(backgroundedAt) >= settings.autoLock.seconds {
            lock()
        }
    }

    // MARK: Off-main KDF helpers

    nonisolated static func wrap(vaultKey: [UInt8], password: String,
                                 salt: [UInt8], params: KdfParams) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try KeyHierarchy.wrap(vaultKey: vaultKey, passphrase: password, salt: salt, params: params)
        }.value
    }

    nonisolated static func unwrap(wrapped: Data, password: String,
                                   salt: [UInt8], params: KdfParams) async throws -> [UInt8] {
        try await Task.detached(priority: .userInitiated) {
            try KeyHierarchy.unwrap(wrapped: wrapped, passphrase: password, salt: salt, params: params)
        }.value
    }
}
