import SwiftUI

/// Renders a `Wallpaper` full-bleed behind a screen. The `.mesh` case is a static
/// gradient placeholder here; Phase 04 swaps in the animated (CAKeyframeAnimation)
/// renderer behind the same view.
struct WallpaperView: View {
    let wallpaper: Wallpaper
    var fallbackColor: Color

    var body: some View {
        content.ignoresSafeArea()
    }

    @ViewBuilder private var content: some View {
        switch wallpaper {
        case .none:
            fallbackColor
        case .solid(let rgb):
            Color(rgb: rgb)
        case .gradient(let colors, let settings):
            gradient(colors, settings)
        case .mesh(let colors):
            gradient(colors, WallpaperSettings(rotation: 45))
        case .pattern(_, let colors, let settings):
            gradient(colors, settings)            // pattern overlay added once assets ship
        case .image(let fileName, let settings):
            imageView(fileName, settings)
        }
    }

    private func gradient(_ rgbs: [UInt32], _ settings: WallpaperSettings) -> some View {
        let colors = (rgbs.isEmpty ? [0x808080] : rgbs).map { Color(rgb: $0) }
        let (start, end) = Self.endpoints(forDegrees: settings.rotation)
        return LinearGradient(colors: colors, startPoint: start, endPoint: end)
            .modifier(WallpaperEffects(settings: settings))
    }

    @ViewBuilder private func imageView(_ fileName: String, _ settings: WallpaperSettings) -> some View {
        if let image = WallpaperStorage.loadImage(named: fileName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .modifier(WallpaperEffects(settings: settings))
        } else {
            fallbackColor
        }
    }

    /// Map a rotation (degrees) to gradient start/end unit points (0° = top→bottom).
    static func endpoints(forDegrees degrees: Int) -> (UnitPoint, UnitPoint) {
        let radians = Double(degrees) * .pi / 180
        let dx = sin(radians) / 2
        let dy = -cos(radians) / 2
        return (UnitPoint(x: 0.5 - dx, y: 0.5 - dy), UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
    }
}

/// Blur + dim scrim shared by gradient/image wallpapers.
private struct WallpaperEffects: ViewModifier {
    let settings: WallpaperSettings
    func body(content: Content) -> some View {
        content
            .blur(radius: settings.blur ? 28 : 0)
            .overlay(Color.black.opacity(settings.dimAlpha))
    }
}

extension View {
    /// Place the active wallpaper behind this view (canvas / lock / onboarding).
    func themedWallpaper(_ wallpaper: Wallpaper, fallback: Color) -> some View {
        background(WallpaperView(wallpaper: wallpaper, fallbackColor: fallback))
    }
}
