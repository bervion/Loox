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
        if progress != journeyProgress { journeyProgress = progress }
    }
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
