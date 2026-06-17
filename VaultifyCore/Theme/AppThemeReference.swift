import Foundation

/// The four built-in base themes. Two light (day / day-classic), two dark
/// (night / night-tinted). Accent + wallpaper are layered on top separately.
nonisolated enum BuiltinTheme: String, Codable, Sendable, CaseIterable, Identifiable, Equatable {
    case day, dayClassic, night, nightTinted

    var id: String { rawValue }
    var isDark: Bool { self == .night || self == .nightTinted }

    /// Themes offered in the picker grid (Design System = light + dark). `dayClassic` /
    /// `nightTinted` stay valid (palettes retained, still resolve if already selected)
    /// but are no longer offered for new selection.
    static let selectable: [BuiltinTheme] = [.day, .night]
}

/// Reference to a theme the user can select: a built-in base, or a saved custom
/// theme (Phase 06). `key` is the stable dictionary key for per-theme accent /
/// wallpaper overrides.
nonisolated enum AppThemeReference: Codable, Sendable, Equatable, Hashable {
    case builtin(BuiltinTheme)
    case custom(UUID)

    var key: String {
        switch self {
        case .builtin(let base): return "builtin.\(base.rawValue)"
        case .custom(let id): return "custom.\(id.uuidString)"
        }
    }
}
