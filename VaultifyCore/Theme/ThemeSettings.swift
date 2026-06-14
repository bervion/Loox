import Foundation

/// Global text-size scale (applied app-wide in Phase 05).
nonisolated enum FontScale: String, Codable, Sendable, CaseIterable, Identifiable {
    case xSmall, small, regular, large, xLarge, xxLarge

    var id: String { rawValue }

    var multiplier: Double {
        switch self {
        case .xSmall: return 0.85
        case .small: return 0.92
        case .regular: return 1.0
        case .large: return 1.10
        case .xLarge: return 1.20
        case .xxLarge: return 1.32
        }
    }
}

/// All non-secret appearance preferences, persisted as JSON in the App Group so the
/// AutoFill extension reads the same theme. Schema is stable from Phase 01 (wallpaper
/// / custom-theme / font-scale fields exist now though their UI lands in later phases).
nonisolated struct ThemeSettings: Codable, Sendable, Equatable {
    var theme: AppThemeReference                 // primary / day theme
    var nightTheme: AppThemeReference            // used when auto-night triggers
    var accents: [String: AppAccentColor]        // per theme-key accent override
    var wallpapers: [String: Wallpaper]          // per theme-key wallpaper
    var customThemes: [CustomTheme]
    var autoNight: AutoNightSetting
    var fontScale: FontScale
    var reduceMotion: Bool

    init(
        theme: AppThemeReference = .builtin(.day),
        nightTheme: AppThemeReference = .builtin(.night),
        accents: [String: AppAccentColor] = [:],
        wallpapers: [String: Wallpaper] = [:],
        customThemes: [CustomTheme] = [],
        autoNight: AutoNightSetting = .system,
        fontScale: FontScale = .regular,
        reduceMotion: Bool = false
    ) {
        self.theme = theme
        self.nightTheme = nightTheme
        self.accents = accents
        self.wallpapers = wallpapers
        self.customThemes = customThemes
        self.autoNight = autoNight
        self.fontScale = fontScale
        self.reduceMotion = reduceMotion
    }

    static let `default` = ThemeSettings()

    /// Explicit per-theme accent override, if the user set one (nil → use the
    /// built-in's native accent).
    func accentOverride(for ref: AppThemeReference) -> AppAccentColor? { accents[ref.key] }

    func wallpaper(for ref: AppThemeReference) -> Wallpaper { wallpapers[ref.key] ?? .none }

    /// Explicit per-theme wallpaper override (nil → use the built-in default).
    func wallpaperOverride(for ref: AppThemeReference) -> Wallpaper? { wallpapers[ref.key] }

    func customTheme(_ id: UUID) -> CustomTheme? { customThemes.first { $0.id == id } }
}
