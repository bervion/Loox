import Foundation

/// Literal palettes for the four built-in themes. Values are Polaris-derived; the
/// Phase 02 audit tunes them for contrast. Accent + wallpaper layer on top.
nonisolated enum BuiltinThemes {
    static func palette(_ theme: BuiltinTheme) -> AppTheme {
        var base: AppTheme
        switch theme {
        case .day: base = day
        case .dayClassic: base = dayClassic
        case .night: base = night
        case .nightTinted: base = nightTinted
        }
        // Derive the on-accent foreground from the accent by real WCAG contrast so every
        // theme's filled controls (buttons / selected chips) keep legible text. Single
        // source of truth — the literal `accentForeground` below is just a placeholder.
        base.accentForeground = RGBMath.onColor(base.accent)
        return base
    }

    /// Default wallpaper shipped with each built-in theme. Day, Day Classic, and
    /// Night stay clean (just the theme background) so "Default" matches the look of
    /// the theme card — a plain dark canvas for Night. Only Night Tinted ships a
    /// subtle gradient, since being tinted is the point of that variant.
    static func defaultWallpaper(_ theme: BuiltinTheme) -> Wallpaper {
        switch theme {
        case .day, .dayClassic, .night: return .none
        case .nightTinted: return .gradient(colors: [0x16222E, 0x1E2D3C], settings: WallpaperSettings(rotation: 90))
        }
    }

    // Retuned to Design System tokens (`Design System/tokens/colors.css`, light).
    static let day = AppTheme(
        reference: .builtin(.day), isDark: false,
        background: 0xFFFFFF, secondaryBackground: 0xF2F2F7, groupedBackground: 0xF2F2F7,
        elevatedBackground: 0xFFFFFF, barBackground: 0xFFFFFF,
        primaryText: 0x1C1C1E, secondaryText: 0x4B4B50, tertiaryText: 0x8A8A8E, placeholderText: 0xB6B6BB,
        accent: 0x2563EB, accentForeground: 0xFFFFFF,
        separator: 0xD8D8DE, border: 0xC7C7CC, controlBackground: 0xE9E9EF,
        switchOn: 0x2563EB, checkmark: 0x2563EB, selection: 0xE6EDFD,
        destructive: 0xE5484D, success: 0x1A8E5F, warning: 0xB06F00, overlayDim: 0x000000)

    static let dayClassic = AppTheme(
        reference: .builtin(.dayClassic), isDark: false,
        background: 0xFFFFFF, secondaryBackground: 0xF4F1EA, groupedBackground: 0xEFE9DC,
        elevatedBackground: 0xFFFFFF, barBackground: 0xF6F2EA,
        primaryText: 0x14130F, secondaryText: 0x726B5E, tertiaryText: 0x9C9482, placeholderText: 0xB4AC98,
        accent: 0x2C6ECB, accentForeground: 0xFFFFFF,
        separator: 0xE6DECF, border: 0xD8CFBC, controlBackground: 0xEBE4D5,
        switchOn: 0x2C6ECB, checkmark: 0x2C6ECB, selection: 0xEFEADB,
        destructive: 0xC4391B, success: 0x1A8B5E, warning: 0xB07D00, overlayDim: 0x000000)

    // Retuned to Design System tokens (`Design System/tokens/colors.css`, dark).
    static let night = AppTheme(
        reference: .builtin(.night), isDark: true,
        background: 0x000000, secondaryBackground: 0x1C1C1E, groupedBackground: 0x000000,
        elevatedBackground: 0x1C1C1E, barBackground: 0x1C1C1E,
        primaryText: 0xFFFFFF, secondaryText: 0xC7C7CC, tertiaryText: 0x8E8E93, placeholderText: 0x5A5A5E,
        // On-accent foreground is derived from the resolved accent by WCAG contrast in
        // `palette()` / `recolored()`, so any preset stays legible on filled controls.
        accent: 0x4C8DFF, accentForeground: 0xFFFFFF,
        separator: 0x38383A, border: 0x38383A, controlBackground: 0x2C2C2E,
        switchOn: 0x4C8DFF, checkmark: 0x4C8DFF, selection: 0x16294B,
        destructive: 0xFF5C5C, success: 0x30D158, warning: 0xFFD60A, overlayDim: 0x000000)

    static let nightTinted = AppTheme(
        reference: .builtin(.nightTinted), isDark: true,
        background: 0x18222D, secondaryBackground: 0x1C2733, groupedBackground: 0x18222D,
        elevatedBackground: 0x213040, barBackground: 0x1B2735,
        primaryText: 0xFFFFFF, secondaryText: 0x8AA0B6, tertiaryText: 0x6A7E92, placeholderText: 0x5B6E82,
        // Deep azure so white text on a filled accent clears WCAG AA (~5.1:1) while
        // keeping the tinted (blue-leaning) character of this variant.
        accent: 0x1C72B5, accentForeground: 0xFFFFFF,
        separator: 0x36465A, border: 0x3C5068, controlBackground: 0x243343,
        switchOn: 0x1C72B5, checkmark: 0x1C72B5, selection: 0x223247,
        destructive: 0xFF6B5B, success: 0x34C789, warning: 0xE3B341, overlayDim: 0x000000)
}
