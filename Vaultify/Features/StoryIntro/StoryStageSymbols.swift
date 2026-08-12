import SwiftUI

/// Every bitmap the stage stamps. Each is resolved ONCE per Canvas pass and
/// drawn many times, so the cost of a rich symbol is paid a single time per
/// frame no matter how many particles wear it.

/// One drifting password scrap: a small dark card with a template Polaris glyph.
/// Fixed decorative colors on the committed-dark canvas (StoryPalette), never
/// theme roles — by design the scraps belong to the "before" world. `mix`
/// crossfades every layer toward the user's theme as the canvas resolves; the
/// theme layers must stay at ZERO strength while the canvas is dark (a light
/// theme's opaque control color painted under the dark-world fill turned the
/// whole swarm into glaring bright chips on black).
struct StoryScrapCard: View {
    let icon: String
    var wide = false
    /// Warning-tinted variant for the consequence beat's ghost copies.
    var tint: Color?
    /// 0 = fixed dark-canvas look, 1 = the user's theme (crossfaded, never a
    /// hard switch, so nothing flashes mid-gather).
    var mix: Double = 0
    let theme: AppTheme

    var body: some View {
        glyph
            .frame(width: wide ? 52 : 44, height: 34)
            .background {
                ZStack {
                    Color(rgb: theme.controlBackground).opacity(mix)
                    StoryPalette.scrapFill.opacity(1 - mix)
                }
            }
            .vaultCornerRadius(Radius.sm)
            .overlay { stroke }
    }

    /// Two passes with complementary opacity: a single interpolated Color is not
    /// available here, and switching on a threshold would pop.
    private var glyph: some View {
        ZStack {
            VaultIcon(icon, size: Metric.iconCompact)
                .foregroundStyle(tint ?? theme.color(.iconSecondary))
                .opacity(tint == nil ? mix : 1)
            if tint == nil {
                VaultIcon(icon, size: Metric.iconCompact)
                    .foregroundStyle(StoryPalette.scrapGlyph)
                    .opacity(1 - mix)
            }
        }
    }

    /// Crossfaded like the fill and the glyph — a threshold switch here would
    /// pop the border mid-gather while everything around it interpolates.
    @ViewBuilder private var stroke: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
        if let tint {
            shape.strokeBorder(tint.opacity(0.4), lineWidth: 1)
        } else {
            ZStack {
                shape.strokeBorder(Color(rgb: theme.separator), lineWidth: 1)
                    .opacity(mix)
                shape.strokeBorder(StoryPalette.scrapStroke, lineWidth: 1)
                    .opacity(1 - mix)
            }
        }
    }
}

/// A gathered password, in the brand's own language: one of the Loox symbol's
/// six gradient lobes, with the specular the logo carries. This is what the
/// welcome loop's cluster is made of — the story reuses the vocabulary rather
/// than inventing a second one, which is why the swarm morphing into these
/// reads as arriving HOME.
///
/// Drawn at a 44pt base and always scaled DOWN by the stage (the largest ring
/// bubble is ~38pt), so a resolved symbol never has to be enlarged.
struct StoryBubbleOrb: View {
    /// 0…5 — index into the brand mark's six lobe gradients.
    let lobe: Int

    var body: some View {
        let side = StoryOrbitLattice.bubbleBase
        let gradient = LooxCanvas.logoGradients[lobe % LooxCanvas.logoGradients.count]
        ZStack {
            Circle().fill(gradient.linear)
            // Top-left specular plus a hairline rim: the read the logo's
            // overlapping lobes have, and what stops a flat disc from looking
            // like a sticker at small sizes.
            Circle()
                .fill(RadialGradient(
                    colors: [Color.white.opacity(0.55), Color.white.opacity(0)],
                    center: UnitPoint(x: 0.32, y: 0.26),
                    startRadius: 0, endRadius: side * 0.42))
            Circle()
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8)
        }
        .frame(width: side, height: side)
    }
}
