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

extension Color {
    /// Build a SwiftUI `Color` from a packed `0xRRGGBB` theme value.
    init(rgb: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: opacity)
    }
}
