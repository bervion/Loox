import SwiftUI

/// Soft ambient elevation (Design System `tokens/elevation.css`) — never glowing.
/// 0 none · 1 resting card · 2 menus · 3 floating tab bar / sheets · sheet (upward).
nonisolated enum Elevation: Sendable {
    case level0, level1, level2, level3, sheet
    /// Deliberate exception: a resting card sitting on a PLAIN WHITE canvas
    /// (welcome carousel) — the flat grouped style has no gray to separate it,
    /// so this one keeps the old soft card shadow.
    case cardOnWhite

    var radius: CGFloat {
        switch self {
        case .level0: return 0
        case .level1: return 2
        case .level2: return 14
        case .cardOnWhite: return 14
        case .level3: return 30
        case .sheet:  return 40
        }
    }

    var y: CGFloat {
        switch self {
        case .level0: return 0
        case .level1: return 1
        case .level2: return 4
        case .cardOnWhite: return 4
        case .level3: return 10
        case .sheet:  return -8
        }
    }
}

extension View {
    /// Apply a Design-System ambient shadow. Opacity adapts to light/dark like the DS
    /// `--shadow-ambient` token (subtle in light, deeper in dark) — soft, not a glow.
    func elevation(_ level: Elevation) -> some View {
        modifier(ElevationModifier(level: level))
    }
}

private struct ElevationModifier: ViewModifier {
    let level: Elevation
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        // Flat rebrand: resting cards (level1/2) cast NO shadow — Apple grouped
        // style, plain white cards on the gray canvas. Only floating chrome
        // (level3 / sheet) still lifts.
        let flat = level == .level0 || level == .level1 || level == .level2
        let opacity = flat ? 0 : (scheme == .dark ? 0.55 : 0.10)
        return content.shadow(color: .black.opacity(opacity), radius: level.radius, y: level.y)
    }
}
