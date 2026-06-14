import Foundation

/// Presentation color for a folder ("Space"). Deliberately UI-free (no SwiftUI
/// import) so it compiles in VaultifyCore for both the app and the AutoFill
/// extension; the app layer resolves the `light`/`dark` hex into a trait-aware
/// `Color` via `VaultColors.dynamic`. Hues mirror `VaultColors.category` for a
/// consistent palette across the app.
nonisolated enum FolderColor: String, Codable, CaseIterable, Sendable, Identifiable {
    case blue, green, purple, teal, orange, indigo, amber, red, pink, gray

    var id: String { rawValue }

    /// Hex (0xRRGGBB) used in light appearance.
    var light: UInt32 {
        switch self {
        case .blue: 0x2C6ECB
        case .green: 0x1A8B5E
        case .purple: 0x9C6ADE
        case .teal: 0x00A0AC
        case .orange: 0xC4571E
        case .indigo: 0x5B5BD6
        case .amber: 0xB98900
        case .red: 0xD72C0D
        case .pink: 0xC42E6E
        case .gray: 0x6D7175
        }
    }

    /// Hex (0xRRGGBB) used in dark appearance (brighter for contrast).
    var dark: UInt32 {
        switch self {
        case .blue: 0x5B9CF6
        case .green: 0x34C789
        case .purple: 0xBD93F9
        case .teal: 0x26C9D3
        case .orange: 0xF08A4B
        case .indigo: 0x9B9BF0
        case .amber: 0xE3B341
        case .red: 0xFF6B5B
        case .pink: 0xF06AA5
        case .gray: 0x9BA1A6
        }
    }

    /// Order shown in the color picker.
    static var palette: [FolderColor] { allCases }
}
