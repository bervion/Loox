import SwiftUI

/// Quiet quick-action tile: an elevated surface with a soft-tinted glyph chip and a
/// primary-text label, laid out 2×2 on Home. The earlier fully-tinted pills read louder
/// than the credential list they sit under — Home's protagonist (DNA #1) — and four
/// saturated hues in a band broke the "calm intelligence" bar (DNA #8). The only
/// saturated ink now is the small glyph chip; the tile itself matches the app's card
/// surfaces. Half-width tiles fit full Vietnamese labels (a single row of four truncated
/// them); an optional live count renders as a small soft badge, not a headline.
///
/// Surface is **clear Liquid Glass on iOS 26** (interactive — these are action controls,
/// like the tab bar), with an elevated card fill on older OSes / Reduce Transparency.
struct QuickActionCard: View {
    let icon: String
    let label: LocalizedStringResource
    let tint: Color
    var count: Int? = nil
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            QuickActionCardLabel(icon: icon, label: label, tint: tint, count: count)
        }
        .buttonStyle(QuickActionButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(Text(label))
    }
}

/// The visual content of a quick-action tile, usable as a plain view — e.g. as the label
/// of a `Menu` so the Add action can present an item-type menu instead of a single tap.
struct QuickActionCardLabel: View {
    let icon: String
    let label: LocalizedStringResource
    let tint: Color
    var count: Int? = nil

    @Environment(AppEnvironment.self) private var env

    /// Outer tile corner radius — shared by every quick-action tile so the glyph chip's
    /// concentric inset (below) stays consistent regardless of which action it is.
    fileprivate static let tileRadius = Radius.md
    /// Tile inner padding — the "inset" half of the concentric-radius formula for the chip.
    fileprivate static let tilePadding = Space.s2

    var body: some View {
        HStack(spacing: Space.s2) {
            // Soft-tinted glyph chip (same language as the Watchtower category tiles):
            // tint at 14% for the well, full tint for the glyph.
            Color.clear
                .frame(width: 28, height: 28)
                .background(
                    tint.opacity(0.14),
                    in: RoundedRectangle(
                        cornerRadius: Radius.concentric(outer: Self.tileRadius,
                                                        inset: Self.tilePadding),
                        style: .continuous))
                .overlay(PolarisIcon(icon, size: 15).foregroundStyle(tint))

            Text(label)
                .vaultType(.subhead)
                .fontWeight(.semibold)
                .themedForeground(.primary)
                .lineLimit(1)
                // 0.75 floor: "Generate Password" is the longest label and needs it at
                // SE width; DNA allows scale-down as a last resort, never below 0.7.
                .minimumScaleFactor(0.75)

            Spacer(minLength: 0)

            if let count, count > 0 {
                countBadge(count)
            }
        }
        .padding(.horizontal, Self.tilePadding)
        .padding(.vertical, Self.tilePadding)
        .frame(maxWidth: .infinity, minHeight: Metric.hitMin)
        .modifier(QuickActionCardSurface(tileRadius: Self.tileRadius))
        .contentShape(.rect(cornerRadius: Self.tileRadius))
    }

    /// Small trailing badge — counts are secondary information, not the tile's headline.
    @ViewBuilder
    private func countBadge(_ count: Int) -> some View {
        Text("\(min(count, 99))")
            .vaultType(.caption)
            .fontWeight(.bold)
            .foregroundStyle(tint)
            .padding(Space.s1)
            .frame(minWidth: 18, minHeight: 18)
            .background(tint.opacity(0.14), in: Circle())
    }
}

/// Tile surface: clear interactive Liquid Glass on iOS 26, elevated card fill with a
/// hairline border otherwise. Mirrors the tab-bar surface's guard strategy
/// (`#if compiler` + `#available` + Reduce Transparency fallback) so a pre-Xcode-26
/// CI build never sees the `glassEffect` symbol.
private struct QuickActionCardSurface: ViewModifier {
    let tileRadius: CGFloat
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let theme = env.theme.active
        let shape = RoundedRectangle(cornerRadius: tileRadius, style: .continuous)
        #if compiler(>=6.2)
        if #available(iOS 26, macOS 26, *), !reduceTransparency {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content
                .background(Color(rgb: theme.elevatedBackground), in: shape)
                .overlay(shape.strokeBorder(Color(rgb: theme.separator), lineWidth: 0.5))
        }
        #else
        content
            .background(Color(rgb: theme.elevatedBackground), in: shape)
            .overlay(shape.strokeBorder(Color(rgb: theme.separator), lineWidth: 0.5))
        #endif
    }
}

/// Wraps content in a `GlassEffectContainer` on iOS 26 so every `glassEffect` inside shares
/// one backdrop layer: a dense glass cluster (4 tiles) then renders in a single offscreen
/// pass and updates together, instead of each re-sampling independently. This removes the
/// "glassEffect tried to update multiple times per frame" warning on theme changes and cuts
/// the GPU cost (each glass otherwise needs ~3 offscreen textures). No-op on older OSes.
struct VaultGlassGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26, macOS 26, *) {
            GlassEffectContainer { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// Press-scale feedback matching DS press = 0.97.
private struct QuickActionButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? Motion.pressScale : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: Motion.fast),
                       value: configuration.isPressed)
    }
}

// MARK: - Convenience factories for the canonical Home quick actions

extension QuickActionCard {
    /// Teal — decorative glyph tint, fixed per DS spec.
    static let tealTint = VaultColors.dynamic(light: 0x0E8A7D, dark: 0x1DB8A6)
    /// Purple — decorative glyph tint, fixed per DS spec.
    static let purpleTint = VaultColors.dynamic(light: 0x7C3AED, dark: 0x9D65F5)
    /// Green — decorative glyph tint, fixed per DS spec.
    static let greenTint = VaultColors.dynamic(light: 0x0A8F3C, dark: 0x1DB356)

    static func generate(action: @escaping () -> Void) -> QuickActionCard {
        QuickActionCard(
            icon: Icons.refresh,
            label: LocalizedStringResource("Generate Password").inAppLocalized,
            tint: tealTint, action: action)
    }

    static func totp(count: Int, action: @escaping () -> Void) -> QuickActionCard {
        QuickActionCard(
            icon: Icons.clock,
            label: LocalizedStringResource("2FA Codes").inAppLocalized,
            tint: purpleTint, count: count, action: action)
    }

    static func watchtower(count: Int, action: @escaping () -> Void) -> QuickActionCard {
        QuickActionCard(
            icon: Icons.watchtower,
            label: LocalizedStringResource("Watchtower").inAppLocalized,
            tint: greenTint, count: count, action: action)
    }
}
