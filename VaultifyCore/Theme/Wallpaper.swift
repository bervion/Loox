import Foundation

/// Per-wallpaper tuning. Rendering lands in Phase 03/04; the model is defined now
/// so `ThemeSettings`' Codable schema is stable from Phase 01.
nonisolated struct WallpaperSettings: Codable, Sendable, Equatable {
    var blur: Bool
    var dimAlpha: Double      // 0…1 dark scrim over the wallpaper (legibility)
    var intensity: Double     // 0…1 pattern tint strength (soft-light)
    var rotation: Int         // gradient rotation, degrees
    var motion: Bool          // parallax on device tilt

    init(blur: Bool = false, dimAlpha: Double = 0, intensity: Double = 0.5, rotation: Int = 0, motion: Bool = false) {
        self.blur = blur
        self.dimAlpha = dimAlpha
        self.intensity = intensity
        self.rotation = rotation
        self.motion = motion
    }

    static let none = WallpaperSettings()
}

/// App-wide background behind the canvas / lock screens. `none` falls back to the
/// theme's solid background. Adapted from Telegram's `TelegramWallpaper` (no chat).
nonisolated enum Wallpaper: Codable, Sendable, Equatable {
    case none
    case solid(UInt32)
    case gradient(colors: [UInt32], settings: WallpaperSettings)
    case mesh(colors: [UInt32])                              // animated (Phase 04)
    case pattern(id: String, colors: [UInt32], settings: WallpaperSettings)
    case image(fileName: String, settings: WallpaperSettings)
}
