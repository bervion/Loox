import XCTest
@testable import Vaultify

/// KDF-profile coverage for the wrapped-key bundle: `recoveryKdf` codec
/// backward compatibility, the opportunistic password-wrap re-wrap, and the
/// Argon2id known-answer vector. The migration tests deliberately run the REAL
/// profiles (seconds-scale) — proving the shipped parameters round-trip is the
/// point; keep additional real-profile derivations out of other suites.
@MainActor
final class KdfMigrationTests: XCTestCase {
    private let password = "correct horse battery staple"
    private let recoveryPhrase = "EJ3K7-Q2MRT-8WXYZ-ABCDE-FGHJK"
    private let vaultKey: [UInt8] = (0..<32).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ 3) }

    private var originalBundle: Data?

    override func setUpWithError() throws {
        originalBundle = try? Data(contentsOf: SharedConfig.keyBundleURL)
        try? FileManager.default.removeItem(at: SharedConfig.keyBundleURL)
        try FileManager.default.createDirectory(at: SharedConfig.containerURL,
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Undo failure-injection permissions first so the restore below can write.
        try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                               ofItemAtPath: SharedConfig.containerURL.path)
        if let originalBundle {
            try originalBundle.write(to: SharedConfig.keyBundleURL, options: [.atomic])
        } else {
            try? FileManager.default.removeItem(at: SharedConfig.keyBundleURL)
        }
    }

    // MARK: Codec backward compatibility

    func testLegacyBundleJSONWithoutRecoveryKdfDecodes() throws {
        var bundle = dummyBundle(kdf: .standard)
        bundle.recoveryKdf = .standard
        var object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(bundle)) as? [String: Any])
        object.removeValue(forKey: "recoveryKdf")
        let legacyJSON = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(VaultKeyBundle.self, from: legacyJSON)
        XCTAssertNil(decoded.recoveryKdf)
        XCTAssertEqual(decoded.kdf, .standard)
        XCTAssertEqual(decoded.wrappedByPassword, bundle.wrappedByPassword)
    }

    func testRecoveryKdfRoundTrips() throws {
        var bundle = dummyBundle(kdf: .constrained)
        bundle.recoveryKdf = .standard
        let decoded = try JSONDecoder().decode(VaultKeyBundle.self,
                                               from: JSONEncoder().encode(bundle))
        XCTAssertEqual(decoded.recoveryKdf, .standard)
        XCTAssertEqual(decoded.kdf, .constrained)
    }

    // MARK: Migration (pure re-wrap step, real profiles)

    func testMigrationRewrapsPasswordPathAndPreservesRecovery() async throws {
        let bundle = try await standardBundle(withRecovery: true)
        let result = try await VaultSession.kdfMigratedBundle(from: bundle,
                                                              vaultKey: vaultKey,
                                                              password: password)
        let migrated = try XCTUnwrap(result)

        XCTAssertEqual(migrated.kdf, .constrained)
        XCTAssertNotEqual(migrated.kdfSalt, bundle.kdfSalt, "re-wrap must use a fresh salt")
        XCTAssertEqual(migrated.wrappedByRecovery, bundle.wrappedByRecovery,
                       "the recovery envelope must stay byte-identical")
        XCTAssertEqual(migrated.recoverySalt, bundle.recoverySalt)
        XCTAssertEqual(migrated.recoveryKdf, .standard,
                       "the pre-migration profile must be recorded before kdf diverges")

        let reopened = try await VaultSession.unwrap(wrapped: migrated.wrappedByPassword,
                                                     password: password,
                                                     salt: Array(migrated.kdfSalt),
                                                     params: migrated.kdf)
        XCTAssertEqual(reopened, vaultKey, "the same password must unwrap the new profile")

        // Lockout regression guard: the Emergency Kit still opens after migration.
        let recoveryWrapped = try XCTUnwrap(migrated.wrappedByRecovery)
        let recoverySalt = try XCTUnwrap(migrated.recoverySalt)
        let viaRecovery = try await VaultSession.unwrap(wrapped: recoveryWrapped,
                                                        password: recoveryPhrase,
                                                        salt: Array(recoverySalt),
                                                        params: migrated.recoveryKdf ?? migrated.kdf)
        XCTAssertEqual(viaRecovery, vaultKey)
    }

    func testMigrationIsNoOpOnConstrainedBundle() async throws {
        let bundle = dummyBundle(kdf: .constrained)
        let result = try await VaultSession.kdfMigratedBundle(from: bundle,
                                                              vaultKey: vaultKey,
                                                              password: password)
        XCTAssertNil(result, "no salt churn on an already-migrated bundle")
    }

    // MARK: Session-level paths

    func testCreateVaultUsesConstrainedProfile() async throws {
        let session = makeSession()
        try await session.createVault(masterPassword: password)
        let bundle = try XCTUnwrap(VaultKeyBundle.load())
        XCTAssertEqual(bundle.kdf, .constrained)
        XCTAssertEqual(session.state, .unlocked)
    }

    func testPasswordUnlockMigratesLegacyBundle() async throws {
        try await standardBundle(withRecovery: false).save()
        let session = makeSession()
        try await session.unlock(password: password)
        XCTAssertEqual(session.state, .unlocked)

        let bundle = try XCTUnwrap(VaultKeyBundle.load())
        XCTAssertEqual(bundle.kdf, .constrained)
        XCTAssertNil(bundle.recoveryKdf, "no recovery wrap means nothing to backfill")
    }

    func testUnlockSucceedsWhenMigrationCannotPersist() async throws {
        try await standardBundle(withRecovery: false).save()
        let before = try Data(contentsOf: SharedConfig.keyBundleURL)
        // Read-only container: the atomic save inside the migration fails while
        // reads keep working.
        try FileManager.default.setAttributes([.posixPermissions: 0o555],
                                              ofItemAtPath: SharedConfig.containerURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                   ofItemAtPath: SharedConfig.containerURL.path)
        }

        let session = makeSession()
        try await session.unlock(password: password)
        XCTAssertEqual(session.state, .unlocked, "a failed migration must never block unlock")

        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: SharedConfig.containerURL.path)
        XCTAssertEqual(try Data(contentsOf: SharedConfig.keyBundleURL), before,
                       "a failed migration must leave the old bundle intact")
    }

    // MARK: Argon2 known answer

    /// Canonical Argon2id v1.3 vector — guards the vendored C primitive against
    /// regression; profile changes must never alter the algorithm itself.
    func testArgon2KnownAnswerVector() throws {
        let expected = "09316115d5cf24ed5a15a31a3ba326e5cf32edc24702987c02b6566f61913cf7"
        let hash = try Argon2.deriveRaw(
            password: Array("password".utf8),
            salt: Array("somesalt".utf8),
            params: KdfParams(memoryCostKiB: 65536, timeCost: 2, parallelism: 1))
        XCTAssertEqual(hash.map { String(format: "%02x", $0) }.joined(), expected)
    }

    // MARK: Helpers

    /// A structurally valid bundle with garbage ciphertext, for tests that never
    /// run Argon2.
    private func dummyBundle(kdf: KdfParams) -> VaultKeyBundle {
        VaultKeyBundle(version: VaultKeyBundle.currentVersion, createdAt: .now,
                       kdfSalt: Data(repeating: 1, count: 16), kdf: kdf,
                       wrappedByPassword: Data(repeating: 2, count: 60),
                       recoverySalt: nil, wrappedByRecovery: nil)
    }

    /// A real pre-migration bundle: password (and optionally recovery) wrapped
    /// under `.standard`, exactly like a vault created before the constrained
    /// profile existed — including `recoveryKdf == nil`.
    private func standardBundle(withRecovery: Bool) async throws -> VaultKeyBundle {
        let salt = KeyHierarchy.newSalt()
        let wrapped = try await VaultSession.wrap(vaultKey: vaultKey, password: password,
                                                  salt: salt, params: .standard)
        var bundle = VaultKeyBundle(version: VaultKeyBundle.currentVersion, createdAt: .now,
                                    kdfSalt: Data(salt), kdf: .standard,
                                    wrappedByPassword: wrapped,
                                    recoverySalt: nil, wrappedByRecovery: nil)
        if withRecovery {
            let recoverySalt = KeyHierarchy.newSalt()
            bundle.recoverySalt = Data(recoverySalt)
            bundle.wrappedByRecovery = try await VaultSession.wrap(
                vaultKey: vaultKey, password: recoveryPhrase,
                salt: recoverySalt, params: .standard)
        }
        return bundle
    }

    private func makeSession() -> VaultSession {
        let settings = SettingsStore()
        // Keep `adoptUnlocked`'s biometric keychain migration inert in the test host.
        settings.biometricUnlockEnabled = false
        return VaultSession(settings: settings)
    }
}
