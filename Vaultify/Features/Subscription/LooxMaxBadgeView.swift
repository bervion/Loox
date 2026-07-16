import SwiftUI

/// The Max plan identity: a teal→green pair distinct from the paywall's
/// pinned blue, with per-appearance stops chosen so the LABEL color passes
/// the 3:1 control floor on both gradient ends — white labels on the deep
/// light-mode stops, black labels on the bright dark-mode stops (the same
/// bright-tint/black-label convention as system green controls).
enum LooxMaxTint {
    /// Deep stops for light UI (white label ≥ 3:1 on both).
    static let lightStops: [UInt32] = [0x0E8A7D, 0x15803D]
    /// Bright neon stops for dark UI (black label ≥ 3:1 on both).
    static let darkStops: [UInt32] = [0x2FD0BF, 0x34D399]

    /// Appearance-adaptive identity gradient (stops are dynamic colors, so
    /// the gradient re-resolves per color scheme without environment plumbing).
    static var gradient: LinearGradient {
        LinearGradient(
            colors: [VaultColors.dynamic(light: lightStops[0], dark: darkStops[0]),
                     VaultColors.dynamic(light: lightStops[1], dark: darkStops[1])],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Solid accent for rings, links and text where a gradient would be noise.
    static var solid: Color { VaultColors.dynamic(light: lightStops[0], dark: darkStops[0]) }

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
        if tier == .max {
            HStack(spacing: badgeHeight * 0.35) {
                Text(verbatim: "Loox")
                LooxMaxBadgeView(height: badgeHeight)
            }
        } else {
            Text(verbatim: tier.displayName)
        }
    }
}
