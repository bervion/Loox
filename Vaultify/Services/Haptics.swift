import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Lightweight haptic feedback wrappers. macOS has no Taptic engine here → the
/// calls compile to no-ops, keeping call sites platform-agnostic.
@MainActor enum Haptics {
    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    static func warning() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
    static func error() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }
    static func tap() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    static func rigid() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        #endif
    }
    static func selection() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    // MARK: Continuous-gesture selection ticks (sliders, wheels)

    #if canImport(UIKit)
    /// Reused, kept-warm generator for repeated ticks during a drag. Spamming
    /// throwaway generators (or firing faster than the system's 32 Hz feedback
    /// limit) floods the console with "exceeds rate-limit" drops and wastes work.
    private static let dragSelection = UISelectionFeedbackGenerator()
    #endif
    private static var lastTick: TimeInterval = 0

    /// Warm up the selection engine at the start of a drag gesture. Resets the
    /// throttle so the drag's first tick fires immediately (snappier feel).
    static func prepareSelection() {
        lastTick = 0
        #if canImport(UIKit)
        dragSelection.prepare()
        #endif
    }

    /// Throttled selection tick (≤ 25 Hz) for continuous gestures — stays under
    /// the system 32 Hz haptic rate limit so no feedback is dropped.
    static func selectionTick() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTick >= 0.04 else { return }
        lastTick = now
        #if canImport(UIKit)
        dragSelection.selectionChanged()
        dragSelection.prepare()
        #endif
    }
}
