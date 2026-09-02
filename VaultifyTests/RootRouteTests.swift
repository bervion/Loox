import XCTest
@testable import Vaultify

/// The route table, with the case that stranded people at the top.
@MainActor
final class RootRouteTests: XCTestCase {

    /// The bug: losing `vault-keybundle.json` leaves `onboardingCompleted` true,
    /// so the app routed to `.locked` forever and every unlock answered
    /// "No vault found on this device." Deleting the app was the only way out.
    func testNoVaultRoutesToOnboardingEvenAfterOnboardingCompleted() {
        XCTAssertEqual(
            RootView.resolveRoute(sessionState: .onboarding,
                                  onboardingCompleted: true,
                                  storyIntroCompleted: true),
            .onboarding)
    }

    func testFreshInstallRoutesToOnboarding() {
        XCTAssertEqual(
            RootView.resolveRoute(sessionState: .onboarding,
                                  onboardingCompleted: false,
                                  storyIntroCompleted: false),
            .onboarding)
    }

    /// A provisioned vault that has not been unlocked stays behind the lock
    /// screen — the fix must not turn every locked launch into onboarding.
    func testProvisionedButLockedStaysLocked() {
        XCTAssertEqual(
            RootView.resolveRoute(sessionState: .locked,
                                  onboardingCompleted: true,
                                  storyIntroCompleted: true),
            .locked)
    }

    /// Onboarding not finished but a bundle already written (the moment between
    /// creating the vault and setting the flag) must not skip ahead.
    func testUnlockedBeforeOnboardingCompletesStaysInOnboarding() {
        XCTAssertEqual(
            RootView.resolveRoute(sessionState: .unlocked,
                                  onboardingCompleted: false,
                                  storyIntroCompleted: false),
            .onboarding)
    }

    func testUnlockedReachesHomeOnceTheStoryIsDone() {
        XCTAssertEqual(
            RootView.resolveRoute(sessionState: .unlocked,
                                  onboardingCompleted: true,
                                  storyIntroCompleted: true),
            .unlocked)
    }

    func testUnlockedWithoutTheStoryRoutesToIt() {
        let expected: RootView.Route = StoryIntroFeature.enabled ? .story : .unlocked
        XCTAssertEqual(
            RootView.resolveRoute(sessionState: .unlocked,
                                  onboardingCompleted: true,
                                  storyIntroCompleted: false),
            expected)
    }
}
