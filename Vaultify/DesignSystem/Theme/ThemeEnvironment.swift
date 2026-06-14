import SwiftUI

// SwiftUI bridge for the active theme: an environment value so any view can read
// resolved colors, plus the `Color(rgb:)` convenience used across the design system.

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = BuiltinThemes.day
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}
