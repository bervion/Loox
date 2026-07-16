import SwiftUI

/// The Max plan identity: a cosmic violet→magenta nebula (owner 260716 —
/// black plus purple-pink, premium), distinct from the paywall's pinned blue.
/// Both appearances keep DEEP stops so a WHITE label clears the 3:1 control
/// floor on both gradient ends (verified: every stop ≥ 3.9:1 vs white).
enum LooxMaxTint {
    /// Deep nebula stops for light UI.
    static let lightStops: [UInt32] = [0x6D28D9, 0xDB2777]
    /// Slightly brighter nebula stops for dark UI (still white-label safe).
    static let darkStops: [UInt32] = [0x8B5CF6, 0xEC4899]

    /// Appearance-adaptive identity gradient (stops are dynamic colors, so
    /// the gradient re-resolves per color scheme without environment plumbing).
    static var gradient: LinearGradient {
        LinearGradient(
            colors: [VaultColors.dynamic(light: lightStops[0], dark: darkStops[0]),
                     VaultColors.dynamic(light: lightStops[1], dark: darkStops[1])],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Solid accent for rings, links and text where a gradient would be
    /// noise — the violet end, lifted in dark mode for contrast on dark
    /// surfaces (0xA78BFA ≈ 6.8:1 on near-black).
    static var solid: Color { VaultColors.dynamic(light: 0x6D28D9, dark: 0xA78BFA) }

    /// Label color on the identity fill — white on both appearances (the
    /// nebula stays deep in dark mode, unlike the old neon variant).
    static var onTint: Color { Color(rgb: 0xFFFFFF) }
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
                    .strokeBorder(LooxMaxTint.gradient, lineWidth: max(1.5, height * 0.09))
            )
            .shadow(color: LooxMaxTint.solid.opacity(0.35), radius: height * 0.16)
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
