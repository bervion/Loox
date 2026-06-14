import SwiftUI

// SwiftUI bridge for the active theme: an environment value so any view can read
// resolved colors, plus the `Color(rgb:)` convenience used across the design system.

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = BuiltinThemes.day
}

private struct MeshPhaseKey: EnvironmentKey { static let defaultValue = 0 }
private struct MeshAnimatedKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }

    /// Drives the animated mesh wallpaper morph (bumped by `ThemeStore`).
    var meshPhase: Int {
        get { self[MeshPhaseKey.self] }
        set { self[MeshPhaseKey.self] = newValue }
    }

    /// Whether the mesh morph animates (false honors Reduce Motion).
    var meshAnimated: Bool {
        get { self[MeshAnimatedKey.self] }
        set { self[MeshAnimatedKey.self] = newValue }
    }
}
