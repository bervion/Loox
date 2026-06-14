import Foundation

/// A named wallpaper preset shown in the gallery (Phase 05).
struct WallpaperPreset: Identifiable, Equatable {
    let id: String
    let wallpaper: Wallpaper
}

/// Curated presets. Patterns + the per-theme glow are derived from the active accent so
/// the background harmonizes with the theme and the app's cards stand out on top.
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

    /// A 4-color glowing mesh palette derived from an accent. Tuned so the app's cards
    /// (the elevated surface) stand out: deep shades for dark themes, soft for light.
    static func glowColors(accent: UInt32, dark: Bool) -> [UInt32] {
        let base: UInt32 = dark ? 0x000000 : 0xFFFFFF
        let amounts: [Double] = dark ? [0.74, 0.56, 0.84, 0.66] : [0.68, 0.50, 0.80, 0.60]
        return amounts.map { RGBMath.blend(accent, base, $0) }
    }

    /// Pattern presets over an accent-derived glow mesh (the line-art glows on the
    /// animated gradient, Telegram-style). Built per theme in the gallery.
    static func patterns(accent: UInt32, dark: Bool) -> [WallpaperPreset] {
        let glow = glowColors(accent: accent, dark: dark)
        return PatternStyle.allCases.map { style in
            WallpaperPreset(id: "p-\(style.rawValue)",
                            wallpaper: .pattern(id: style.rawValue, colors: glow,
                                                settings: WallpaperSettings(intensity: 0.55)))
        }
    }

    static let all: [WallpaperPreset] = gradients + patterns(accent: 0x3CA7F0, dark: true) + meshes
}
