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
    /// WCAG 2.x relative luminance (0…1): channels linearized from sRGB before the
    /// Rec.709 weighting. This is the value contrast ratios must be computed from.
    static func relativeLuminance(_ rgb: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let c = Double((rgb >> shift) & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    /// WCAG contrast ratio between two colors (1…21).
    static func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double {
        let la = relativeLuminance(a), lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Best-contrast on-color (white or black) for text/icons drawn on `background`,
    /// chosen by real WCAG contrast rather than a raw luminance threshold.
    static func onColor(_ background: UInt32) -> UInt32 {
        let white: UInt32 = 0xFFFFFF, black: UInt32 = 0x000000
        return contrastRatio(white, background) >= contrastRatio(black, background) ? white : black
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
