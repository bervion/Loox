import SwiftUI

/// The app brand mark (eagle) shown on the splash, lock, and privacy screens.
///
/// Backed by the `BrandLogo` asset — the official Icon Composer render of the app
/// icon, with the iOS app-icon squircle already baked in (so no manual clipping).
/// Ships light + dark variants (luminosity appearances) so it follows the app
/// theme via the root `preferredColorScheme`.
struct BrandLogoMark: View {
    let size: CGFloat
    var shadowRadius: CGFloat = 10
    var shadowY: CGFloat = 5

    var body: some View {
        Image("BrandLogo")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.16), radius: shadowRadius, y: shadowY)
    }
}
