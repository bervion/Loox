import Foundation

/// A named wallpaper preset shown in the gallery (Phase 05).
struct WallpaperPreset: Identifiable, Equatable {
    let id: String
    let wallpaper: Wallpaper
}

/// Curated, tasteful presets — gradients + a few animated mesh palettes (incl.
/// Telegram's signature). Patterns ship once their SVG assets are added.
enum WallpaperPresets {
    static let gradients: [WallpaperPreset] = [
        WallpaperPreset(id: "sky", wallpaper: .gradient(colors: [0x6EA8FE, 0xC9E0FF], settings: WallpaperSettings(rotation: 90))),
        WallpaperPreset(id: "dusk", wallpaper: .gradient(colors: [0x3A2C6E, 0x8E6AD6], settings: WallpaperSettings(rotation: 60))),
        WallpaperPreset(id: "mint", wallpaper: .gradient(colors: [0x1E8B6A, 0xBDF0DC], settings: WallpaperSettings(rotation: 90))),
        WallpaperPreset(id: "sunset", wallpaper: .gradient(colors: [0xC4571E, 0xF0B45A], settings: WallpaperSettings(rotation: 75))),
        WallpaperPreset(id: "ink", wallpaper: .gradient(colors: [0x0E1A2B, 0x24405E], settings: WallpaperSettings(rotation: 90))),
        WallpaperPreset(id: "graphite", wallpaper: .gradient(colors: [0x1C1C1E, 0x3A3A3C], settings: WallpaperSettings(rotation: 90))),
    ]

    static let meshes: [WallpaperPreset] = [
        WallpaperPreset(id: "telegram", wallpaper: .mesh(colors: [0x7FA381, 0xFFF5C5, 0x336F55, 0xFBE37D])),
        WallpaperPreset(id: "aurora", wallpaper: .mesh(colors: [0x2B5876, 0x4E4376, 0x8E2DE2, 0x4A00E0])),
        WallpaperPreset(id: "ember", wallpaper: .mesh(colors: [0x3A1C71, 0xD76D77, 0xFFAF7B, 0x3A1C71])),
    ]

    static let patterns: [WallpaperPreset] = [
        WallpaperPreset(id: "p-dots", wallpaper: .pattern(id: "dots", colors: [0x1B2735, 0x2A3F55], settings: WallpaperSettings(intensity: 0.5, rotation: 90))),
        WallpaperPreset(id: "p-rings", wallpaper: .pattern(id: "rings", colors: [0x2B1A3D, 0x4A2D63], settings: WallpaperSettings(intensity: 0.5, rotation: 90))),
        WallpaperPreset(id: "p-waves", wallpaper: .pattern(id: "waves", colors: [0x10303A, 0x1C5560], settings: WallpaperSettings(intensity: 0.5, rotation: 90))),
        WallpaperPreset(id: "p-plus", wallpaper: .pattern(id: "plus", colors: [0x2A2310, 0x4A3D1C], settings: WallpaperSettings(intensity: 0.5, rotation: 90))),
        WallpaperPreset(id: "p-diagonal", wallpaper: .pattern(id: "diagonal", colors: [0x1A2B1A, 0x2D4A2D], settings: WallpaperSettings(intensity: 0.5, rotation: 90))),
        WallpaperPreset(id: "p-grid", wallpaper: .pattern(id: "grid", colors: [0x202024, 0x35353C], settings: WallpaperSettings(intensity: 0.45, rotation: 90))),
    ]

    static let all: [WallpaperPreset] = gradients + patterns + meshes
}
