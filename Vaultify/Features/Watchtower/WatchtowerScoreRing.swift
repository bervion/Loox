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

/// 270° speedometer gauge that visualises vault health score (0-100).
///
/// Geometry mirrors `ScoreRing` in `Design System/ui_kits/ios-app/Watchtower.jsx`:
/// - Arc open at the bottom, starting at 135° sweeping 270° clockwise.
/// - Green→blue gradient fill stroke with a glow-shadow effect.
/// - 44 tick marks (major every 4th).
/// - Filled triangle marker at the fill tip.
/// - Center: large score number (vaultMono) + band label beneath.
struct WatchtowerScoreRing: View {
    let score: Int

    // DS geometry constants (proportional — scaled by the GeometryReader)
    private enum Geo {
        static let baseWidth: CGFloat  = 232
        static let baseHeight: CGFloat = 196
        static let cx: CGFloat = baseWidth / 2      // 116
        static let cy: CGFloat = 104
        static let radius: CGFloat = 86
        static let bandWidth: CGFloat = 18
        static let startDeg: CGFloat = 135
        static let sweepDeg: CGFloat = 270
        static let tickCount = 44
    }

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Drives the sweep animation; jumps instantly under Reduce Motion
    @State private var animatedFraction: CGFloat = 0

    private var fraction: CGFloat { CGFloat(max(0, min(100, score))) / 100 }
    private var endDeg: CGFloat { Geo.startDeg + Geo.sweepDeg * fraction }

    // Green→blue gradient tip colour (lerp matching the DS hex values)
    private func tipColor(at f: CGFloat) -> Color {
        let r = lerp(0x16, 0x38, f)
        let g = lerp(0xA3, 0xBD, f)
        let b = lerp(0x4A, 0xF8, f)
        return Color(red: r / 255, green: g / 255, blue: b / 255)
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    var body: some View {
        let band = scoreBand(for: score)
        let theme = env.theme.active

        GeometryReader { geo in
            // Scale the DS base dimensions to fit the available width
            let scale = geo.size.width / Geo.baseWidth
            let cx = Geo.cx * scale
            let cy = Geo.cy * scale
            let r  = Geo.radius * scale
            let bw = Geo.bandWidth * scale

            Canvas { ctx, size in
                drawTrack(ctx: ctx, cx: cx, cy: cy, r: r, bw: bw, theme: theme)
                drawFill(ctx: ctx, cx: cx, cy: cy, r: r, bw: bw)
                drawTicks(ctx: ctx, cx: cx, cy: cy, r: r, scale: scale, theme: theme)
                drawMarker(ctx: ctx, cx: cx, cy: cy, r: r, bw: bw)
            }
            .frame(width: geo.size.width, height: geo.size.height)

            // Center readout (outside Canvas so Dynamic Type works)
            scoreReadout(band: band, theme: theme, cy: cy, scale: scale)
        }
        .frame(width: Geo.baseWidth, height: Geo.baseHeight)
        .onAppear {
            let target = fraction
            if reduceMotion {
                animatedFraction = target
            } else {
                withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: Motion.slow)) {
                    animatedFraction = target
                }
            }
        }
        .onChange(of: score) { _, _ in
            let target = fraction
            if reduceMotion {
                animatedFraction = target
            } else {
                withAnimation(.vault(.timingCurve(0.32, 0.72, 0, 1, duration: Motion.slow),
                                     reduceMotion: reduceMotion) ?? .default) {
                    animatedFraction = target
                }
            }
        }
        .accessibilityLabel(Text("Security score: \(score)"))
    }

    // MARK: - Drawing helpers

    private func drawTrack(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat,
                           r: CGFloat, bw: CGFloat, theme: AppTheme) {
        var path = Path()
        path.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                    startAngle: .degrees(Geo.startDeg),
                    endAngle: .degrees(Geo.startDeg + Geo.sweepDeg),
                    clockwise: false)
        ctx.stroke(path,
                   with: .color(Color(rgb: theme.primaryText).opacity(0.07)),
                   style: StrokeStyle(lineWidth: bw, lineCap: .round))
    }

    private func drawFill(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat,
                          r: CGFloat, bw: CGFloat) {
        guard animatedFraction > 0 else { return }
        let currentEnd = Geo.startDeg + Geo.sweepDeg * animatedFraction
        var path = Path()
        path.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                    startAngle: .degrees(Geo.startDeg),
                    endAngle: .degrees(currentEnd),
                    clockwise: false)
        // Green→blue gradient matching the DS linearGradient definition
        let gradient = Gradient(colors: [
            Color(red: 0x16/255, green: 0xA3/255, blue: 0x4A/255), // #16A34A
            Color(red: 0x10/255, green: 0xB9/255, blue: 0x81/255), // #10B981
            Color(red: 0x38/255, green: 0xBD/255, blue: 0xF8/255), // #38BDF8
        ])
        ctx.stroke(path,
                   with: .linearGradient(gradient,
                                         startPoint: CGPoint(x: cx - r, y: cy),
                                         endPoint: CGPoint(x: cx + r, y: cy)),
                   style: StrokeStyle(lineWidth: bw, lineCap: .round))
    }

    private func drawTicks(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat,
                           r: CGFloat, scale: CGFloat, theme: AppTheme) {
        let tickColor = Color(rgb: theme.primaryText).opacity(0.16)
        for i in 0...Geo.tickCount {
            let deg = Geo.startDeg + Geo.sweepDeg * CGFloat(i) / CGFloat(Geo.tickCount)
            let isMajor = i % 4 == 0
            let length: CGFloat = (isMajor ? 11 : 8) * scale
            let strokeW: CGFloat = (isMajor ? 2.4 : 1.5) * scale
            let innerR = r - length / 2
            let outerR = r + length / 2
            let rad = deg * .pi / 180
            let ax = cx + innerR * cos(rad)
            let ay = cy + innerR * sin(rad)
            let bx = cx + outerR * cos(rad)
            let by = cy + outerR * sin(rad)
            var path = Path()
            path.move(to: CGPoint(x: ax, y: ay))
            path.addLine(to: CGPoint(x: bx, y: by))
            ctx.stroke(path, with: .color(tickColor),
                       style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
        }
    }

    private func drawMarker(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat,
                            r: CGFloat, bw: CGFloat) {
        guard animatedFraction > 0 else { return }
        let currentEnd = Geo.startDeg + Geo.sweepDeg * animatedFraction
        let baseR = r - bw / 2 - 6
        // half-angle subtended by a 16pt base arc at baseR
        let halfDeg = (16 / baseR) * (180 / .pi)
        let endRad = currentEnd * .pi / 180

        func polar(_ rad: CGFloat, _ deg: CGFloat) -> CGPoint {
            let a = deg * .pi / 180
            return CGPoint(x: cx + rad * cos(a), y: cy + rad * sin(a))
        }

        let tip   = polar(baseR + 13, currentEnd)
        let left  = polar(baseR, currentEnd - halfDeg)
        let right = polar(baseR, currentEnd + halfDeg)

        var path = Path()
        path.move(to: tip)
        path.addLine(to: left)
        path.addLine(to: right)
        path.closeSubpath()

        ctx.fill(path, with: .color(tipColor(at: animatedFraction)))
    }

    @ViewBuilder
    private func scoreReadout(band: ScoreBand, theme: AppTheme,
                              cy: CGFloat, scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(height: (cy - 26 * scale))
            Text("\(score)")
                .font(.vaultMono(.largeTitle, weight: .bold))
                .themedForeground(.primary)
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
