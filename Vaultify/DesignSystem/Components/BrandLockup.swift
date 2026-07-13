import SwiftUI

/// Horizontal brand lockup: the six-circle symbol beside the LOOX wordmark.
/// `height` is the symbol's height; the wordmark is scaled to ~0.52 of it so
/// its cap height sits optically balanced next to the mark. The wordmark
/// follows light/dark via its asset variants; the symbol is full-colour.
struct BrandLockup: View {
    var height: CGFloat = 40

    var body: some View {
        HStack(spacing: height * 0.18) {
            Image("BrandSymbol")
                .resizable()
                .scaledToFit()
                .frame(height: height)
            BrandLogoMark(size: height * 0.52, shadowRadius: 0, shadowY: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Loox"))
    }
}
