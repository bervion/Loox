import SwiftUI

/// Procedural, tintable line-art patterns (no bundled assets) — a tasteful take on
/// Telegram's pattern wallpapers. Drawn over a gradient base and blended soft-light.
enum PatternStyle: String, CaseIterable, Identifiable {
    case dots, grid, diagonal, rings, waves, plus
    var id: String { rawValue }
}

/// Tiles a single motif across the canvas.
struct PatternCanvas: View {
    let style: PatternStyle
    var color: Color = .white
    var tile: CGFloat = 46

    var body: some View {
        Canvas { context, size in
            let cols = Int(size.width / tile) + 2
            let rows = Int(size.height / tile) + 2
            for row in 0..<rows {
                for col in 0..<cols {
                    draw(&context, at: CGPoint(x: CGFloat(col) * tile, y: CGFloat(row) * tile))
                }
            }
        }
    }

    private func draw(_ context: inout GraphicsContext, at o: CGPoint) {
        let s = tile
        switch style {
        case .dots:
            context.fill(Path(ellipseIn: CGRect(x: o.x + s * 0.42, y: o.y + s * 0.42, width: s * 0.16, height: s * 0.16)),
                         with: .color(color))
        case .grid:
            var path = Path()
            path.move(to: o); path.addLine(to: CGPoint(x: o.x + s, y: o.y))
            path.move(to: o); path.addLine(to: CGPoint(x: o.x, y: o.y + s))
            context.stroke(path, with: .color(color), lineWidth: 0.8)
        case .diagonal:
            var path = Path()
            path.move(to: CGPoint(x: o.x, y: o.y + s)); path.addLine(to: CGPoint(x: o.x + s, y: o.y))
            context.stroke(path, with: .color(color), lineWidth: 1)
        case .rings:
            context.stroke(Path(ellipseIn: CGRect(x: o.x + s * 0.2, y: o.y + s * 0.2, width: s * 0.6, height: s * 0.6)),
                           with: .color(color), lineWidth: 1)
        case .waves:
            var path = Path()
            path.move(to: CGPoint(x: o.x, y: o.y + s * 0.5))
            path.addQuadCurve(to: CGPoint(x: o.x + s * 0.5, y: o.y + s * 0.5), control: CGPoint(x: o.x + s * 0.25, y: o.y + s * 0.2))
            path.addQuadCurve(to: CGPoint(x: o.x + s, y: o.y + s * 0.5), control: CGPoint(x: o.x + s * 0.75, y: o.y + s * 0.8))
            context.stroke(path, with: .color(color), lineWidth: 1)
        case .plus:
            var path = Path()
            path.move(to: CGPoint(x: o.x + s * 0.5, y: o.y + s * 0.35)); path.addLine(to: CGPoint(x: o.x + s * 0.5, y: o.y + s * 0.65))
            path.move(to: CGPoint(x: o.x + s * 0.35, y: o.y + s * 0.5)); path.addLine(to: CGPoint(x: o.x + s * 0.65, y: o.y + s * 0.5))
            context.stroke(path, with: .color(color), lineWidth: 1)
        }
    }
}

/// Gradient base + tiled motif overlay (soft-light), with blur/dim effects.
struct PatternWallpaperView: View {
    let colors: [UInt32]
    let style: PatternStyle
    let settings: WallpaperSettings
    @Environment(\.meshPhase) private var meshPhase
    @Environment(\.meshAnimated) private var meshAnimated
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            base
            PatternCanvas(style: style)
                .opacity(0.12 + settings.intensity * 0.40)
                .blendMode(.softLight)
        }
        .blur(radius: (settings.blur && !reduceTransparency) ? 28 : 0)
        .overlay(Color.black.opacity(settings.dimAlpha))
    }

    /// A 4-color palette glows on the animated mesh (Telegram-style "lit" pattern);
    /// anything else falls back to a static gradient.
    @ViewBuilder private var base: some View {
        if colors.count == 4 {
            MeshGradientView(colors: colors, phase: meshPhase, animated: meshAnimated)
        } else {
            let palette = (colors.isEmpty ? [0x1C1C1E, 0x2C2C2E] : colors).map { Color(rgb: $0) }
            let (start, end) = WallpaperView.endpoints(forDegrees: settings.rotation)
            LinearGradient(colors: palette, startPoint: start, endPoint: end)
        }
    }
}
