import XCTest
@testable import Vaultify

/// A deliberate lock (panic shake / Settings "Lock Now") must survive an app
/// restart: the flag is metadata, never key material, and clears only on a
/// successful unlock or a full vault reset.
@MainActor
final class VaultSessionPanicLockTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "panic-lock-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeSession() -> VaultSession {
        let configuration = try! UITestConfiguration.parse(arguments: [
            "Vaultify",
            UITestConfiguration.launchFlag,
            UITestConfiguration.fixtureArgument,
            UITestConfiguration.Fixture.vaultEditSaveRelock.rawValue,
        ])
        return VaultSession(
            settings: SettingsStore(defaults: defaults, mirrorToSharedConfig: false),
            uiTestConfiguration: configuration,
            defaults: defaults
        )
    }

    func testDeliberateLockPersistsFlag() {
        let session = makeSession()
        session.lock(deliberate: true)
        XCTAssertTrue(defaults.bool(forKey: VaultSession.deliberateLockDefaultsKey))
    }

    func testAutoLockClearsPersistedFlag() {
        let session = makeSession()
        session.lock(deliberate: true)
        session.lock(deliberate: false)
        XCTAssertNil(defaults.object(forKey: VaultSession.deliberateLockDefaultsKey))
    }

    func testSuccessfulUnlockClearsPersistedFlag() {
        let session = makeSession()
        session.lock(deliberate: true)
        session.adoptUnlocked(key: UITestConfiguration.fixtureKey, publishSharedSession: false)
        XCTAssertNil(defaults.object(forKey: VaultSession.deliberateLockDefaultsKey))
        XCTAssertFalse(session.deliberatelyLocked)
    }

    func testVaultResetClearsPersistedFlag() {
        let session = makeSession()
        session.lock(deliberate: true)
        session.lockToOnboarding()
        XCTAssertNil(defaults.object(forKey: VaultSession.deliberateLockDefaultsKey))
    }

    func testInitRestoresDeliberateLockFromPersistedFlag() {
        let first = makeSession()
        first.lock(deliberate: true)

        let second = makeSession()
        XCTAssertTrue(second.deliberatelyLocked)
        XCTAssertEqual(second.state, .locked)
    }
}
