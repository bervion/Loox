import Foundation

/// Literal palettes for the four built-in themes. Values are Polaris-derived; the
/// Phase 02 audit tunes them for contrast. Accent + wallpaper layer on top.
nonisolated enum BuiltinThemes {
    static func palette(_ theme: BuiltinTheme) -> AppTheme {
        switch theme {
        case .day: return day
        case .dayClassic: return dayClassic
        case .night: return night
        case .nightTinted: return nightTinted
        }
    }

    static let day = AppTheme(
        reference: .builtin(.day), isDark: false,
        background: 0xFFFFFF, secondaryBackground: 0xF2F2F7, groupedBackground: 0xF2F2F7,
        elevatedBackground: 0xFFFFFF, barBackground: 0xF9F9F9,
        primaryText: 0x111213, secondaryText: 0x6D7175, tertiaryText: 0x9BA1A6, placeholderText: 0xB0B4B8,
        accent: 0x2C6ECB, accentForeground: 0xFFFFFF,
        separator: 0xE3E5E7, border: 0xD2D5D8, controlBackground: 0xE9EBED,
        switchOn: 0x2C6ECB, checkmark: 0x2C6ECB, selection: 0xEAF1FB,
        destructive: 0xD72C0D, success: 0x1A8B5E, warning: 0xB98900, overlayDim: 0x000000)

    static let dayClassic = AppTheme(
        reference: .builtin(.dayClassic), isDark: false,
        background: 0xFFFFFF, secondaryBackground: 0xF4F1EA, groupedBackground: 0xEFE9DC,
        elevatedBackground: 0xFFFFFF, barBackground: 0xF6F2EA,
        primaryText: 0x14130F, secondaryText: 0x726B5E, tertiaryText: 0x9C9482, placeholderText: 0xB4AC98,
        accent: 0x2C6ECB, accentForeground: 0xFFFFFF,
        separator: 0xE6DECF, border: 0xD8CFBC, controlBackground: 0xEBE4D5,
        switchOn: 0x2C6ECB, checkmark: 0x2C6ECB, selection: 0xEFEADB,
        destructive: 0xC4391B, success: 0x1A8B5E, warning: 0xB07D00, overlayDim: 0x000000)

    static let night = AppTheme(
        reference: .builtin(.night), isDark: true,
        background: 0x000000, secondaryBackground: 0x1C1C1E, groupedBackground: 0x000000,
        elevatedBackground: 0x1C1C1E, barBackground: 0x121214,
        primaryText: 0xFFFFFF, secondaryText: 0x98989F, tertiaryText: 0x6C6C70, placeholderText: 0x5A5A5E,
        accent: 0x5B9CF6, accentForeground: 0xFFFFFF,
        separator: 0x2C2C2E, border: 0x38383A, controlBackground: 0x2C2C2E,
        switchOn: 0x5B9CF6, checkmark: 0x5B9CF6, selection: 0x1E2A3A,
        destructive: 0xFF6B5B, success: 0x34C789, warning: 0xE3B341, overlayDim: 0x000000)

    static let nightTinted = AppTheme(
        reference: .builtin(.nightTinted), isDark: true,
        background: 0x18222D, secondaryBackground: 0x1C2733, groupedBackground: 0x18222D,
        elevatedBackground: 0x213040, barBackground: 0x1B2735,
        primaryText: 0xFFFFFF, secondaryText: 0x8AA0B6, tertiaryText: 0x6A7E92, placeholderText: 0x5B6E82,
        accent: 0x3CA7F0, accentForeground: 0xFFFFFF,
        separator: 0x2A3848, border: 0x33445A, controlBackground: 0x243343,
        switchOn: 0x3CA7F0, checkmark: 0x3CA7F0, selection: 0x223247,
        destructive: 0xFF6B5B, success: 0x34C789, warning: 0xE3B341, overlayDim: 0x000000)
}
