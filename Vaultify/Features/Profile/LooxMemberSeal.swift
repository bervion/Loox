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
        let ringRadius = diameter / 2 - diameter * 0.115
        let subscriber = appString("Subscriber").uppercased(with: appResourceLocale)
        ZStack {
            // Two balanced arcs like the reference stamp: the subscriber word
            // hugs the TOP arc, the brand hugs the BOTTOM arc — flipped so it
            // reads left-to-right instead of upside down. Fixed-size fonts by
            // design (documented exemption from the vaultType rule): the ring
            // is geometry — glyphs scale with the seal's diameter, never with
            // Dynamic Type, or they overflow the circle. Decorative +
            // accessibilityHidden. The "•" is a ring divider, not prose.
            Group {
                SealArcText(text: subscriber, radius: ringRadius,
                            step: min(13.5, 165 / Double(max(subscriber.count, 1))),
                            center: 0)
                    .font(.system(size: diameter * 0.105, weight: .black))
                // The brand arc runs slightly larger for coverage (owner 260716).
                SealArcText(text: "• LOOX •", radius: ringRadius,
                            step: 15.5, center: 180, flipped: true)
                    .font(.system(size: diameter * 0.125, weight: .black))
            }
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
}

/// Lays glyphs of `text` along an arc of `radius`, evenly stepped and centered
/// on `center` (degrees; 0 = 12 o'clock, 180 = 6 o'clock). `flipped` renders
/// stamp-style bottom text: each glyph rotates 180° about its own center and
/// the sequence runs right-to-left in angle, so it reads left-to-right.
private struct SealArcText: View {
    let text: String
    let radius: CGFloat
    /// Degrees between consecutive glyph centers.
    let step: Double
    let center: Double
    var flipped = false

    var body: some View {
        let glyphs = Array(text)
        let count = glyphs.count
        ZStack {
            ForEach(glyphs.indices, id: \.self) { index in
                let progress = Double(index) - Double(count - 1) / 2
                let angle = center + (flipped ? -progress : progress) * step
                Text(verbatim: String(glyphs[index]))
                    .rotationEffect(.degrees(flipped ? 180 : 0))
                    .offset(y: -radius)
                    .rotationEffect(.degrees(angle))
            }
        }
    }
}
