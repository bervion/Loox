import UIKit

/// CPU rasterizer for the mesh gradient — ported faithfully from Telegram's
/// `generateGradient` (swirl transform + radial-basis cubic weighting + optional
/// saturation boost). Renders a small bitmap (default 80×80) that the layer scales
/// up; the Phase 04 view bakes a few of these per morph and plays them via
/// `CAKeyframeAnimation`. `nonisolated` → runs off-main.
nonisolated enum MeshGradientRenderer {
    /// Render one mesh frame. `colors` and `positions` must be the same count
    /// (typically 4). `saturation` is a multiplier (1.0 = unchanged, ~1.7 = boosted).
    static func image(size: Int = 80, colors: [UInt32], positions: [CGPoint], saturation: Double = 1.0) -> UIImage? {
        guard !colors.isEmpty, colors.count == positions.count else { return nil }

        let width = size, height = size
        let comps = colors.map { rgb -> (r: Double, g: Double, b: Double) in
            (Double((rgb >> 16) & 0xFF) / 255, Double((rgb >> 8) & 0xFF) / 255, Double(rgb & 0xFF) / 255)
        }
        let pts = positions.map { (x: Double($0.x), y: Double($0.y)) }

        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: space, bitmapInfo: info),
              let base = ctx.data else { return nil }
        let buffer = base.bindMemory(to: UInt8.self, capacity: width * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                let dx = Double(x) / Double(width - 1) - 0.5
                let dy = Double(y) / Double(height - 1) - 0.5

                // Radial swirl: pixels further from center rotate more.
                let dist = (dx * dx + dy * dy).squareRoot()
                let swirl = 0.35 * dist
                let theta = swirl * swirl * 0.8 * 8.0
                let cosT = cos(theta), sinT = sin(theta)
                let px = (dx * cosT - dy * sinT) + 0.5
                let py = (dx * sinT + dy * cosT) + 0.5

                // Radial-basis blend of the anchor colors (cubic falloff).
                var r = 0.0, g = 0.0, b = 0.0, total = 0.0
                for i in 0..<comps.count {
                    let ex = px - pts[i].x, ey = py - pts[i].y
                    let d = (ex * ex + ey * ey).squareRoot()
                    var w = max(0.0, 0.92 - d)
                    w = w * w * w
                    r += comps[i].r * w; g += comps[i].g * w; b += comps[i].b * w; total += w
                }
                if total > 0 { r /= total; g /= total; b /= total }

                if saturation != 1.0 {
                    let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
                    r = clamp(lum + (r - lum) * saturation)
                    g = clamp(lum + (g - lum) * saturation)
                    b = clamp(lum + (b - lum) * saturation)
                }

                let o = (y * width + x) * 4
                buffer[o] = UInt8(clamp(r) * 255)
                buffer[o + 1] = UInt8(clamp(g) * 255)
                buffer[o + 2] = UInt8(clamp(b) * 255)
                buffer[o + 3] = 255
            }
        }

        return ctx.makeImage().map { UIImage(cgImage: $0) }
    }

    private static func clamp(_ v: Double) -> Double { min(1.0, max(0.0, v)) }
}
