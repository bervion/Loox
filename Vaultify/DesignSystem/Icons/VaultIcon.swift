import SwiftUI

/// Renders an app icon by name, whether it resolves to an SF Symbol or a legacy template asset.
///
/// Both branches occupy the same `size × size` box, so swapping an icon's namespace never
/// reflows the layout around it.
struct VaultIcon: View {
    let name: String
    var size: CGFloat
    var weight: Font.Weight
    var mode: SymbolRenderingMode

    /// SF glyphs carry larger optical bounds than the legacy strokes did, so a symbol drawn at
    /// the box's full point size reads noticeably heavier than the asset it replaces. This is
    /// the ratio `SettingsIconBadge` already settled on by eye (13pt SF against 16pt Polaris).
    private static let systemOpticalScale: CGFloat = 0.82

    /// `size` default (26) is a fallback only — call sites are expected to pass an explicit
    /// `Metric` tier (`iconCompact/iconInline/iconUtility/iconTab/iconTile/…`). It stays a plain
    /// number rather than a token because it back-stops ~20 Settings rows that omit `size:`, and
    /// snapping it to a token would reflow all of them at once.
    init(_ name: String,
         size: CGFloat = 26,
         weight: Font.Weight = .regular,
         mode: SymbolRenderingMode = .monochrome) {
        self.name = name
        self.size = size
        self.weight = weight
        self.mode = mode
    }

    var body: some View {
        Group {
            switch IconResolver.resolve(name) {
            case .system(let symbol):
                // Point-size sizing, not `.resizable()`: SF Symbols carry their own optical
                // metrics and stretching one to a square box distorts its stroke weights.
                Image(systemName: symbol)
                    .font(.system(size: size * Self.systemOpticalScale, weight: weight))
                    .symbolRenderingMode(mode)
            case .asset(let asset):
                Image(asset)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension Image {
    /// The resolved glyph for an icon name, for the few call sites that need a raw `Image`
    /// rather than `VaultIcon` — a `.resizable()` decorative glyph sized by its container, or a
    /// UIKit-backed tab item.
    ///
    /// Reach for this only when `VaultIcon`'s fixed box does not fit. Constructing `Image(name)`
    /// directly is the trap: an `sf:` token is not an asset name, so it renders nothing at all.
    init(vaultIcon name: String) {
        switch IconResolver.resolve(name) {
        case .system(let symbol): self.init(systemName: symbol)
        case .asset(let asset): self.init(asset)
        }
    }
}
