import SwiftUI

/// The Max plan identity: an AURORA over black (owner-tuned 260716 against
/// the Duolingo Max reference) — mint → ice cyan carrying the field, with a
/// violet whisper compressed into the gradient tail as the accent, never the
/// body. Light UI deepens the stops under WHITE labels; dark UI keeps the
/// bright aurora under BLACK labels (the bright-tint/black-label convention
/// of system green controls). Every stop clears the 3:1 control floor for
/// its appearance's label (verified per stop).
enum LooxMaxTint {
    /// Deep spruce → teal-ink → violet stops for light UI (white label).
    static let lightStops: [UInt32] = [0x047857, 0x0E7490, 0x6D28D9]
    /// Bright mint → ice cyan → violet stops for dark UI (black label).
    static let darkStops: [UInt32] = [0x6EE7B7, 0x67E8F9, 0x8B5CF6]

    /// Appearance-adaptive identity gradient. The violet stop sits at the
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
    /// noise — the teal anchor (light 0x0F766E ≈ 5.5:1 on white, dark
    /// 0x5EEAD4 ≈ 13:1 on near-black).
    static var solid: Color { VaultColors.dynamic(light: 0x0F766E, dark: 0x5EEAD4) }

    /// Label color on the identity fill: white on the deep light stops,
    /// black on the bright dark stops.
    static var onTint: Color { VaultColors.dynamic(light: 0xFFFFFF, dark: 0x000000) }
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
