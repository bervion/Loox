import XCTest
@testable import Vaultify

/// The tutorial's state machine: when a tour may start, how it advances, and
/// what each ending records. Presentation is not covered here — the overlay is
/// a pure view driven entirely by this coordinator.
@MainActor
final class TutorialFlowStateTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "tutorial.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makeCoordinator() -> TutorialCoordinator {
        TutorialCoordinator(store: TutorialStore(defaults: defaults))
    }

    private let flow = TutorialFlow(id: "test-flow", steps: [
        TutorialStep(id: "one", title: "One", message: "First"),
        TutorialStep(id: "two", title: "Two", message: "Second"),
    ])

    func testCompletingEveryStepEndsTheTourAndKeepsItFromReturning() {
        let coordinator = makeCoordinator()

        coordinator.startIfNeeded(flow)
        XCTAssertEqual(coordinator.currentStep?.id, "one")
        XCTAssertFalse(coordinator.isLastStep)

        coordinator.advance()
        XCTAssertEqual(coordinator.currentStep?.id, "two")
        XCTAssertTrue(coordinator.isLastStep, "the closing step swaps Next for Done")

        coordinator.advance()
        XCTAssertNil(coordinator.currentStep, "past the last step the tour is over")

        // A completed tour must not reappear on the next visit to the screen.
        coordinator.startIfNeeded(flow)
        XCTAssertNil(coordinator.currentStep)
    }

    func testSkippingIsAnAnswerAndIsNotAskedAgain() {
        let coordinator = makeCoordinator()
        coordinator.startIfNeeded(flow)

        coordinator.skip()

        XCTAssertNil(coordinator.currentStep)
        coordinator.startIfNeeded(flow)
        XCTAssertNil(coordinator.currentStep, "asking again after a no is nagging")
    }

    /// An interruption outside the user's intent (auto-lock, a push landing
    /// elsewhere) must not spend the one chance the tour gets.
    func testSuspendLeavesTheFlowEligible() {
        let coordinator = makeCoordinator()
        coordinator.startIfNeeded(flow)

        coordinator.suspend()
        XCTAssertNil(coordinator.currentStep)

        coordinator.startIfNeeded(flow)
        XCTAssertEqual(coordinator.currentStep?.id, "one")
    }

    func testStartIsIgnoredWhileAnotherFlowIsRunning() {
        let coordinator = makeCoordinator()
        let other = TutorialFlow(id: "other", steps: [
            TutorialStep(id: "x", title: "X", message: "X"),
        ])

        coordinator.startIfNeeded(flow)
        coordinator.startIfNeeded(other)

        XCTAssertEqual(coordinator.currentStep?.id, "one",
                       "two overlapping spotlights would fight over the screen")
    }

    func testStepLabelCountsFromOne() {
        let coordinator = makeCoordinator()
        coordinator.startIfNeeded(flow)

        XCTAssertEqual(coordinator.stepLabel, String(format: appString("Step %lld of %lld"), 1, 2))
    }

    func testStoreDistinguishesCompletedFromSkippedAndUnanswered() {
        let store = TutorialStore(defaults: defaults)

        XCTAssertEqual(store.state(of: "a"), .notStarted)
        XCTAssertTrue(store.shouldPresent("a"))

        store.mark("a", .completed)
        XCTAssertEqual(store.state(of: "a"), .completed)
        XCTAssertFalse(store.shouldPresent("a"))

        store.reset("a")
        XCTAssertTrue(store.shouldPresent("a"), "reset is what lets a tour be replayed")
    }

    /// The shipping flow's anchors must be ones a screen actually publishes,
    /// or a step spotlights nothing.
    func testFirstRunFlowOnlyReferencesKnownAnchors() {
        let known: Set<String> = [TutorialAnchorID.homeAddItem,
                                  TutorialAnchorID.homeSearch,
                                  TutorialAnchorID.homeSecurity,
                                  TutorialAnchorID.settingsAutoFill]
        for step in TutorialFlow.firstRun.steps {
            guard let anchor = step.anchor else { continue }
            XCTAssertTrue(known.contains(anchor), "unknown anchor \(anchor)")
        }
    }
}
