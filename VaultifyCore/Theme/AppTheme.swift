import Foundation

/// Resolved, immutable semantic palette for one active appearance. Generic app
/// chrome only — no chat. Colors are packed `0xRRGGBB`; convert at the UI edge with
/// `Color(rgb:)` / `UIColor(rgb:)`. Built by `BuiltinThemes`, recolored by accent.
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
    func recolored(accent: UInt32) -> AppTheme {
        var theme = self
        theme.accent = accent
        theme.switchOn = accent
        theme.checkmark = accent
        let white: UInt32 = 0xFFFFFF
        let black: UInt32 = 0x000000
        theme.accentForeground = RGBMath.luminance(accent) > 0.6 ? black : white
        theme.selection = RGBMath.blend(accent, isDark ? background : white, isDark ? 0.80 : 0.88)
        return theme
    }
}
