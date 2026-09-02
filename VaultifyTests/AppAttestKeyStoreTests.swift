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
        store().reset()
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func store() -> AppAttestKeyStore {
        AppAttestKeyStore(namespace: "test-\(suiteName!)", apiBase: base, defaults: defaults)
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

    /// Staging and production must never see each other's key state.
    func testScopingByHostKeepsEnvironmentsApart() throws {
        let prod = AppAttestKeyStore(namespace: "test-\(suiteName!)", apiBase: base, defaults: defaults)
        let staging = AppAttestKeyStore(namespace: "test-\(suiteName!)",
                                        apiBase: URL(string: "https://api-staging.example.test")!,
                                        defaults: defaults)
        try prod.persist(keyId: "prod-key")
        XCTAssertNil(staging.storedKeyId)
        staging.reset()
    }
}
