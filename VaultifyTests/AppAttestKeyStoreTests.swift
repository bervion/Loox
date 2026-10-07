import XCTest
@testable import Vaultify

/// A reinstall is the case that stranded people: the Keychain outlives app
/// deletion, the Secure Enclave key does not, and the two Keychain items still
/// agree with each other afterwards — so the store used to hand back an id for
/// a key that no longer existed and report it as already registered.
final class AppAttestKeyStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let base = URL(string: "https://api.example.test")!

    override func setUp() {
        super.setUp()
        suiteName = "app-attest-store-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        store(environment: .development).reset()
        store(environment: .production).reset()
        store().purgeLegacy()
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private var namespace: String { "test-\(suiteName!)" }

    private func store(environment: AppAttestEnvironment = .development) -> AppAttestKeyStore {
        AppAttestKeyStore(namespace: namespace, apiBase: base, environment: environment,
                         defaults: defaults)
    }

    func testPersistThenReadBack() throws {
        let s = store()
        try s.persist(keyId: "key-abc")
        XCTAssertEqual(s.storedKeyId, "key-abc")
    }

    /// The regression. Simulating a reinstall = Keychain intact, defaults gone.
    func testReinstallDropsTheKeyIdEvenThoughTheKeychainStillHasIt() throws {
        let s = store()
        try s.persist(keyId: "key-abc")
        try s.markRegistered(keyId: "key-abc")
        XCTAssertEqual(s.storedKeyId, "key-abc")
        XCTAssertTrue(s.isRegistered(keyId: "key-abc"))

        defaults.removePersistentDomain(forName: suiteName)

        XCTAssertNil(s.storedKeyId,
                     "a key id that outlived its install must not be offered — the Enclave key is gone")
        XCTAssertFalse(s.isRegistered(keyId: "key-abc"),
                       "registration cannot be trusted once the install that registered it is gone")
    }

    func testRegistrationMarkerOnlyAuthorisesItsOwnKey() throws {
        let s = store()
        try s.persist(keyId: "key-abc")
        try s.markRegistered(keyId: "key-abc")
        XCTAssertFalse(s.isRegistered(keyId: "key-xyz"))
    }

    func testResetClearsBothStores() throws {
        let s = store()
        try s.persist(keyId: "key-abc")
        try s.markRegistered(keyId: "key-abc")
        s.reset()
        XCTAssertNil(s.storedKeyId)
        XCTAssertFalse(s.isRegistered(keyId: "key-abc"))
    }

    func testLateRejectedKeyDoesNotResetItsReplacement() throws {
        let s = store()
        try s.persist(keyId: "key-one")
        try s.markRegistered(keyId: "key-one")
        try s.persist(keyId: "key-two")
        try s.markRegistered(keyId: "key-two")

        // Another request receives K1's rejection after K2 has enrolled.
        XCTAssertFalse(store().reset(ifKeyIdMatches: "key-one"))

        XCTAssertEqual(s.storedKeyId, "key-two")
        XCTAssertTrue(s.isRegistered(keyId: "key-two"))
        XCTAssertFalse(s.isRegistered(keyId: "key-one"))
    }

    func testConditionalResetClearsTheMatchingKeyAndRegistration() throws {
        let s = store()
        try s.persist(keyId: "key-one")
        try s.markRegistered(keyId: "key-one")
        try s.persist(keyId: "key-two")
        try s.markRegistered(keyId: "key-two")

        XCTAssertTrue(store().reset(ifKeyIdMatches: "key-two"))

        XCTAssertNil(s.storedKeyId)
        XCTAssertFalse(s.isRegistered(keyId: "key-two"))
        XCTAssertFalse(s.reset(ifKeyIdMatches: "key-two"))
    }

    /// Staging and production must never see each other's key state.
    func testScopingByHostKeepsEnvironmentsApart() throws {
        let prod = store(environment: .production)
        let staging = AppAttestKeyStore(namespace: namespace,
                                        apiBase: URL(string: "https://api-staging.example.test")!,
                                        environment: .production,
                                        defaults: defaults)
        try prod.persist(keyId: "prod-key")
        XCTAssertNil(staging.storedKeyId)
        staging.reset()
    }

    /// Relay uses the same host in Debug and Release. A host-only scope let
    /// Apple's development and production keys overwrite each other's state.
    func testSameHostSeparatesAttestationEnvironmentsAndRegistration() throws {
        let development = store(environment: .development)
        let production = store(environment: .production)
        try development.persist(keyId: "development-key")
        try development.markRegistered(keyId: "development-key")

        XCTAssertNil(production.storedKeyId)
        XCTAssertFalse(production.isRegistered(keyId: "development-key"))

        try production.persist(keyId: "production-key")
        try production.markRegistered(keyId: "production-key")

        XCTAssertEqual(development.storedKeyId, "development-key")
        XCTAssertEqual(production.storedKeyId, "production-key")
        XCTAssertTrue(development.isRegistered(keyId: "development-key"))
        XCTAssertTrue(production.isRegistered(keyId: "production-key"))
        XCTAssertFalse(development.isRegistered(keyId: "production-key"))
        XCTAssertFalse(production.isRegistered(keyId: "development-key"))
    }

    func testResetDoesNotClearTheOtherAttestationEnvironment() throws {
        let development = store(environment: .development)
        let production = store(environment: .production)
        try development.persist(keyId: "development-key")
        try development.markRegistered(keyId: "development-key")
        try production.persist(keyId: "production-key")
        try production.markRegistered(keyId: "production-key")

        development.reset()

        XCTAssertNil(development.storedKeyId)
        XCTAssertFalse(development.isRegistered(keyId: "development-key"))
        XCTAssertEqual(production.storedKeyId, "production-key")
        XCTAssertTrue(production.isRegistered(keyId: "production-key"))
    }

    /// A fresh development install must not revive production's stale Keychain
    /// id by recreating an install marker shared by both environments.
    func testNewDevelopmentInstallDoesNotReviveProductionStateAfterReinstall() throws {
        let development = store(environment: .development)
        let production = store(environment: .production)
        try production.persist(keyId: "old-production-key")
        try production.markRegistered(keyId: "old-production-key")
        defaults.removePersistentDomain(forName: suiteName)

        try development.persist(keyId: "new-development-key")
        try development.markRegistered(keyId: "new-development-key")

        XCTAssertNil(production.storedKeyId)
        XCTAssertFalse(production.isRegistered(keyId: "old-production-key"))
        XCTAssertEqual(development.storedKeyId, "new-development-key")
        XCTAssertTrue(development.isRegistered(keyId: "new-development-key"))
    }

    func testAmbiguousHostOnlyStateIsIgnoredAndPurgedWithSuppliedLegacyAccounts() throws {
        let keyAccount = "\(namespace)-app-attest-key-id@\(base.host!)"
        let registeredAccount = "\(namespace)-app-attest-registered@\(base.host!)"
        let installMarker = "\(namespace)-app-attest-install@\(base.host!)"
        let flatAccount = "\(namespace)-legacy-key-id"
        defer { KeychainStore.delete(account: flatAccount) }
        try KeychainStore.set(Data("ambiguous-key".utf8), account: keyAccount)
        try KeychainStore.set(Data("ambiguous-key".utf8), account: registeredAccount)
        try KeychainStore.set(Data("flat-key".utf8), account: flatAccount)
        defaults.set(true, forKey: installMarker)

        let development = AppAttestKeyStore(namespace: namespace, apiBase: base,
                                            environment: .development,
                                            legacyAccounts: [flatAccount], defaults: defaults)
        let production = store(environment: .production)
        XCTAssertNil(development.storedKeyId)
        XCTAssertNil(production.storedKeyId)
        XCTAssertFalse(development.isRegistered(keyId: "ambiguous-key"))
        XCTAssertFalse(production.isRegistered(keyId: "ambiguous-key"))

        // The services call this before minting a replacement key.
        development.purgeLegacy()
        try development.persist(keyId: "fresh-development-key")
        try development.markRegistered(keyId: "fresh-development-key")

        XCTAssertNil(try KeychainStore.get(account: keyAccount))
        XCTAssertNil(try KeychainStore.get(account: registeredAccount))
        XCTAssertNil(try KeychainStore.get(account: flatAccount))
        XCTAssertFalse(defaults.bool(forKey: installMarker))
        XCTAssertEqual(development.storedKeyId, "fresh-development-key")
        XCTAssertTrue(development.isRegistered(keyId: "fresh-development-key"))
        XCTAssertNil(production.storedKeyId)
    }
}
