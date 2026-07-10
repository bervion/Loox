import SwiftUI

/// Corner-radius scale from the Design System (`tokens/spacing.css`):
/// xs 6 · sm 10 (buttons, fields, tiles) · md 14 (grouped lists) · lg 20 (cards) ·
/// xl 28 (sheets) · pill (capsules, tab bar). Always pair with the continuous
/// (squircle) curve via `vaultCornerRadius`.
nonisolated enum Radius {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 14
    static let lg: CGFloat = 20
    static let xl: CGFloat = 28
    static let pill: CGFloat = 999

    /// Concentric child radius for a rounded shape inset within a rounded parent:
    /// `R_inner ≈ R_outer − inset`, floored at `xs` so tight insets never go sharp.
    /// Keeps nested corners visually parallel instead of pinched or flared.
    static func concentric(outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(outer - inset, xs)
    }
}

extension View {
    /// Clip to a Design-System corner radius with the continuous (squircle) curve.
    func vaultCornerRadius(_ radius: CGFloat) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
