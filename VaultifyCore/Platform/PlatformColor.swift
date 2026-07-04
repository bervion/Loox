import SwiftUI

#if canImport(UIKit)
import UIKit
/// Cross-platform color type: `UIColor` on iOS/iPadOS, `NSColor` on macOS.
/// Lives in VaultifyCore so shared theme code compiled into both the app and the
/// AutoFill extension resolves one symbol.
public typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
public typealias PlatformColor = NSColor
#endif

public extension PlatformColor {
    /// Build a platform color from a packed `0xRRGGBB` theme value (sRGB).
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        let r = CGFloat((rgb >> 16) & 0xFF) / 255
        let g = CGFloat((rgb >> 8) & 0xFF) / 255
        let b = CGFloat(rgb & 0xFF) / 255
        #if canImport(UIKit)
        self.init(red: r, green: g, blue: b, alpha: alpha)
        #elseif canImport(AppKit)
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
        #endif
    }
}

public extension Color {
    /// Appearance-reactive color that resolves to `light`/`dark` packed RGB.
    /// On iOS a dynamic `UIColor` tracks the trait collection; on macOS an
    /// `NSColor` dynamic provider tracks the active `NSAppearance`.
    static func platformDynamic(light: UInt32, dark: UInt32) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            PlatformColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #elseif canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return PlatformColor(rgb: isDark ? dark : light)
        })
        #endif
    }

    /// System separator color, resolved cross-platform (`UIColor.separator` /
    /// `NSColor.separatorColor`). Kept out of the theme system on purpose — matches
    /// the OS hairline used for favicon tile borders etc.
    static var platformSeparator: Color {
        #if canImport(UIKit)
        return Color(uiColor: .separator)
        #elseif canImport(AppKit)
        return Color(nsColor: .separatorColor)
        #endif
    }

    /// System gray-5 fill, resolved cross-platform. iOS uses `UIColor.systemGray5`;
    /// macOS has no `systemGray5`, so it maps to the same light/dark RGB values.
    static var platformSystemGray5: Color {
        #if canImport(UIKit)
        return Color(uiColor: .systemGray5)
        #else
        return .platformDynamic(light: 0xE5E5EA, dark: 0x3A3A3C)
        #endif
    }

    /// Live theme-driven color: `resolve(isDark)` returns the packed RGB from the
    /// active theme. Re-evaluated by the OS on appearance change; the app also
    /// re-renders on theme mutation, matching existing iOS behavior. Not `@Sendable`:
    /// callers read `@MainActor` theme state, same as the existing iOS provider.
    static func platformThemed(_ resolve: @escaping (_ isDark: Bool) -> UInt32) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            PlatformColor(rgb: resolve(traits.userInterfaceStyle == .dark))
        })
        #elseif canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return PlatformColor(rgb: resolve(isDark))
        })
        #endif
    }
}
