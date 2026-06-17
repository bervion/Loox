import Foundation

/// The seven Design-System accent presets (Telegram-style live theming). Each carries a
/// light + dark hue so the accent re-tints correctly per theme; soft / press / on-accent
/// are derived from these in `AppTheme+Tokens`. Values mirror `Design System/tokens/accents.css`.
nonisolated enum AccentPreset: String, Sendable, CaseIterable, Identifiable {
    case blue, indigo, teal, purple, pink, graphite, mono

    var id: String { rawValue }

    /// Hue used on light themes.
    var lightRGB: UInt32 {
        switch self {
        case .blue: return 0x2563EB
        case .indigo: return 0x5145CD
        case .teal: return 0x0E8A7D
        case .purple: return 0x7C3AED
        case .pink: return 0xD6256E
        case .graphite: return 0x4B4B50
        case .mono: return 0x1C1C1E
        }
    }

    /// Hue used on dark themes.
    var darkRGB: UInt32 {
        switch self {
        case .blue: return 0x4C8DFF
        case .indigo: return 0x8B80FF
        case .teal: return 0x2FD0BF
        case .purple: return 0xB388FF
        case .pink: return 0xFF77AB
        case .graphite: return 0xAEAEB2
        case .mono: return 0xFFFFFF
        }
    }

    /// Resolve the hue for the active theme's light/dark mode.
    func rgb(isDark: Bool) -> UInt32 { isDark ? darkRGB : lightRGB }
}

extension AccentPreset: Codable {
    /// Tolerant decode: presets removed in older builds (cyan/green/orange/red/yellow)
    /// or any unknown raw value fall back to `.blue` so persisted settings still load.
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AccentPreset(rawValue: raw) ?? .blue
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A chosen accent. `customRGB` is retained only for backward-compatible decoding of
/// older settings; custom RGB accents were removed (accents are the 7 presets), so it is
/// no longer applied when resolving the color.
nonisolated struct AppAccentColor: Codable, Sendable, Equatable {
    var base: AccentPreset
    var customRGB: UInt32?

    init(base: AccentPreset = .blue, customRGB: UInt32? = nil) {
        self.base = base
        self.customRGB = customRGB
    }

    /// Resolve the preset hue for the active theme's light/dark mode.
    func rgb(isDark: Bool) -> UInt32 { base.rgb(isDark: isDark) }

    /// Back-compat convenience (light hue). Prefer `rgb(isDark:)`.
    var rgb: UInt32 { base.lightRGB }

    static let `default` = AppAccentColor(base: .blue)
}
