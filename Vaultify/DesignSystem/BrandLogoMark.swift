import SwiftUI

/// The Loox wordmark shown on the privacy shield, lock, and onboarding screens.
///
/// Backed by the `BrandLogo` asset — a WIDE wordmark (≈4.3:1), not a square tile,
/// so it must always render aspect-fit: `size` is the mark's HEIGHT and the width
/// follows the artwork's own ratio. Ships light + dark variants (luminosity
/// appearances) so it follows the app theme via the root `preferredColorScheme`.
struct BrandLogoMark: View {
    /// Height of the wordmark in points (width scales with the asset's ratio).
    let size: CGFloat
    var shadowRadius: CGFloat = 8
    var shadowY: CGFloat = 3

    var body: some View {
        Image("BrandLogo")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(height: size)
            .shadow(color: .black.opacity(0.12), radius: shadowRadius, y: shadowY)
    }
}
