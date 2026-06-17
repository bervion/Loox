import SwiftUI

/// Reminders-style quick-action card: a colour tile with the icon in a glyph badge
/// (top-left), an optional live count (top-right), and the label (bottom-left). Laid out
/// two-up on Home. Each action keeps its decorative tint (accent / teal / purple / green).
///
/// Surface is **tinted Liquid Glass on iOS 26** (interactive), with a flat colour fill on
/// older OSes / Reduce Transparency. These are action controls (like the tab bar), not data
/// rows, so glass is appropriate. Foreground is always white — the tints are dark enough for
/// legible white text/icons in both light and dark mode.
struct QuickActionCard: View {
    let icon: String
    let label: LocalizedStringResource
    let fill: Color
    var count: Int? = nil
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            QuickActionCardLabel(icon: icon, label: label, fill: fill, count: count)
        }
        .buttonStyle(QuickActionButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(Text(label))
    }
}

/// The visual content of a quick-action card, usable as a plain view — e.g. as the label
/// of a `Menu` so the Add action can present an item-type menu instead of a single tap.
struct QuickActionCardLabel: View {
    let icon: String
    let label: LocalizedStringResource
    let fill: Color
    var count: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Space.s2) {
                // Icon glyph — a Liquid-Glass badge inset into the card surface.
                Color.clear
                    .frame(width: 34, height: 34)
                    .modifier(GlyphBadgeSurface())
                    .overlay(PolarisIcon(icon, size: 19).foregroundStyle(.white))

                Spacer(minLength: Space.s2)

                if let count {
                    Text("\(count)")
                        .font(.system(.title).weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }

            Spacer(minLength: Space.s4)

            Text(label)
                .vaultType(.subhead)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .modifier(QuickActionCardSurface(fill: fill))
        .contentShape(.rect(cornerRadius: Radius.lg))
    }
}

/// Card surface: tinted Liquid Glass on iOS 26 (interactive), flat colour fill otherwise.
/// Mirrors the tab-bar surface's guard strategy (`#if compiler` + `#available` + Reduce
/// Transparency fallback) so a pre-Xcode-26 CI build never sees the `glassEffect` symbol.
private struct QuickActionCardSurface: ViewModifier {
    let fill: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
        #if compiler(>=6.2)
        if #available(iOS 26, *), !reduceTransparency {
            content.glassEffect(.regular.tint(fill).interactive(), in: shape)
        } else {
            content.background(fill, in: shape)
        }
        #else
        content.background(fill, in: shape)
        #endif
    }
}

/// Glyph badge surface: clear Liquid Glass on iOS 26 (reads as a glass well inset into the
/// tinted card), else a subtle dark fill. Same guard strategy as the card surface.
private struct GlyphBadgeSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
        #if compiler(>=6.2)
        if #available(iOS 26, *), !reduceTransparency {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(Color.black.opacity(0.18), in: shape)
        }
        #else
        content.background(Color.black.opacity(0.18), in: shape)
        #endif
    }
}

/// Wraps content in a `GlassEffectContainer` on iOS 26 so every `glassEffect` inside shares
/// one backdrop layer: a dense glass cluster (the 4 cards + their badges = 8 glass views)
/// then renders in a single offscreen pass and updates together, instead of each re-sampling
/// independently. This removes the "glassEffect tried to update multiple times per frame"
/// warning on theme changes and cuts the GPU cost (each glass otherwise needs ~3 offscreen
/// textures). No-op on older OSes.
struct VaultGlassGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
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
    /// Teal — decorative, fixed per DS spec.
    static let tealFill = VaultColors.dynamic(light: 0x0E8A7D, dark: 0x1DB8A6)
    /// Purple — decorative, fixed per DS spec.
    static let purpleFill = VaultColors.dynamic(light: 0x7C3AED, dark: 0x9D65F5)
    /// Green — decorative, fixed per DS spec.
    static let greenFill = VaultColors.dynamic(light: 0x0A8F3C, dark: 0x1DB356)

    static func generate(action: @escaping () -> Void) -> QuickActionCard {
        QuickActionCard(
            icon: Icons.refresh,
            label: LocalizedStringResource("Generate Password").inAppLocalized,
            fill: tealFill, action: action)
    }

    static func totp(count: Int, action: @escaping () -> Void) -> QuickActionCard {
        QuickActionCard(
            icon: Icons.clock,
            label: LocalizedStringResource("2FA Codes").inAppLocalized,
            fill: purpleFill, count: count, action: action)
    }

    static func watchtower(count: Int, action: @escaping () -> Void) -> QuickActionCard {
        QuickActionCard(
            icon: Icons.watchtower,
            label: LocalizedStringResource("Watchtower").inAppLocalized,
            fill: greenFill, count: count, action: action)
    }
}
