import SwiftUI

/// iOS-Settings-style leading icon for settings rows: a solid-tint rounded square
/// with a white Polaris glyph — instantly scannable row families, like the system
/// Settings app. The white-on-tint pair is a documented DNA exemption (fixed
/// decorative settings tiles, same class as the system's own icon grid); tints are
/// appearance-dynamic so dark mode keeps the hues from glowing.
struct SettingsIconBadge: View {
    /// Polaris asset name (default) …
    var icon: String? = nil
    /// … or an SF Symbol, ONLY for domain glyphs the Polaris set has no honest
    /// shape for (iCloud, and future Apple-platform notions) — user-granted
    /// exemption 260711, mirroring the payment-card SF grant.
    var systemName: String? = nil
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
            .fill(tint)
            .frame(width: 29, height: 29)
            .overlay(glyph.foregroundStyle(.white))
            .accessibilityHidden(true)   // the row's text labels the control
    }

    @ViewBuilder private var glyph: some View {
        if let systemName {
            // 13pt: SF glyphs carry larger optical bounds than the 16pt Polaris
            // strokes — at 14 the SF badge visibly outweighed its neighbours.
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
        } else {
            PolarisIcon(icon ?? Icons.info, size: 16)
        }
    }
}

/// Fixed decorative tint families for `SettingsIconBadge` (system-Settings hues,
/// light/dark pairs). Semantic roles deliberately NOT used: these are stable badge
/// identities, not state colours — an accent/theme change must not repaint the
/// entire settings grid.
enum SettingsBadgeTint {
    static let blue   = VaultColors.dynamic(light: 0x007AFF, dark: 0x0A84FF)
    static let green  = VaultColors.dynamic(light: 0x34C759, dark: 0x30D158)
    static let indigo = VaultColors.dynamic(light: 0x5856D6, dark: 0x5E5CE6)
    static let orange = VaultColors.dynamic(light: 0xFF9500, dark: 0xFF9F0A)
    static let red    = VaultColors.dynamic(light: 0xFF3B30, dark: 0xFF453A)
    static let teal   = VaultColors.dynamic(light: 0x30B0C7, dark: 0x40C8E0)
    static let purple = VaultColors.dynamic(light: 0xAF52DE, dark: 0xBF5AF2)
    static let pink   = VaultColors.dynamic(light: 0xFF2D55, dark: 0xFF375F)
    static let gray   = VaultColors.dynamic(light: 0x8E8E93, dark: 0x98989D)
}
