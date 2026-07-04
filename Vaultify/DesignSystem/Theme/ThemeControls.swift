import SwiftUI

// Small UI helpers bridging the theme core to SwiftUI controls.

extension Color {
    /// Resolve a SwiftUI `Color` to a packed `0xRRGGBB` value (for the custom accent
    /// `ColorPicker`).
    var themeRGB: UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(UIKit)
        PlatformColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        #elseif canImport(AppKit)
        (PlatformColor(self).usingColorSpace(.deviceRGB) ?? PlatformColor(self))
            .getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        func ch(_ v: CGFloat) -> UInt32 { UInt32((max(0, min(1, v)) * 255).rounded()) }
        return (ch(r) << 16) | (ch(g) << 8) | ch(b)
    }
}

extension BuiltinTheme {
    var displayName: LocalizedStringResource {
        let base: LocalizedStringResource = switch self {
        case .day: "Day"
        case .dayClassic: "Day Classic"
        case .night: "Night"
        case .nightTinted: "Night Tinted"
        }
        return base.inAppLocalized
    }
}

extension FontScale {
    /// Map the app text-size to a SwiftUI Dynamic Type size (`.regular` = system).
    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .xSmall: return .xSmall
        case .small: return .small
        case .regular: return .large
        case .large: return .xLarge
        case .xLarge: return .xxLarge
        case .xxLarge: return .xxxLarge
        }
    }

    var label: LocalizedStringResource {
        let base: LocalizedStringResource = switch self {
        case .xSmall: "Extra Small"
        case .small: "Small"
        case .regular: "Default"
        case .large: "Large"
        case .xLarge: "Extra Large"
        case .xxLarge: "Largest"
        }
        return base.inAppLocalized
    }
}

extension View {
    /// Apply the app text-size, but defer to the system when set to Default.
    @ViewBuilder func appFontScale(_ scale: FontScale) -> some View {
        if scale == .regular { self } else { dynamicTypeSize(scale.dynamicTypeSize) }
    }
}
