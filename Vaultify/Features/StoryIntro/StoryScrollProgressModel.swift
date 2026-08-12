import SwiftUI
import Observation

/// Scroll plumbing for the story journey. The beat column publishes its offset
/// through `StoryScrollMetricsKey`; the screen writes it in here; and ONLY the
/// stage layer reads `journeyProgress` — so a scroll tick invalidates the
/// Canvas stage and nothing else (the beat column's own effects stay on
/// render-side `scrollTransition`/`visualEffect`).
@Observable
final class StoryScrollProgressModel {
    /// 0…1 across the whole journey (0 = top of beat 1, 1 = bottom of beat 6).
    private(set) var journeyProgress: Double = 0

    /// Continuous beat coordinate 0…5: whole numbers are composed pages
    /// (0 = hook … 5 = commitment), fractions are the transitions between
    /// them. All stage choreography is a pure function of this scalar.
    var beatPosition: Double { journeyProgress * Double(StoryBeat.allCases.count - 1) }

    /// The consequence beat's one optional interaction: the moment the user
    /// "sent" the shared password (nil until they do). One-shot — like the real
    /// mistake, it cannot be un-sent. The stage derives the ripple from this;
    /// non-tappers get a softer scroll-driven ripple instead, so the beat plays
    /// either way.
    private(set) var sendTapTime: TimeInterval?

    func noteSendTap() {
        guard sendTapTime == nil else { return }
        sendTapTime = Date().timeIntervalSinceReferenceDate
        // "Risky state entered" in the haptics vocabulary, and the most literal
        // use of it in the app: the shared password has just left, and the
        // beat's whole point is that it cannot be called back.
        Haptics.warning()
    }

    /// The seal landed: the stage plays its exit burst from this instant while
    /// the screen finishes the flag flip behind it.
    private(set) var sealTime: TimeInterval?

    func noteSeal() {
        guard sealTime == nil else { return }
        sealTime = Date().timeIntervalSinceReferenceDate
    }

    func update(_ metrics: StoryScrollMetrics) {
        guard metrics.span > 0 else { return }
        // 2pt quantization: drops the sub-pixel offset churn a 120Hz scroll
        // produces without visibly stepping the scrub (a full journey spans
        // thousands of points).
        let offset = (metrics.offset / 2).rounded() * 2
        let progress = min(max(Double(offset / metrics.span), 0), 1)
        // A rotation or an iPad split-view resize publishes a new span and a
        // new offset together, so `progress` can move without a finger having
        // moved at all. The picture must follow that; the touch must not.
        let resized = metrics.span != lastSpan
        lastSpan = metrics.span

        guard progress != journeyProgress else { return }
        journeyProgress = progress

        guard !resized else {
            // Re-seat the ratchet silently, so the next real drag ticks from
            // where the finger actually is rather than replaying the jump.
            gatherDetent = Self.gatherDetent(at: beatPosition)
            if beatPosition >= StoryField.gatherWindow.end { clusterClosed = true }
            return
        }
        scoreGather()
    }

    // MARK: Haptic score

    /// The DNA vocabulary gives scrolling and navigation NO haptic, and this
    /// screen keeps that rule: nothing fires for reaching a beat or turning a
    /// page. What fires is the one stretch where the finger is not navigating
    /// but MANIPULATING — the turn, where the drag physically reels every stray
    /// password into the vault.
    ///
    /// That stretch is quantised into detents, and each one crossed fires a
    /// throttled selection tick, in either direction: dragging back visibly
    /// scatters the swarm again, so it has to tick going back too. The result
    /// is the ratchet a picker has under the thumb, and it is the only place in
    /// the story with a continuous texture.
    private func scoreGather() {
        let beat = beatPosition
        guard let detent = Self.gatherDetent(at: beat) else {
            gatherDetent = nil
            if beat <= StoryField.gatherWindow.start {
                // Scrubbed back before the turn: the swarm has visibly
                // scattered again, so the close is owed a second time. Reset
                // ONLY here — resetting on window exit would let a finger
                // oscillating across the end buzz on every crossing.
                clusterClosed = false
            } else if !clusterClosed, beat >= StoryField.gatherWindow.end {
                // The cluster closing is a single event, not a texture: one
                // tap, the first time the last survivor lands.
                clusterClosed = true
                Haptics.tap()
            }
            return
        }
        // Entering the window: warm the engine so the first detent is not the
        // one that gets dropped.
        if gatherDetent == nil { Haptics.prepareSelection() }
        guard detent != gatherDetent else { return }
        gatherDetent = detent
        Haptics.selectionTick()
    }

    /// Which detent of the turn a beat position falls in, or nil outside it.
    /// Pure so the texture's shape can be pinned without a Taptic engine.
    ///
    /// `nonisolated` so tests can call it off the main actor.
    nonisolated static func gatherDetent(at beat: Double) -> Int? {
        let window = StoryField.gatherWindow
        guard beat > window.start, beat < window.end else { return nil }
        let span = window.end - window.start
        let detent = Int((beat - window.start) / span * Double(gatherDetents))
        return min(detent, gatherDetents - 1)
    }

    /// Detents across the turn. Fourteen over one page of scrolling reads as a
    /// texture under the thumb; far fewer feels like a rattle, and far more is
    /// wasted under the 32 Hz ceiling the generator throttles at anyway.
    nonisolated static let gatherDetents = 14

    /// Which detent the finger last crossed, or nil when outside the turn.
    /// `@ObservationIgnored` on both: they are written on nearly every scroll
    /// tick and no view reads them, so there is no reason to pay for tracking.
    @ObservationIgnored private var gatherDetent: Int?
    /// The cluster-closed tap, owed once per genuine gather.
    @ObservationIgnored private var clusterClosed = false
    /// Last scrollable span, to tell a drag apart from a relayout.
    @ObservationIgnored private var lastSpan: CGFloat = 0
}

/// Offset + scrollable distance, published together so the handler never sees
/// an offset measured against a stale span (e.g. across a rotation).
nonisolated struct StoryScrollMetrics: Equatable {
    var offset: CGFloat = 0
    /// Content height minus one viewport page — the distance `offset` travels
    /// from the first composed page to the last.
    var span: CGFloat = 0
}

nonisolated struct StoryScrollMetricsKey: PreferenceKey {
    static let defaultValue = StoryScrollMetrics()
    static func reduce(value: inout StoryScrollMetrics, nextValue: () -> StoryScrollMetrics) {
        value = nextValue()
    }
}
