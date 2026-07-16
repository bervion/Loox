import SwiftUI

/// Circular membership seal for the Loox screen header — the brand symbol in
/// the middle with the localized "Loox member" phrase curved around it, in the
/// spirit of the iCloud+ subscriber stamp. Purely decorative: fixed size (the
/// header title carries the information), hidden from accessibility, static
/// under Reduce Motion by construction (nothing animates).
struct LooxMemberSeal: View {
    @Environment(AppEnvironment.self) private var env
    /// Paid tiers tint the ring with the accent; Free keeps it quiet.
    var tier: LooxTier
    var diameter: CGFloat = 68

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(rgb: env.theme.active.elevatedBackground))
                .overlay(Circle().strokeBorder(Color(rgb: env.theme.active.separator), lineWidth: 0.75))
            SealRingText(text: ringText, radius: diameter / 2 - diameter * 0.115)
                // Fixed-size font by design (documented exemption from the
                // vaultType rule): the ring is geometry, not text — its glyph
                // size must scale with the seal's diameter, never with Dynamic
                // Type, or the ring overflows the circle. The whole seal is
                // decorative and accessibilityHidden.
                .font(.system(size: diameter * 0.105, weight: .semibold))
                .themedForeground(tier > .free ? .accentText : .secondary)
            Image("BrandSymbol")
                .resizable()
                .scaledToFit()
                .frame(width: diameter * 0.4, height: diameter * 0.4)
        }
        .frame(width: diameter, height: diameter)
        .elevation(.level1)
        .accessibilityHidden(true)
    }

    /// The phrase repeated twice so the ring reads dense at any locale's length
    /// (a single short phrase leaves the circle sparse). The "•" is a decorative
    /// ring divider, not sentence punctuation — the no-"·"-separator copy rule
    /// governs prose, and this whole view is hidden from assistive tech.
    private var ringText: String {
        let phrase = appString("Loox member").uppercased(with: appResourceLocale)
        return "\(phrase) • \(phrase) • "
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
