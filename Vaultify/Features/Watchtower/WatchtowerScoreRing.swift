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
    // Ticks fade + scale in as a whole layer — a reliable view-level animation.
    // The ticks themselves are always drawn at full opacity so they never vanish.
    @State private var ticksIn = false

    // Target fraction [0, 1]
    private var fraction: CGFloat { CGFloat(max(0, min(100, score))) / 100 }

    // Displayed integer derived from animated fraction so it counts up each frame
    private var displayedScore: Int { max(0, min(100, Int((animatedFraction * 100).rounded()))) }

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
                // Track + gradient fill (animatedFraction-driven)
                Canvas { ctx, _ in
                    drawTrack(ctx: ctx, cx: cx, cy: cy, r: r, bw: bw, theme: theme)
                    drawFill(ctx: ctx, cx: cx, cy: cy, r: r, bw: bw)
                }
                .frame(width: geo.size.width, height: geo.size.height)

                // Ticks on their own layer (always drawn full) so a reliable
                // view-level fade + scale powers them in — they never disappear.
                Canvas { ctx, _ in
                    drawTicks(ctx: ctx, cx: cx, cy: cy, r: r, scale: scale, theme: theme)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .opacity(ticksIn ? 1 : 0)
                .scaleEffect(ticksIn ? 1 : 0.92, anchor: .center)
                .animation(reduceMotion ? nil : .easeOut(duration: Motion.slow * 1.8), value: ticksIn)

                // Needle marker on top
                Canvas { ctx, _ in
                    drawMarker(ctx: ctx, cx: cx, cy: cy, r: r, bw: bw, scale: scale)
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
            animatedFraction = target
            numberBlur       = 0
            ticksIn          = true
            return
        }

        // Reset the sweep for replay (e.g. when the score settles after the audit)
        animatedFraction = 0
        numberBlur       = 6

        // Needle + fill swing toward the score and settle — a low-damping spring
        // gives the "đung đưa" swing of a real gauge needle stepping onto a scale.
        withAnimation(.spring(response: 0.9, dampingFraction: 0.6)) {
            animatedFraction = target
        }
        // Number blur dissolves as the needle settles
        withAnimation(.easeOut(duration: Motion.slow * 1.6)) {
            numberBlur = 0
        }
        // Ticks layer fades + scales in (eased by its .animation modifier)
        ticksIn = true
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
        let f = min(1, animatedFraction)   // spring may overshoot past 1
        guard f > 0 else { return }
        var path = Path()
        path.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                    startAngle: .degrees(Geo.startDeg),
                    endAngle:   .degrees(currentEndDeg(f)),
                    clockwise:  false)
        // Diagonal linear gradient follows the arc direction (left-top → right)
        ctx.stroke(path,
                   with: .linearGradient(Self.gaugeGradient,
                                         startPoint: CGPoint(x: cx - r, y: cy),
                                         endPoint:   CGPoint(x: cx + r, y: cy)),
                   style: StrokeStyle(lineWidth: bw, lineCap: .round))
    }

    private func drawTicks(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat,
                           r: CGFloat, scale: CGFloat, theme: AppTheme) {
        // Always full opacity — the parent layer animates them in. Dark + semi-
        // transparent so they read on the grey track AND the coloured fill.
        let tickColor = Color(rgb: theme.primaryText).opacity(0.24)
        for i in 0...Geo.tickCount {
            let deg = Geo.startDeg + Geo.sweepDeg * CGFloat(i) / CGFloat(Geo.tickCount)
            let isMajor = i % 4 == 0
            let length: CGFloat = (isMajor ? 11 : 7) * scale
            let strokeW: CGFloat = (isMajor ? 2.2 : 1.4) * scale
            let innerR = r - length / 2
            let outerR = r + length / 2
            let rad = deg * .pi / 180
            var path = Path()
            path.move(to: CGPoint(x: cx + innerR * cos(rad), y: cy + innerR * sin(rad)))
            path.addLine(to: CGPoint(x: cx + outerR * cos(rad), y: cy + outerR * sin(rad)))
            ctx.stroke(path, with: .color(tickColor),
                       style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
        }
    }

    /// Needle: a triangle in the ring's interior just below the band, pointing
    /// OUTWARD at the fill tip (1Password style). Coloured to match the fill at the
    /// tip (green→blue) so it reads as part of the dial, and travels with the score.
    private func drawMarker(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat,
                            r: CGFloat, bw: CGFloat, scale: CGFloat) {
        // Always drawn — even at score 0 it rests at the arc start, so the needle
        // is never missing. The spring may overshoot past 1 → clamp.
        let f = min(1, animatedFraction)
        let endRad = currentEndDeg(f) * .pi / 180

        // 1Password-style triangle sitting in the interior just below the band,
        // pointing OUTWARD at the fill tip; travels with the score.
        let triH: CGFloat = 15 * scale     // radial height
        let triW: CGFloat = 17 * scale     // base width
        let gap:  CGFloat = 4  * scale     // gap between the tip and the band's inner edge
        let centreR = r - bw / 2 - gap - triH / 2

        let mcx = cx + centreR * cos(endRad)
        let mcy = cy + centreR * sin(endRad)

        // Build pointing up (-y = tip); rotation maps local up → the outward radial.
        var tri = Path()
        tri.move(to: CGPoint(x: 0, y: -triH / 2))            // tip → points at the band
        tri.addLine(to: CGPoint(x: -triW / 2, y: triH / 2))  // base left
        tri.addLine(to: CGPoint(x:  triW / 2, y: triH / 2))  // base right
        tri.closeSubpath()
        tri = tri.applying(
            CGAffineTransform(translationX: mcx, y: mcy).rotated(by: endRad + .pi / 2))

        ctx.fill(tri, with: .color(fillTipColor(f)))
    }

    /// Colour of the gradient fill at fraction `f` (green→teal→blue) — tints the
    /// needle so it matches the fill tip, like the 1Password marker.
    private func fillTipColor(_ f: CGFloat) -> Color {
        let stops: [(CGFloat, CGFloat, CGFloat)] = [
            (0x16, 0xA3, 0x4A), (0x10, 0xB9, 0x81), (0x38, 0xBD, 0xF8)
        ]
        let t = max(0, min(1, f)) * 2          // 0…2 across the two gradient segments
        let i = min(1, Int(t))
        let lt = t - CGFloat(i)
        let a = stops[i], b = stops[i + 1]
        return Color(red:   (a.0 + (b.0 - a.0) * lt) / 255,
                     green: (a.1 + (b.1 - a.1) * lt) / 255,
                     blue:  (a.2 + (b.2 - a.2) * lt) / 255)
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
