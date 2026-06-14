import Foundation

/// Preset accent swatches (Polaris-derived hues). The user can also pick a fully
/// custom RGB.
nonisolated enum AccentPreset: String, Codable, Sendable, CaseIterable, Identifiable {
    case blue, cyan, teal, green, orange, pink, purple, red, yellow, graphite

    var id: String { rawValue }

    var rgb: UInt32 {
        switch self {
        case .blue: return 0x2C6ECB
        case .cyan: return 0x00A0AC
        case .teal: return 0x16A394
        case .green: return 0x1A8B5E
        case .orange: return 0xC4571E
        case .pink: return 0xE0218A
        case .purple: return 0x9C6ADE
        case .red: return 0xD72C0D
        case .yellow: return 0xB98900
        case .graphite: return 0x6D7175
        }
    }
}

/// A chosen accent — a preset, optionally overridden by a custom RGB.
nonisolated struct AppAccentColor: Codable, Sendable, Equatable {
    var base: AccentPreset
    var customRGB: UInt32?

    init(base: AccentPreset = .blue, customRGB: UInt32? = nil) {
        self.base = base
        self.customRGB = customRGB
    }

    var rgb: UInt32 { customRGB ?? base.rgb }

    static let `default` = AppAccentColor(base: .blue)
}
