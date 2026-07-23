import SwiftUI

/// Readable-content width tiers for regular-width layouts (iPad fullscreen,
/// Split View, and later macOS — pure SwiftUI, no platform dependencies).
/// Compact widths are unaffected: the clamp only ever narrows containers wider
/// than the tier, so iPhone layouts render byte-identically.
///
/// Tiers follow the audit'd Apple idioms: `form` for onboarding/unlock columns
/// (fields + CTA), `reading` for prose-heavy detail, `wide` for tile grids.
enum VaultContentWidth {
    case form
    case reading
    case wide

    var maxWidth: CGFloat {
        switch self {
        case .form: 560
        case .reading: 640
        case .wide: 960
        }
    }
}

extension View {
    /// Clamp this view to a readable column and center it in the available
    /// width — the shared mechanism every regular-width surface uses instead
    /// of stretching iPhone layouts across 1,000+ points.
    func vaultContentWidth(_ tier: VaultContentWidth = .form) -> some View {
        frame(maxWidth: tier.maxWidth)
            .frame(maxWidth: .infinity)
    }
}
