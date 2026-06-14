import SwiftUI
import UIKit

// Packed 0xRRGGBB color helpers + pure color math shared by the theme engine
// (compiled into both the app and the AutoFill extension). Theme colors are stored
// as `UInt32` (Sendable, Codable) and converted to UIColor/Color at the UI edge.

extension UIColor {
    nonisolated convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha)
    }
}

/// Color math used by accent recolor. Pure + off-main safe.
nonisolated enum RGBMath {
    /// Relative luminance (sRGB-ish, 0…1) — used to pick on-accent foreground.
    static func luminance(_ rgb: UInt32) -> Double {
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// Per-channel linear blend of `a` toward `b` by `t` (0…1).
    static func blend(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        let clamped = max(0, min(1, t))
        func channel(_ shift: UInt32) -> UInt32 {
            let av = Double((a >> shift) & 0xFF)
            let bv = Double((b >> shift) & 0xFF)
            return UInt32((av + (bv - av) * clamped).rounded()) & 0xFF
        }
        return (channel(16) << 16) | (channel(8) << 8) | channel(0)
    }
}

extension Color {
    /// Build a SwiftUI `Color` from a packed `0xRRGGBB` theme value. Shared by the
    /// app and the AutoFill extension.
    nonisolated init(rgb: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: opacity)
    }
}
