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
    /// The settle-delay task between a screen asking for its tour and the tour
    /// actually appearing (see `startIfNeeded`).
    @ObservationIgnored private var pendingStart: Task<Void, Never>?
    @ObservationIgnored private let settleDelay: Duration

    /// `settleDelay` is injectable so the state-machine tests stay synchronous
    /// (`.zero` starts the flow inline, no task hop).
    init(store: TutorialStore = TutorialStore(),
         settleDelay: Duration = .milliseconds(1200)) {
        self.store = store
        self.settleDelay = settleDelay
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
    ///
    /// The flow appears after `settleDelay`, not on the same frame the screen
    /// does: a tour that pops with the tab switch reads as an interruption —
    /// the user hasn't even seen the screen it explains yet. One beat later,
    /// the layout has landed and the tour reads as a guide. The asking screen
    /// must cancel on disappear (`cancelPendingStart`) — otherwise a tab
    /// switched away from during the delay would pop its tour over some other
    /// screen.
    func startIfNeeded(_ flow: TutorialFlow) {
        guard TutorialFeature.enabled, self.flow == nil, pendingStart == nil,
              store.shouldPresent(flow.id) else { return }
        guard settleDelay > .zero else {
            begin(flow)
            return
        }
        pendingStart = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.settleDelay ?? .zero)
            guard let self else { return }
            self.pendingStart = nil
            guard !Task.isCancelled, self.flow == nil, self.store.shouldPresent(flow.id) else { return }
            self.begin(flow)
        }
    }

    private func begin(_ flow: TutorialFlow) {
        self.flow = flow
        stepIndex = 0
        logStep()
    }

    /// The screen that asked for a tour is going away before the settle delay
    /// elapsed — drop the request. The flow stays eligible for the next visit.
    func cancelPendingStart() {
        pendingStart?.cancel()
        pendingStart = nil
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
        cancelPendingStart()
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
