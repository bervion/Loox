import LocalAuthentication
import Security
import XCTest
@testable import Vaultify

/// The app-wide biometric failure policy: a face that was presented and rejected
/// is an identity signal and locks the vault; a dismissed prompt proves nothing
/// and must never lock. `BiometricAuth.classify` is the single place that decides
/// which is which, so every mapping is pinned here — it is pure, so none of this
/// needs a device or a real Keychain item.
@MainActor
final class BiometricFailurePolicyTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "biometric-policy-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - LAError classification

    func testEveryCancelFormClassifiesAsCancelled() {
        // `.userFallback` belongs here: `localizedFallbackTitle` is never set, so
        // the system prompt shows its "Enter Password" button and tapping it is a
        // deliberate choice of another route, not a rejected face.
        for code in [LAError.Code.userCancel, .systemCancel, .appCancel, .userFallback] {
            XCTAssertEqual(BiometricAuth.classify(LAError(code)), .cancelled,
                           "\(code) must never read as a failed identity check")
        }
    }

    func testRejectedBiometryClassifiesAsFailed() {
        XCTAssertEqual(BiometricAuth.classify(LAError(.authenticationFailed)), .failed)
    }

    func testBiometryLockoutClassifiesAsLockout() {
        XCTAssertEqual(BiometricAuth.classify(LAError(.biometryLockout)), .lockout)
    }

    func testStatesWhereBiometryNeverRanClassifyAsUnavailable() {
        for code in [LAError.Code.biometryNotAvailable, .biometryNotEnrolled, .invalidContext,
                     .notInteractive, .passcodeNotSet] {
            XCTAssertEqual(BiometricAuth.classify(LAError(code)), .unavailable,
                           "\(code) means nothing was attempted, so it carries no penalty")
        }
    }

    func testUnrecognisedErrorsDefaultToFailed() {
        struct SomethingElse: Error {}
        XCTAssertEqual(BiometricAuth.classify(SomethingElse()), .failed,
                       "an unattributable error during an identity check is read conservatively")
        XCTAssertEqual(BiometricAuth.classify(URLError(.notConnectedToInternet)), .failed)
    }

    // MARK: - Keychain failure classification

    func testVaultKeyStoreFailuresClassify() {
        XCTAssertEqual(BiometricAuth.classify(BiometricKeyStore.Failure.cancelled), .cancelled)
        XCTAssertEqual(BiometricAuth.classify(BiometricKeyStore.Failure.denied), .failed)
        XCTAssertEqual(BiometricAuth.classify(BiometricKeyStore.Failure.invalidated), .unavailable)
        XCTAssertEqual(BiometricAuth.classify(BiometricKeyStore.Failure.unavailable), .unavailable)
        XCTAssertEqual(BiometricAuth.classify(BiometricKeyStore.Failure.accessControl), .unavailable)
        XCTAssertEqual(BiometricAuth.classify(BiometricKeyStore.Failure.store(errSecInternalError)),
                       .failed)
    }

    /// A dismissed prompt and a rejected face used to collapse into one case, so
    /// the policy could not tell them apart at all.
    func testVaultKeyStoreKeepsCancelAndDenialApart() {
        XCTAssertNotEqual(BiometricAuth.classify(BiometricKeyStore.Failure.cancelled),
                          BiometricAuth.classify(BiometricKeyStore.Failure.denied))
    }

    func testLevel2StoreFailuresClassify() {
        XCTAssertEqual(BiometricAuth.classify(Level2BiometricKeyStore.Failure.cancelled), .cancelled)
        XCTAssertEqual(BiometricAuth.classify(Level2BiometricKeyStore.Failure.denied), .failed)
        XCTAssertEqual(BiometricAuth.classify(Level2BiometricKeyStore.Failure.notEnrolled), .unavailable)
        XCTAssertEqual(BiometricAuth.classify(Level2BiometricKeyStore.Failure.accessControl), .unavailable)
        XCTAssertEqual(BiometricAuth.classify(Level2BiometricKeyStore.Failure.store(errSecInternalError)),
                       .failed)
    }

    // MARK: - The policy itself

    /// A UI-test-fixture session starts unlocked and never touches the real
    /// Keychain or a vault file, so the policy can be exercised directly.
    private func makeUnlockedSession() throws -> VaultSession {
        let configuration = try UITestConfiguration.parse(arguments: [
            "Vaultify",
            UITestConfiguration.launchFlag,
            UITestConfiguration.fixtureArgument,
            UITestConfiguration.Fixture.vaultEditSaveRelock.rawValue,
        ])
        let session = VaultSession(
            settings: SettingsStore(defaults: defaults, mirrorToSharedConfig: false),
            uiTestConfiguration: configuration,
            defaults: defaults
        )
        XCTAssertEqual(session.state, .unlocked)
        return session
    }

    func testRejectedFaceLocksTheVaultBehindTheSlideGate() throws {
        let session = try makeUnlockedSession()
        session.noteBiometricOutcome(LAError(.authenticationFailed))
        XCTAssertEqual(session.state, .locked)
        XCTAssertTrue(session.deliberatelyLocked,
                      "a rejected face must not be re-offered Face ID on the spot")
    }

    func testLockoutLocksTheVault() throws {
        let session = try makeUnlockedSession()
        session.noteBiometricOutcome(LAError(.biometryLockout))
        XCTAssertEqual(session.state, .locked)
    }

    func testDeniedKeychainReadLocksTheVault() throws {
        let session = try makeUnlockedSession()
        session.noteBiometricOutcome(BiometricKeyStore.Failure.denied)
        XCTAssertEqual(session.state, .locked)
    }

    func testCancelNeverLocksTheVault() throws {
        let session = try makeUnlockedSession()
        for error: Error in [LAError(.userCancel), LAError(.systemCancel), LAError(.appCancel),
                             LAError(.userFallback), BiometricKeyStore.Failure.cancelled,
                             Level2BiometricKeyStore.Failure.cancelled] {
            session.noteBiometricOutcome(error)
            XCTAssertEqual(session.state, .unlocked,
                           "dismissing a prompt proves nothing about who is holding the phone")
        }
    }

    func testUnavailableBiometryNeverLocksTheVault() throws {
        let session = try makeUnlockedSession()
        for error: Error in [LAError(.biometryNotEnrolled), LAError(.biometryNotAvailable),
                             BiometricKeyStore.Failure.invalidated] {
            session.noteBiometricOutcome(error)
            XCTAssertEqual(session.state, .unlocked)
        }
    }

    func testAlreadyLockedSessionIsLeftAlone() throws {
        let session = try makeUnlockedSession()
        session.lock()
        XCTAssertFalse(session.deliberatelyLocked)
        session.noteBiometricOutcome(LAError(.authenticationFailed))
        XCTAssertEqual(session.state, .locked)
        XCTAssertFalse(session.deliberatelyLocked,
                       "an auto-lock must not be upgraded to the slide gate by a later outcome")
    }

    // MARK: - Level-2 key lifetime

    func testBackgroundingClearsTheLevel2Key() throws {
        let session = try makeUnlockedSession()
        session.setLevel2Key([UInt8](repeating: 0x11, count: 32))
        XCTAssertNotNil(session.level2Key)
        session.markBackgrounded()
        XCTAssertNil(session.level2Key,
                     "Extra Protection is a per-visit gate, not a session-long one")
    }
}
