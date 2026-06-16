import SwiftUI

/// Motion tokens (Design System `tokens/elevation.css`): short, low-bounce,
/// Apple-native. Durations collapse to instant under Reduce Motion via `Animation.vault`.
nonisolated enum Motion {
    // Durations (seconds)
    static let fast: Double = 0.14
    static let base: Double = 0.20
    static let medium: Double = 0.26
    static let slow: Double = 0.32

    /// Standard easing — Apple-like ease-out.
    static let standard = Animation.timingCurve(0.32, 0.72, 0, 1, duration: base)

    /// Low-bounce spring for the tab indicator and selection changes.
    static let spring = Animation.spring(response: 0.34, dampingFraction: 0.86)

    /// Press feedback scale (DS press = 0.97).
    static let pressScale: CGFloat = 0.97
}

extension Animation {
    /// A Design-System animation that becomes instant (`nil`) under Reduce Motion.
    /// Pass to `.animation(_:value:)` / `withAnimation` so motion respects the setting.
    static func vault(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}
