import SwiftUI

/// Circular subscriber seal for the membership screen header, in the spirit of
/// the iCloud+ stamp: the brand symbol with "NGƯỜI ĐĂNG KÝ • LOOX •" (localized)
/// curved around it in the HEAVY primary label color — no chip behind it, the
/// ring sits directly on the screen. Shown to SUBSCRIBERS only (the caller
/// gates on tier); purely decorative and hidden from assistive tech.
///
/// On first appear the ring radiates outward from the logo once (scale + fade
/// + a slight unfurl), echoing the brand reveal animation; Reduce Motion skips
/// straight to the final state.
struct LooxMemberSeal: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var diameter: CGFloat = 68
    @State private var revealed = false

    var body: some View {
        ZStack {
            SealRingText(text: ringText, radius: diameter / 2 - diameter * 0.115)
                // Fixed-size font by design (documented exemption from the
                // vaultType rule): the ring is geometry, not text — its glyph
                // size must scale with the seal's diameter, never with Dynamic
                // Type, or the ring overflows the circle. The whole seal is
                // decorative and accessibilityHidden.
                .font(.system(size: diameter * 0.105, weight: .heavy))
                .themedForeground(.primary)
                .scaleEffect(revealed ? 1 : 0.5)
                .opacity(revealed ? 1 : 0)
                .rotationEffect(.degrees(revealed ? 0 : -12))
            Image("BrandSymbol")
                .resizable()
                .scaledToFit()
                .frame(width: diameter * 0.44, height: diameter * 0.44)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
        .onAppear {
            guard !revealed else { return }
            guard !reduceMotion else {
                revealed = true
                return
            }
            withAnimation(Motion.spring.delay(0.05)) { revealed = true }
        }
    }

    /// One pass around the circle (iCloud+ layout): the localized subscriber
    /// word, then the brand. The "•" is a decorative ring divider, not
    /// sentence punctuation — the no-"·"-separator copy rule governs prose,
    /// and this whole view is hidden from assistive tech.
    private var ringText: String {
        let subscriber = appString("Subscriber").uppercased(with: appResourceLocale)
        return "\(subscriber) • LOOX • "
    }
}

/// Lays glyphs of `text` evenly around a circle of `radius`, starting at
/// 12 o'clock. Even angular distribution (rather than width-metric arc layout)
/// matches the stamp look: uniform rhythm, no kerning cliffs between locales.
private struct SealRingText: View {
    let text: String
    let radius: CGFloat

    var body: some View {
        let glyphs = Array(text)
        ZStack {
            ForEach(glyphs.indices, id: \.self) { index in
                Text(verbatim: String(glyphs[index]))
                    .offset(y: -radius)
                    .rotationEffect(.degrees(Double(index) / Double(glyphs.count) * 360))
            }
        }
    }
}
