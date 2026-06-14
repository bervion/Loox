import Foundation

/// A user-created theme: a built-in base recolored by an accent, with a wallpaper.
/// Created / edited / exported in Phase 06; the model is defined now so the
/// persisted `ThemeSettings` schema is stable.
nonisolated struct CustomTheme: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var base: BuiltinTheme
    var accent: AppAccentColor
    var wallpaper: Wallpaper

    init(
        id: UUID = UUID(),
        name: String,
        base: BuiltinTheme,
        accent: AppAccentColor = .default,
        wallpaper: Wallpaper = .none
    ) {
        self.id = id
        self.name = name
        self.base = base
        self.accent = accent
        self.wallpaper = wallpaper
    }
}
