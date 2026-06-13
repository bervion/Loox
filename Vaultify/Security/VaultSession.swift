import Foundation

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
    /// Timestamp of last user activity — drives auto-lock.
    var lastActivity: Date = .now

    let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
        state = VaultKeyBundle.exists ? .locked : .onboarding
    }

    var biometricEnrolled: Bool { BiometricKeyStore.isEnrolled }

    // MARK: Create

    /// Provision a brand-new vault from a master password.
    func createVault(masterPassword: String) async throws {
        let salt = KeyHierarchy.newSalt()
        let params = KdfParams.standard
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

    func unlock(password: String) async throws {
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
    }

    func disableBiometricUnlock() {
        BiometricKeyStore.delete()
        settings.biometricUnlockEnabled = false
    }

    // MARK: Lock

    func lock() {
        vaultKey = nil
        level2Key = nil
        state = .locked
    }

    /// Drop the key and return to onboarding (used by full vault reset).
    func lockToOnboarding() {
        vaultKey = nil
        level2Key = nil
        state = .onboarding
    }

    /// Adopt the Level-2 Secret Key after a Level-2 unlock. Internal so
    /// `VaultSession+Level2` can set it across files.
    func setLevel2Key(_ bytes: [UInt8]) { level2Key = SecureBytes(bytes) }

    func registerActivity() { lastActivity = .now }

    /// Adopt a freshly-derived Vault Key and transition to unlocked. Internal so
    /// `VaultSession+Recovery` can reuse it across files.
    func adoptUnlocked(key: [UInt8]) {
        vaultKey = SecureBytes(key)
        state = .unlocked
        lastActivity = .now
    }

    /// Lock if the configured inactivity window has elapsed.
    func lockIfTimedOut(now: Date = .now) {
        guard state == .unlocked else { return }
        if now.timeIntervalSince(lastActivity) >= settings.autoLock.seconds {
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
