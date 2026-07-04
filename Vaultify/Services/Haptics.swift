import UIKit

/// Lightweight haptic feedback wrappers.
@MainActor enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func rigid() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }

    // MARK: Continuous-gesture selection ticks (sliders, wheels)

    /// Reused, kept-warm generator for repeated ticks during a drag. Spamming
    /// throwaway generators (or firing faster than the system's 32 Hz feedback
    /// limit) floods the console with "exceeds rate-limit" drops and wastes work.
    private static let dragSelection = UISelectionFeedbackGenerator()
    private static var lastTick: TimeInterval = 0

    /// Warm up the selection engine at the start of a drag gesture. Resets the
    /// throttle so the drag's first tick fires immediately (snappier feel).
    static func prepareSelection() {
        lastTick = 0
        dragSelection.prepare()
    }

    /// Throttled selection tick (≤ 25 Hz) for continuous gestures — stays under
    /// the system 32 Hz haptic rate limit so no feedback is dropped.
    static func selectionTick() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTick >= 0.04 else { return }
        lastTick = now
        dragSelection.selectionChanged()
        dragSelection.prepare()
    }
}
