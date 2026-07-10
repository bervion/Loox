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

/// 270° speedometer gauge for the vault health score (0–100), 1Password-style.
///
/// The intro is driven by `TimelineView(.animation)` (a real per-frame clock) rather
/// than `withAnimation`, because `Canvas` does NOT interpolate a `withAnimation`-driven
/// `@State` — it reads the final value immediately, so the gauge would jump. The clock
/// lets every frame redraw: the needle sweeps the full dial (the safety gradient cycles
/// red→amber→green), then settles back to the score; the number counts along with it.
/// After the intro it freezes to a static render (no battery drain). Reduce Motion shows
/// the settled state immediately.
struct WatchtowerScoreRing: View {

    let score: Int

    // MARK: Geometry (proportional — scaled by GeometryReader)
    private enum Geo {
        static let baseWidth: CGFloat  = 260
        static let baseHeight: CGFloat = 218
        static let cx: CGFloat = baseWidth / 2     // 130
        static let cy: CGFloat = 116
        static let radius: CGFloat = 104
        static let bandWidth: CGFloat = 24
        static let startDeg: CGFloat = 135
        static let sweepDeg: CGFloat = 270
        static let tickCount = 44
    }

    private static let introDuration: Double = 1.8

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // While true the TimelineView clock runs the intro; flips false when it finishes.
    @State private var animating = false
    @State private var startDate = Date()

    private var targetFraction: CGFloat { CGFloat(max(0, min(100, score))) / 100 }

    var body: some View {
        let theme = env.theme.active
        let band  = scoreBand(for: score)

        GeometryReader { geo in
            let scale = geo.size.width / Geo.baseWidth
            let cx = Geo.cx * scale
            let cy = Geo.cy * scale
            let r  = Geo.radius * scale
            let bw = Geo.bandWidth * scale

            if animating && !reduceMotion {
                TimelineView(.animation) { timeline in
                    let p = clamp01(CGFloat(timeline.date.timeIntervalSince(startDate)) / CGFloat(Self.introDuration))
                    gauge(progress: p, cx: cx, cy: cy, r: r, bw: bw, scale: scale,
                          theme: theme, band: band, size: geo.size)
                }
            } else {
                // Settled / Reduce-Motion: render the final frame statically.
                gauge(progress: 1, cx: cx, cy: cy, r: r, bw: bw, scale: scale,
                      theme: theme, band: band, size: geo.size)
            }
        }
        .frame(width: Geo.baseWidth, height: Geo.baseHeight)
        .onAppear { trigger() }
        .onChange(of: score) { _, _ in trigger() }
        .accessibilityLabel(Text("Security score: \(score), ") + Text(band.label))
    }

    // MARK: - Intro trigger

    private func trigger() {
        guard !reduceMotion else { animating = false; return }
        let now = Date()
        startDate = now
        animating = true
        // Freeze to the static render once the intro completes (stops the clock).
        // Guard against an earlier intro's timer stopping a newer one (the score can
        // settle 0→N right after appear, firing trigger() twice).
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.introDuration + 0.05))
            if startDate == now { animating = false }
        }
    }

    // MARK: - Progress → needle fraction (the "spinning scale" choreography)

    /// Maps intro progress `p` (0→1) to the needle fraction: sweep up to the FULL dial,
    /// then settle back to the score — so the whole safety gradient flashes by before it
    /// lands on the level.
    private func needleFraction(_ p: CGFloat) -> CGFloat {
        guard p < 1 else { return targetFraction }
        if p < 0.5 {
            return easeOut(p / 0.5)                       // 0 → 1 (sweep to full)
        } else {
            let b = easeInOut((p - 0.5) / 0.5)            // 0 → 1
            return 1 + (targetFraction - 1) * b           // 1 → score
        }
    }

    // MARK: - Composed gauge (Canvas dial + needle + centre readout)

    @ViewBuilder
    private func gauge(progress p: CGFloat, cx: CGFloat, cy: CGFloat, r: CGFloat,
                       bw: CGFloat, scale: CGFloat, theme: AppTheme, band: ScoreBand,
                       size: CGSize) -> some View {
        let f = needleFraction(p)
        let tipColor = safetyColor(f, theme: theme)
        ZStack {
            Canvas { ctx, _ in
                drawTrack(ctx: ctx, cx: cx, cy: cy, r: r, bw: bw, theme: theme)
                drawFill(ctx: ctx, cx: cx, cy: cy, r: r, bw: bw, fraction: f, tip: tipColor)
                drawTicks(ctx: ctx, cx: cx, cy: cy, r: r, scale: scale, theme: theme)
                drawMarker(ctx: ctx, cx: cx, cy: cy, r: r, bw: bw, scale: scale,
                           fraction: f, color: tipColor)
            }
            .frame(width: size.width, height: size.height)

            // Band label uses the DISCRETE semantic role (not the continuous sweep
            // tint) so it always matches the exact 80/50 thresholds, never an
            // interpolated in-between hue.
            scoreReadout(displayed: Int((f * 100).rounded()), band: band,
                         color: theme.color(band.role), cy: cy, scale: scale)
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
        ctx.stroke(path, with: .color(Color(rgb: theme.primaryText).opacity(0.08)),
                   style: StrokeStyle(lineWidth: bw, lineCap: .round))
    }

    private func drawFill(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat,
                          r: CGFloat, bw: CGFloat, fraction: CGFloat, tip: Color) {
        let f = max(0, min(1, fraction))
        guard f > 0.001 else { return }
        var path = Path()
        path.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                    startAngle: .degrees(Geo.startDeg),
                    endAngle:   .degrees(Geo.startDeg + Geo.sweepDeg * f),
                    clockwise: false)
        // Subtle gradient from a slightly darker shade to the tip colour for depth.
        let grad = Gradient(colors: [tip.opacity(0.78), tip])
        ctx.stroke(path,
                   with: .linearGradient(grad,
                                         startPoint: CGPoint(x: cx - r, y: cy),
                                         endPoint:   CGPoint(x: cx + r, y: cy)),
                   style: StrokeStyle(lineWidth: bw, lineCap: .round))
    }

    private func drawTicks(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat,
                           r: CGFloat, scale: CGFloat, theme: AppTheme) {
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

    /// Triangle needle in the ring interior, pointing OUTWARD at the fill tip.
    private func drawMarker(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat,
                            r: CGFloat, bw: CGFloat, scale: CGFloat,
                            fraction: CGFloat, color: Color) {
        let f = max(0, min(1, fraction))
        let endRad = (Geo.startDeg + Geo.sweepDeg * f) * .pi / 180
        let triH: CGFloat = 15 * scale
        let triW: CGFloat = 17 * scale
        let gap:  CGFloat = 4  * scale
        let centreR = r - bw / 2 - gap - triH / 2
        let mcx = cx + centreR * cos(endRad)
        let mcy = cy + centreR * sin(endRad)
        var tri = Path()
        tri.move(to: CGPoint(x: 0, y: -triH / 2))            // tip → points at the band
        tri.addLine(to: CGPoint(x: -triW / 2, y: triH / 2))
        tri.addLine(to: CGPoint(x:  triW / 2, y: triH / 2))
        tri.closeSubpath()
        tri = tri.applying(
            CGAffineTransform(translationX: mcx, y: mcy).rotated(by: endRad + .pi / 2))
        ctx.fill(tri, with: .color(color))
    }

    @ViewBuilder
    private func scoreReadout(displayed: Int, band: ScoreBand, color: Color,
                              cy: CGFloat, scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(height: cy - 28 * scale)
            Text("\(displayed)")
                .font(.vaultCode(.largeTitle, weight: .bold))
                .themedForeground(.primary)
                .monospacedDigit()
            Text(band.label)
                .vaultType(.sectionLabel)
                .foregroundStyle(color)
                .kerning(1.4)
                .padding(.top, 2)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Colour + easing

    /// Safety colour for a fraction: destructive (0) → warning (0.5) → success (1),
    /// blended between the ACTIVE THEME's semantic roles (not fixed hex) so the
    /// sweep stays WCAG-legible and on-brand across every accent preset and both
    /// light/dark appearances.
    private func safetyColor(_ f: CGFloat, theme: AppTheme) -> Color {
        let t = Double(max(0, min(1, f)))
        if t < 0.5 {
            return Color(rgb: RGBMath.blend(theme.destructive, theme.warning, t / 0.5))
        } else {
            return Color(rgb: RGBMath.blend(theme.warning, theme.success, (t - 0.5) / 0.5))
        }
    }

    private func clamp01(_ x: CGFloat) -> CGFloat { max(0, min(1, x)) }
    private func easeOut(_ t: CGFloat) -> CGFloat { 1 - pow(1 - t, 3) }
    private func easeInOut(_ t: CGFloat) -> CGFloat {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
}
