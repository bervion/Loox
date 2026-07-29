import LocalAuthentication
import XCTest
@testable import Vaultify

/// The lock screen's one hard invariant: it must never present ZERO ways in.
/// The badge disables itself into a spinner while a prompt is in flight and the
/// password field is not mounted until biometrics have been dismissed, so the
/// combination "prompt never answers" once left a spinner and nothing else —
/// a screen indistinguishable from a hang. `LockAffordances` is the pure
/// derivation the view renders from, so the whole state space can be walked here.
@MainActor
final class LockAffordanceInvariantTests: XCTestCase {

    /// Every combination the screen can hold, for a given probe/absorb pose.
    private func allStates(probed: Bool = true, absorbed: Bool = false) -> [LockAffordances] {
        var states: [LockAffordances] = []
        for mode in [LockAffordances.Mode.biometric, .password] {
            for usable in [false, true] {
                for slide in [false, true] {
                    for authenticating in [false, true] {
                        for dismissed in [false, true] {
                            states.append(LockAffordances(mode: mode,
                                                          probed: probed,
                                                          biometricsUsable: usable,
                                                          requireSlide: slide,
                                                          authenticating: authenticating,
                                                          dismissed: dismissed,
                                                          absorbed: absorbed))
                        }
                    }
                }
            }
        }
        return states
    }

    /// A prompt in flight is the ONLY state that legitimately shows no operable
    /// control — the system's own biometric sheet is over the screen at that
    /// point. Every other reachable state must offer something.
    private func isPromptInFlight(_ state: LockAffordances) -> Bool {
        state.mode == .biometric && state.biometricsUsable && state.authenticating
            && !state.dismissed && !state.requireSlide
    }

    // MARK: - The invariant

    func testEveryProbedStateOffersAWayInUnlessAPromptIsInFlight() {
        for state in allStates() {
            XCTAssertEqual(state.offersAWayIn, !isPromptInFlight(state),
                           "no way in from \(state)")
        }
    }

    /// The deadline that closes the hang: a prompt that outlives it marks the
    /// attempt dismissed, which mounts the password field. Dismissal costs no
    /// attempt, so this is free.
    func testTheBiometricDeadlineRestoresAWayIn() {
        for state in allStates() where isPromptInFlight(state) {
            var expired = state
            expired.dismissed = true
            XCTAssertTrue(expired.offersAWayIn)
            XCTAssertTrue(expired.showsPasswordField)
            XCTAssertTrue(expired.showsBiometricBadge,
                          "dismissing costs no attempt, so the badge stays one tap from a retry")
        }
    }

    /// Backgrounding clears the in-flight flag: a prompt cannot outlive the app
    /// leaving, so the badge must come back tappable rather than spinning.
    func testClearingTheInFlightFlagRestoresAWayIn() {
        for state in allStates() where isPromptInFlight(state) {
            var settled = state
            settled.authenticating = false
            XCTAssertTrue(settled.offersAWayIn)
            XCTAssertTrue(settled.showsBiometricBadge)
        }
    }

    /// A spinning badge is disabled, so it is not a way in on its own.
    func testASpinningBadgeDoesNotCountAsAnAffordance() {
        let state = LockAffordances(mode: .biometric, probed: true, biometricsUsable: true,
                                    authenticating: true)
        XCTAssertTrue(state.showsBiometricBadge)
        XCTAssertFalse(state.offersAWayIn)
    }

    // MARK: - The slide gate

    func testTheSlideGateReplacesEveryOtherControlAndIsItselfAWayIn() {
        for state in allStates() where state.requireSlide {
            XCTAssertTrue(state.showsSlide)
            XCTAssertFalse(state.showsBiometricBadge,
                           "a deliberate lock must not re-offer Face ID before the slide")
            XCTAssertFalse(state.showsPasswordField)
            XCTAssertTrue(state.offersAWayIn)
        }
    }

    // MARK: - The probe

    /// The pre-probe frame is the launch pose (mark only). It is bounded by an
    /// in-flight capability snapshot, not by anything the user does, and BOTH
    /// of its outcomes land on a control.
    func testProbingAlwaysLandsOnAControl() {
        var unprobed = LockAffordances()
        XCTAssertFalse(unprobed.offersAWayIn)

        var withBiometrics = unprobed
        withBiometrics.probed = true
        withBiometrics.biometricsUsable = true
        XCTAssertTrue(withBiometrics.showsBiometricBadge)
        XCTAssertTrue(withBiometrics.offersAWayIn)

        unprobed.probed = true
        XCTAssertTrue(unprobed.showsPasswordField,
                      "a device without biometric unlock goes straight to the password")
        XCTAssertTrue(unprobed.offersAWayIn)
    }

    /// The password fallback must not depend on the mode flip landing: a device
    /// that cannot use biometrics shows the field even while `mode` still says
    /// `.biometric`.
    func testPasswordFieldDoesNotWaitForTheModeFlip() {
        let state = LockAffordances(mode: .biometric, probed: true, biometricsUsable: false)
        XCTAssertTrue(state.showsPasswordField)
        XCTAssertFalse(state.showsBiometricBadge)
    }

    /// The pre-probe frame is the only state with nothing on it, so the screen
    /// puts a stopwatch on it: a probe that outstays its deadline mounts the
    /// field with the safe snapshot, and the late answer must add the badge
    /// beside the field rather than take the field away mid-typing.
    func testTheProbeDeadlineMountsTheFieldAndALateAnswerKeepsIt() {
        var stalled = LockAffordances()
        XCTAssertFalse(stalled.offersAWayIn)

        stalled.probed = true
        stalled.dismissed = true
        XCTAssertTrue(stalled.showsPasswordField)
        XCTAssertTrue(stalled.offersAWayIn)

        var lateAnswer = stalled
        lateAnswer.biometricsUsable = true
        XCTAssertTrue(lateAnswer.showsPasswordField,
                      "a late probe must not pull the field out from under the user")
        XCTAssertTrue(lateAnswer.showsBiometricBadge)
    }

    // MARK: - The absorb

    /// The success choreography retires the two gates, and deliberately KEEPS
    /// the password field: the absorb collapses the whole chrome — field
    /// included — into the mark, and unmounting it would both slide it out on
    /// its own transition and shrink the measured chrome height that puts the
    /// mark at the exact screen centre.
    func testTheAbsorbRetiresTheGatesAndKeepsTheFieldToAbsorb() {
        for state in allStates(absorbed: true) {
            XCTAssertFalse(state.showsSlide)
            XCTAssertFalse(state.showsBiometricBadge)
            var open = state
            open.absorbed = false
            XCTAssertEqual(state.showsPasswordField, open.showsPasswordField,
                           "the field must survive the absorb so the chrome height holds")
        }
    }

    // MARK: - Capability snapshot

    /// Naming the biometry is a daemon round-trip, so the lock screen renders
    /// from a snapshot. The mapping itself is pure and pinned here.
    func testBiometryNamingIsPure() {
        XCTAssertEqual(BiometricAuth.displayName(for: .faceID), "Face ID")
        XCTAssertEqual(BiometricAuth.displayName(for: .touchID), "Touch ID")
        XCTAssertEqual(BiometricAuth.systemImage(for: .faceID), "faceid")
        XCTAssertEqual(BiometricAuth.systemImage(for: .touchID), "touchid")
        XCTAssertEqual(BiometricAuth.iconAsset(for: .faceID), "ic_person")
        XCTAssertEqual(BiometricAuth.iconAsset(for: .touchID), "ic_passkey")
        // No biometry: a lock glyph, never an empty name.
        XCTAssertEqual(BiometricAuth.systemImage(for: .none), "lock.fill")
        XCTAssertFalse(BiometricAuth.displayName(for: .none).isEmpty)
    }

    /// The value the screen renders with before the probe answers must never
    /// claim biometrics are ready.
    func testUnavailableCapabilityOffersNoBiometricRoute() {
        let capability = BiometricCapability.unavailable
        XCTAssertFalse(capability.isAvailable)
        XCTAssertFalse(capability.isEnrolled)
        XCTAssertFalse(capability.systemImage.isEmpty)
        XCTAssertFalse(capability.displayName.isEmpty)
    }

    /// A UI-test-fixture session never touches the real keychain, so its
    /// snapshot must report no biometric route (and must not probe at all).
    func testFixtureSessionReportsNoBiometricCapability() async throws {
        let suiteName = "lock-affordance-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
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
        let capability = await session.biometricCapability()
        XCTAssertEqual(capability, .unavailable)
    }
}
