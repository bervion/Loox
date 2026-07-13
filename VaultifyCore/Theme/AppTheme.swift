import Foundation

/// Resolved, immutable semantic palette for one active appearance. Generic app
/// chrome only — no chat. Colors are packed `0xRRGGBB`; convert at the UI edge with
/// `Color(rgb:)` / `PlatformColor(rgb:)`. Built by `BuiltinThemes`, recolored by accent.
nonisolated struct AppTheme: Sendable, Equatable {
    var reference: AppThemeReference
    var isDark: Bool

    // Backgrounds
    var background: UInt32
    var secondaryBackground: UInt32
    var groupedBackground: UInt32
    var elevatedBackground: UInt32     // cards / floating surfaces over wallpaper
    var barBackground: UInt32          // nav / tab bar

    // Text
    var primaryText: UInt32
    var secondaryText: UInt32
    var tertiaryText: UInt32
    var placeholderText: UInt32

    // Accent
    var accent: UInt32
    var accentForeground: UInt32       // text / icon drawn on top of `accent`
    /// Brand link hue paired with the accent (nil → derive from `accent`).
    /// The brand blue fill (#009DFF) pairs with the brand link blue (#0065F4).
    var linkAccent: UInt32? = nil

    // Lines & controls
    var separator: UInt32
    var border: UInt32
    var controlBackground: UInt32
    var switchOn: UInt32
    var checkmark: UInt32
    var selection: UInt32

    // Status
    var destructive: UInt32
    var success: UInt32
    var warning: UInt32

    // Overlay
    var overlayDim: UInt32

    /// Return a copy recolored by `accent`, deriving the accent-tied tokens
    /// (switch/check/selection/on-accent foreground).
    func recolored(accent rawAccent: UInt32) -> AppTheme {
        var theme = self
        // Controlled Contrast fill guard: the accent must read as a SHAPE
        // (≥3:1, WCAG non-text) on both canvas surfaces. Curated presets pass
        // untouched (non-destructive); an extreme input — black accent on a
        // black theme from a future custom/import path — is pulled just far
        // enough to stay visible instead of sinking into the background.
        // Both guards shift the same direction (toward the mode's on-color).
        var accent = RGBMath.ensureContrast(rawAccent, on: groupedBackground, floor: 3.0)
        accent = RGBMath.ensureContrast(accent, on: elevatedBackground, floor: 3.0)
        theme.accent = accent
        // Brand pairing: the brand blue ships its own link hue instead of a
        // derived darkening; other presets keep the derived text rank.
        theme.linkAccent = (rawAccent == 0x009DFF) ? 0x0065F4 : nil
        // The themed toggle draws a WHITE knob on the ON track (native UISwitch
        // anatomy) — a white/near-white accent (mono on dark) makes knob and
        // track one shape. Guard the track against the knob at 2.0:1, the ratio
        // the native iOS green track keeps against its own knob (~2.05:1), so
        // every preset feels stock and extreme accents settle into a deliberate
        // gray instead of vanishing.
        theme.switchOn = RGBMath.ensureContrast(accent, on: 0xFFFFFF, floor: 2.0)
        theme.checkmark = accent
        // White-preferred on-accent (iOS convention for coloured controls) so text/icons on
        // filled accent buttons read white on saturated accents (e.g. dark-mode blue), only
        // falling back to black for genuinely light tints.
        theme.accentForeground = RGBMath.onAccent(accent)
        let white: UInt32 = 0xFFFFFF
        theme.selection = RGBMath.blend(accent, isDark ? background : white, isDark ? 0.80 : 0.88)
        return theme
    }
}
