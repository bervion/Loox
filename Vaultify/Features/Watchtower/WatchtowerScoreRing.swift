import SwiftUI

// MARK: - Band

/// Security band derived from a health score, matching the DS threshold spec.
nonisolated struct ScoreBand {
    let label: LocalizedStringResource
    let role: ThemeRole
}

nonisolated func scoreBand(for score: Int) -> ScoreBand {
    if score >= 80 {
        return ScoreBand(label: "Fairly secure", role: .success)
    } else if score >= 50 {
        return ScoreBand(label: "Needs attention", role: .warning)
    } else {
        return ScoreBand(label: "At risk", role: .destructive)
    }
}

// MARK: - WatchtowerScoreRing

/// 270° speedometer gauge that visualises vault health score (0–100).
///
/// Design: 1Password-style rounded arc with a needle marker that reads cleanly
/// over the gradient band. The marker sits centred on the band at the fill tip,
/// filled with the band's semantic colour and outlined in the surface background
/// so it pops off the gradient fill.
///
/// Intro animation: fill + needle sweep from 0 → target with an ease-out curve,
/// the displayed number counts up driven by `animatedFraction`, and a motion blur
/// fades away as the sweep completes. Ticks fade in during the sweep.
/// Everything collapses to instant under Reduce Motion.
struct WatchtowerScoreRing: View {

    let score: Int

    // MARK: Geometry constants (proportional — scaled by GeometryReader)
    private enum Geo {
        // Larger gauge: rounder, thicker band for the speedometer feel
        static let baseWidth: CGFloat  = 260
        static let baseHeight: CGFloat = 218
        static let cx: CGFloat = baseWidth / 2        // 130
        static let cy: CGFloat = 116
        static let radius: CGFloat = 104
        static let bandWidth: CGFloat  = 24           // was 18; thicker = more presence
        static let startDeg: CGFloat   = 135
        static let sweepDeg: CGFloat   = 270
        static let tickCount           = 44
    }

    // DS gauge gradient: green → teal → sky (sanctioned hex values)
    private static let gaugeGradient = Gradient(colors: [
        Color(red: 0x16/255, green: 0xA3/255, blue: 0x4A/255), // #16A34A
        Color(red: 0x10/255, green: 0xB9/255, blue: 0x81/255), // #10B981
        Color(red: 0x38/255, green: 0xBD/255, blue: 0xF8/255), // #38BDF8
    ])

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Drives fill + needle + number-count-up each animation frame
    @State private var animatedFraction: CGFloat = 0
    // Blur on the centre number: starts high, animates down to 0
    @State private var numberBlur: CGFloat = 0
    // Tick opacity: fades in during the sweep
    @State private var tickOpacity: CGFloat = 0

    // Target fraction [0, 1]
    private var fraction: CGFloat { CGFloat(max(0, min(100, score))) / 100 }

    // Displayed integer derived from animated fraction so it counts up each frame
    private var displayedScore: Int { Int((animatedFraction * 100).rounded()) }

    // Angle where the fill tip currently sits
    private func currentEndDeg(_ f: CGFloat) -> CGFloat {
        Geo.startDeg + Geo.sweepDeg * f
    }

    var body: some View {
        let band  = scoreBand(for: score)
        let theme = env.theme.active

        GeometryReader { geo in
            let scale  = geo.size.width / Geo.baseWidth
            let cx     = Geo.cx        * scale
            let cy     = Geo.cy        * scale
            let r      = Geo.radius    * scale
            let bw     = Geo.bandWidth * scale

            ZStack {
                Canvas { ctx, _ in
                    drawTrack(ctx: ctx, cx: cx, cy: cy, r: r, bw: bw, theme: theme)
                    drawTicks(ctx: ctx, cx: cx, cy: cy, r: r, scale: scale,
                              theme: theme, opacity: tickOpacity)
                    drawFill(ctx: ctx, cx: cx, cy: cy, r: r, bw: bw)
                    drawMarker(ctx: ctx, cx: cx, cy: cy, r: r, bw: bw,
                               band: band, theme: theme, scale: scale)
                }
                .frame(width: geo.size.width, height: geo.size.height)

                // Centre readout outside Canvas so Dynamic Type + blur work
                scoreReadout(band: band, theme: theme, cy: cy, scale: scale)
            }
        }
        .frame(width: Geo.baseWidth, height: Geo.baseHeight)
        .onAppear { animate(to: fraction) }
        .onChange(of: score) { _, _ in animate(to: fraction) }
        .accessibilityLabel(Text("Security score: \(score)"))
    }

    // MARK: - Animation trigger

    private func animate(to target: CGFloat) {
        if reduceMotion {
            // Instant: no sweep, no blur, ticks visible immediately
            animatedFraction = target
            numberBlur       = 0
            tickOpacity      = 1
            return
        }

        // Reset for replay (e.g. score updates)
        animatedFraction = 0
        numberBlur       = 10
        tickOpacity      = 0

        // Needle + fill sweep: ease-out settle, like stepping on a scale
        withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: Motion.slow * 2)) {
            animatedFraction = target
        }
        // Number blur dissolves over the same window
        withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: Motion.slow * 2)) {
            numberBlur = 0
        }
        // Ticks fade in slightly after the sweep begins (staggered for "settle" feel)
        withAnimation(.timingCurve(0.32, 0.72, 0, 1,
                                   duration: Motion.slow * 1.6).delay(0.1)) {
            tickOpacity = 1
        }
    }

    // MARK: - Drawing helpers

    private func drawTrack(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat,
                           r: CGFloat, bw: CGFloat, theme: AppTheme) {
        var path = Path()
        path.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                    startAngle: .degrees(Geo.startDeg),
                    endAngle:   .degrees(Geo.startDeg + Geo.sweepDeg),
                    clockwise: false)
        ctx.stroke(path,
                   with: .color(Color(rgb: theme.primaryText).opacity(0.07)),
                   style: StrokeStyle(lineWidth: bw, lineCap: .round))
    }

    private func drawFill(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat,
                          r: CGFloat, bw: CGFloat) {
        guard animatedFraction > 0 else { return }
        var path = Path()
        path.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                    startAngle: .degrees(Geo.startDeg),
                    endAngle:   .degrees(currentEndDeg(animatedFraction)),
                    clockwise:  false)
        // Diagonal linear gradient follows the arc direction (left-top → right)
        ctx.stroke(path,
                   with: .linearGradient(Self.gaugeGradient,
                                         startPoint: CGPoint(x: cx - r, y: cy),
                                         endPoint:   CGPoint(x: cx + r, y: cy)),
                   style: StrokeStyle(lineWidth: bw, lineCap: .round))
    }

    private func drawTicks(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat,
                           r: CGFloat, scale: CGFloat, theme: AppTheme,
                           opacity: CGFloat) {
        let tickColor = Color(rgb: theme.primaryText).opacity(0.15 * opacity)
        for i in 0...Geo.tickCount {
            let deg    = Geo.startDeg + Geo.sweepDeg * CGFloat(i) / CGFloat(Geo.tickCount)
            let isMajor = i % 4 == 0
            let length: CGFloat = (isMajor ? 11 : 7) * scale
            let strokeW: CGFloat = (isMajor ? 2.2 : 1.4) * scale
            // Ticks straddle the arc radius
            let innerR = r - length / 2
            let outerR = r + length / 2
            let rad = deg * .pi / 180
            var path = Path()
            path.move(to: CGPoint(x: cx + innerR * cos(rad),
                                  y: cy + innerR * sin(rad)))
            path.addLine(to: CGPoint(x: cx + outerR * cos(rad),
                                     y: cy + outerR * sin(rad)))
            ctx.stroke(path, with: .color(tickColor),
                       style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
        }
    }

    /// Needle marker: a small rounded pointer centred on the band at the fill tip.
    ///
    /// Why this design: the previous filled triangle sat on the gradient and was
    /// hard to distinguish. This version uses a band-semantic colour fill with a
    /// ~2pt surface-background outline so it pops regardless of the gradient under it.
    private func drawMarker(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat,
                            r: CGFloat, bw: CGFloat,
                            band: ScoreBand, theme: AppTheme, scale: CGFloat) {
        guard animatedFraction > 0 else { return }
        let endDeg = currentEndDeg(animatedFraction)
        let endRad = endDeg * .pi / 180

        // Marker is a rounded lozenge sitting on the arc, pointing outward
        let markerLength = bw * 1.1        // slightly taller than band
        let markerWidth  = bw * 0.55       // narrower — clean needle shape
        let outlineWidth = 2.2 * scale

        // Centre of the marker == point on the arc at the tip angle
        let markerCx = cx + r * cos(endRad)
        let markerCy = cy + r * sin(endRad)

        // Build the marker shape in local space, then rotate to the arc tangent.
        // The "outward" direction from the arc centre is exactly `endRad`, so
        // rotating the local Y-axis to that direction aligns the needle with the arc.
        var localRect = Path(roundedRect: CGRect(
            x: -markerWidth / 2,
            y: -markerLength / 2,
            width: markerWidth,
            height: markerLength
        ), cornerRadius: markerWidth / 2, style: .continuous)

        // Transform: rotate so local Y aligns with the outward radial, then translate
        let transform = CGAffineTransform(translationX: markerCx, y: markerCy)
            .rotated(by: endRad + .pi / 2)
        localRect = localRect.applying(transform)

        // Outline first (renders behind the fill, visually as a halo)
        let outlinePath = localRect.strokedPath(
            StrokeStyle(lineWidth: outlineWidth, lineCap: .round, lineJoin: .round))
        ctx.fill(outlinePath, with: .color(Color(rgb: theme.groupedBackground).opacity(0.9)))

        // Band-coloured fill on top
        ctx.fill(localRect, with: .color(bandColor(band: band, theme: theme)))
    }

    /// Resolves the band's semantic colour using the theme's own role→Color mapping.
    private func bandColor(band: ScoreBand, theme: AppTheme) -> Color {
        theme.color(band.role)
    }

    // MARK: - Centre readout

    @ViewBuilder
    private func scoreReadout(band: ScoreBand, theme: AppTheme,
                              cy: CGFloat, scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(height: cy - 28 * scale)
            // Number counts up each frame from animatedFraction
            Text("\(displayedScore)")
                .font(.vaultMono(.largeTitle, weight: .bold))
                .themedForeground(.primary)
                .blur(radius: numberBlur)
                .contentTransition(.numericText())
            Text(band.label)
                .vaultType(.sectionLabel)
                .themedForeground(band.role)
                .kerning(1.4)
                .padding(.top, 2)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
