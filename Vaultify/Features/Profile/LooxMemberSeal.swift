import SwiftUI

/// Circular subscriber seal for the membership screen header, in the spirit of
/// the iCloud+ stamp: the brand symbol with "NGƯỜI ĐĂNG KÝ • LOOX •" (localized)
/// curved around it in the HEAVY primary label color — no chip behind it, the
/// ring sits directly on the screen. Shown to SUBSCRIBERS only: the caller
/// gates on `LooxEntitlementStore.isSubscriber` and passes `paidTier`, so the
/// in-app complimentary Loox+ never earns the stamp. Purely decorative and
/// hidden from assistive tech.
///
/// On first appear the ring radiates outward from the logo once (scale + fade
/// + a slight unfurl), echoing the brand reveal animation; Reduce Motion skips
/// straight to the final state.
struct LooxMemberSeal: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bottom arc names the PLAN ("LOOX PLUS" / "LOOX MAX") — longer brand
    /// text is what gives the stamp its near-full ring coverage (owner 260716).
    var tier: LooxTier = .plus
    var diameter: CGFloat = 68
    @State private var revealed = false

    var body: some View {
        let ringRadius = diameter / 2 - diameter * 0.115
        // appLabel, not appString: the latter's `String(localized:locale:)`
        // only drives formatting, not table selection (see Localization.swift),
        // so the ring would stick to the SYSTEM language instead of the
        // in-app choice. appLabel routes through LocalizedStringResource with
        // the explicit in-app locale — the repo's correct table selector.
        let subscriber = appLabel("Subscriber").uppercased(with: appResourceLocale)
        let brand = "✦ LOOX \(tier == .max ? "MAX" : "PLUS") ✦"
        ZStack {
            // Two balanced arcs like the reference stamp: the subscriber word
            // hugs the TOP arc (~190°), the plan name hugs the BOTTOM arc
            // (~160°) — flipped so it reads left-to-right — with the "✦"
            // joints landing near 3 and 9 o'clock, ≈350° of coverage total.
            // Fixed-size fonts by design (documented exemption from the
            // vaultType rule): the ring is geometry — glyphs scale with the
            // seal's diameter, never with Dynamic Type, or they overflow the
            // circle. Decorative + accessibilityHidden; the "✦" is a ring
            // divider, not prose.
            Group {
                SealArcText(text: subscriber, radius: ringRadius,
                            step: min(15, 190 / Double(max(subscriber.count, 1))),
                            center: 0)
                    .font(.system(size: diameter * 0.105, weight: .black))
                SealArcText(text: brand, radius: ringRadius,
                            step: min(14, 160 / Double(max(brand.count, 1))),
                            center: 180, flipped: true)
                    .font(.system(size: diameter * 0.115, weight: .black))
            }
            .themedForeground(.primary)
            .scaleEffect(revealed ? 1 : 0.35)
            .opacity(revealed ? 1 : 0)
            .rotationEffect(.degrees(revealed ? 0 : -20))
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
            // Owner-tuned 260716: a short beat then a slightly slowed spring —
            // starts while the push settles and finishes just after, which
            // reads smoother than waiting the transition out entirely.
            withAnimation(Motion.spring.speed(0.8).delay(0.1)) { revealed = true }
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
