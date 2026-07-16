import SwiftUI

/// The Max plan identity (owner-tuned 260716): premium BLACK in light UI —
/// an ink field with a deep-violet whisper compressed into the gradient
/// tail — and a cosmic purple→pink AURORA in dark UI. White labels ride the
/// light ink; black labels ride the bright dark aurora. Every stop clears
/// the 3:1 control floor for its appearance's label (verified per stop).
enum LooxMaxTint {
    /// Ink → charcoal → deep-violet-whisper stops for light UI (white label).
    static let lightStops: [UInt32] = [0x0B0B0F, 0x1F1F26, 0x4C1D95]
    /// Bright violet → magenta → pink stops for dark UI (black label).
    static let darkStops: [UInt32] = [0x8B5CF6, 0xEC4899, 0xF472B6]

    /// Appearance-adaptive identity gradient. The accent stop sits at the
    /// tail (0.62 → 1.0) so it reads as a streak, not the field.
    static var gradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: VaultColors.dynamic(light: lightStops[0], dark: darkStops[0]), location: 0),
                .init(color: VaultColors.dynamic(light: lightStops[1], dark: darkStops[1]), location: 0.62),
                .init(color: VaultColors.dynamic(light: lightStops[2], dark: darkStops[2]), location: 1),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Solid accent for rings, links and text where a gradient would be
    /// noise — ink in light UI (≈ 17:1 on white), fuchsia in dark UI
    /// (0xE879F9 ≈ 6.8:1 on near-black).
    static var solid: Color { VaultColors.dynamic(light: 0x111114, dark: 0xE879F9) }

    /// Label color on the identity fill: white on the light ink field,
    /// black on the bright dark aurora.
    static var onTint: Color { VaultColors.dynamic(light: 0xFFFFFF, dark: 0x000000) }

    /// The badge ring/glow pin the PURPLE-PINK aurora in BOTH appearances:
    /// the chip is a fixed dark surface, so light mode's ink stops would
    /// vanish against it.
    static var badgeRing: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(rgb: darkStops[0]), location: 0),
                .init(color: Color(rgb: darkStops[1]), location: 0.62),
                .init(color: Color(rgb: darkStops[2]), location: 1),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static let badgeGlow = Color(rgb: 0xA78BFA)
}

/// Per-plan paywall identity: Loox+ (and the default surface) keeps the
/// pinned iCloud-style blue; Loox Max switches to the teal→green Max tint.
enum LooxPlanTint {
    static func accent(_ tier: LooxTier) -> Color {
        tier == .max ? LooxMaxTint.solid : LooxPaywallBlue.color
    }

    static func fill(_ tier: LooxTier) -> AnyShapeStyle {
        tier == .max ? AnyShapeStyle(LooxMaxTint.gradient)
                     : AnyShapeStyle(LooxPaywallBlue.color)
    }

    static func onFill(_ tier: LooxTier) -> Color {
        tier == .max ? LooxMaxTint.onTint : Color(rgb: 0xFFFFFF)
    }
}

/// The "MAX" badge (mirrors `Design System/loox-max-badge.svg`): a fixed dark
/// ink chip — its own surface in both appearances, like the About ink block —
/// ringed by the Max identity gradient, with a heavy italic wordmark and a
/// soft identity glow. Scales with `height` so it can sit beside any text rank.
struct LooxMaxBadgeView: View {
    var height: CGFloat = 18

    var body: some View {
        Text(verbatim: "MAX")
            .font(.system(size: height * 0.58, weight: .heavy))
            .italic()
            .kerning(height * 0.08)
            .foregroundStyle(Color(rgb: 0xFFFFFF))
            .padding(.horizontal, height * 0.3)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: height * 0.26, style: .continuous)
                    .fill(Color(rgb: 0x101114))
            )
            .overlay(
                RoundedRectangle(cornerRadius: height * 0.26, style: .continuous)
                    .strokeBorder(LooxMaxTint.badgeRing, lineWidth: max(1.5, height * 0.09))
            )
            .shadow(color: LooxMaxTint.badgeGlow.opacity(0.35), radius: height * 0.16)
            .accessibilityLabel(Text(verbatim: "Max"))
    }
}

/// Tier name lockup: "Loox" + the MAX badge for `.max` (owner 260716 —
/// everywhere "Loox Max" reads as the brand word plus the badge), the plain
/// display name for every other tier. Text inherits the surrounding font and
/// foreground, so callers style it exactly like the Text it replaces.
struct LooxTierLabel: View {
    let tier: LooxTier
    var badgeHeight: CGFloat = 16

    var body: some View {
        // The brand word carries the HEAVIEST weight in plan-name lockups
        // (owner 260716); size still follows the surrounding vaultType font.
        if tier == .max {
            HStack(spacing: badgeHeight * 0.35) {
                Text(verbatim: "Loox").fontWeight(.black)
                LooxMaxBadgeView(height: badgeHeight)
            }
        } else {
            Text(verbatim: tier.displayName).fontWeight(.black)
        }
    }
}
