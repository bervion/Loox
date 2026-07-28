import SwiftUI

/// Runs one tutorial flow at a time: which step is showing, when a flow may
/// start, and what gets persisted or logged when it ends.
///
/// All behavior lives here so the overlay stays a pure view — and so a flow is
/// data (`TutorialFlow`) rather than another piece of view code.
@MainActor @Observable final class TutorialCoordinator {
    private(set) var flow: TutorialFlow?
    private(set) var stepIndex = 0

    @ObservationIgnored private let store: TutorialStore

    init(store: TutorialStore = TutorialStore()) {
        self.store = store
    }

    var currentStep: TutorialStep? {
        guard let flow, stepIndex < flow.steps.count else { return nil }
        return flow.steps[stepIndex]
    }

    var isPresenting: Bool { currentStep != nil }

    /// The last step ends the tour, so its button says so ("Done", not "Next")
    /// and it drops the Skip escape — there is nothing left to skip.
    var isLastStep: Bool {
        guard let flow else { return false }
        return stepIndex == flow.steps.count - 1
    }

    /// Label like "1 of 3" — orientation matters more in a tour than in a
    /// sheet, because the user can't see how much is left.
    var stepLabel: String? {
        guard let flow else { return nil }
        return String(format: appString("Step %lld of %lld"), stepIndex + 1, flow.steps.count)
    }

    /// Begin a flow unless it was already completed or skipped, or the feature
    /// is off. Safe to call on every appearance — it self-suppresses.
    func startIfNeeded(_ flow: TutorialFlow) {
        guard TutorialFeature.enabled, self.flow == nil, store.shouldPresent(flow.id) else { return }
        self.flow = flow
        stepIndex = 0
        logStep()
    }

    func advance() {
        guard let flow else { return }
        let next = stepIndex + 1
        if next < flow.steps.count {
            stepIndex = next
            logStep()
        } else {
            finish(.completed)
        }
    }

    func skip() { finish(.skipped) }

    /// Clear every recorded answer so the tours play again. Any tour currently
    /// on screen is dropped first — otherwise it would finish and immediately
    /// re-record the state this just erased.
    func replayAll() {
        suspend()
        store.resetAll()
    }

    /// Ends the tour without recording an answer — for a flow interrupted by
    /// something outside the user's intent (an auto-lock, a push landing on
    /// another screen). It stays eligible to run again later.
    func suspend() {
        flow = nil
        stepIndex = 0
    }

    private func finish(_ state: TutorialStore.State) {
        guard let flow else { return }
        store.mark(flow.id, state)
        AnalyticsEngine.shared.log(.tutorialFlowEnded(
            flow: flow.id, outcome: state == .completed ? "completed" : "skipped"))
        self.flow = nil
        stepIndex = 0
    }

    private func logStep() {
        guard let flow else { return }
        AnalyticsEngine.shared.log(.tutorialStepShown(flow: flow.id, step: stepIndex))
    }
}
