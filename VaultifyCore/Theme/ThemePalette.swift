import Foundation

/// Pure resolution of `ThemeSettings` → a concrete `AppTheme`. `nonisolated` so it
/// can run off-main and from the AutoFill extension.
nonisolated enum ThemePalette {
    /// Base palette for a reference, with custom-theme accent already applied.
    static func base(_ ref: AppThemeReference, settings: ThemeSettings) -> AppTheme {
        switch ref {
        case .builtin(let builtin):
            return BuiltinThemes.palette(builtin)
        case .custom(let id):
            guard let custom = settings.customTheme(id) else { return BuiltinThemes.day }
            var theme = BuiltinThemes.palette(custom.base)
            theme.reference = ref
            return theme.recolored(accent: custom.accent.rgb)
        }
    }

    /// Pick the active reference for the current conditions (auto-night aware).
    static func activeReference(_ settings: ThemeSettings, systemIsDark: Bool, brightness: Double, now: Date = Date()) -> AppThemeReference {
        switch AutoNight.prefersNight(settings.autoNight, systemIsDark: systemIsDark, now: now, brightness: brightness) {
        case .some(true): return settings.nightTheme
        default: return settings.theme
        }
    }

    /// Fully-resolved active theme: pick day/night, then apply any per-theme accent
    /// override (built-in themes only; custom themes carry their own accent).
    static func resolve(_ settings: ThemeSettings, systemIsDark: Bool, brightness: Double, now: Date = Date()) -> AppTheme {
        let ref = activeReference(settings, systemIsDark: systemIsDark, brightness: brightness, now: now)
        var theme = base(ref, settings: settings)
        if case .builtin = ref, let accent = settings.accents[ref.key] {
            theme = theme.recolored(accent: accent.rgb)
        }
        return theme
    }

    /// The wallpaper for the active reference: a custom theme's own, else the user's
    /// per-theme override, else the built-in default.
    static func activeWallpaper(_ settings: ThemeSettings, systemIsDark: Bool, brightness: Double, now: Date = Date()) -> Wallpaper {
        let ref = activeReference(settings, systemIsDark: systemIsDark, brightness: brightness, now: now)
        if case .custom(let id) = ref, let custom = settings.customTheme(id) {
            return custom.wallpaper
        }
        if let override = settings.wallpaperOverride(for: ref) {
            return override
        }
        if case .builtin(let builtin) = ref {
            return BuiltinThemes.defaultWallpaper(builtin)
        }
        return .none
    }
}
