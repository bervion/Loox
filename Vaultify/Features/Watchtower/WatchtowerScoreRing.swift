import SwiftUI

// MARK: - Band

/// Security band derived from a health score, matching the DS threshold spec.
nonisolated struct ScoreBand {
    let label: LocalizedStringResource
    let role: ThemeRole
}

// MARK: - Gauge display hues

/// Fixed display palette for the Watchtower gauge band and strength bar,
/// sampled from the 1Password reference. The semantic status tokens are tuned
/// for TEXT contrast (a deep teal-green, a dark amber) and read heavy on a wide
/// decorative band, so the band paint uses these vivid hues directly — the same
/// exact colors in every theme and appearance. Text/icons keep the tokens.
nonisolated enum WatchtowerPalette {
    static let deepGreen: UInt32 = 0x3E8E27
    static let green: UInt32     = 0x52C13C
    static let yellow: UInt32    = 0xF5D22B
    static let orange: UInt32    = 0xF79E1F
    static let red: UInt32       = 0xE94E2B
    /// The gauge's cool endpoint: the band drifts toward this sky blue over its
    /// last stretch (the 1P tail gradient), scaled by how safe the score is.
    static let skyTail: UInt32   = 0x5BBDEE
    /// Mid ramp of the safety morph, between yellow and orange.
    static let amber: UInt32     = 0xF5B322
}

/// Display green for the gauge band and strength-bar track (band paint only).
nonisolated func watchtowerGaugeGreen(_ theme: AppTheme) -> UInt32 {
    WatchtowerPalette.green
}

/// Display amber for the gauge's mid ramp — same band-paint layer.
nonisolated func watchtowerGaugeAmber(_ theme: AppTheme) -> UInt32 {
    WatchtowerPalette.amber
}

/// Display hue for one strength grade on the Watchtower strength bar — the same
/// decorative band-paint layer as `watchtowerGaugeGreen/Amber` (text keeps the
/// semantic tokens). Five stops of the 1P ramp: deep green, green, yellow,
/// orange, red.
nonisolated func watchtowerGradeHue(_ grade: PasswordGrade, theme: AppTheme) -> UInt32 {
    switch grade {
    case .excellent: return WatchtowerPalette.deepGreen
    case .strong: return WatchtowerPalette.green
    case .fair: return WatchtowerPalette.yellow
    case .weak: return WatchtowerPalette.orange
    case .veryWeak: return WatchtowerPalette.red
    }
}

/// Bands on the REAL 0–1000 audit scale (proposal thresholds 800/500).
nonisolated func scoreBand(for score: Int) -> ScoreBand {
    if score >= 800 {
        return ScoreBand(label: "Fairly secure", role: .success)
    } else if score >= 500 {
        return ScoreBand(label: "Needs attention", role: .warning)
    } else {
        return ScoreBand(label: "At risk", role: .destructive)
    }
}

// MARK: - WatchtowerScoreRing

/// 270° "temperature" gauge for the vault health score (0–100), 1Password-style.
///
/// The band is ALWAYS drawn full; the score is communicated by colour, a rolling
/// count-up, and a marker — not by arc length. Choreography:
///   1. ignite — the grey track crossfades to the destructive hue (whole arc)
///   2. hold   — a short beat at red, number at 0
///   3. count  — the number rolls up odometer-style while the whole band's hue
///               morphs red → amber → green along the safety blend. The dial is
///               a spinning DISC: the ticks and the band's conic gradient rotate
///               together like a flywheel on an underdamped spring — fast
///               forward, overshoot, reverse, settle
///   4. settle — a triangle marker rises from the readout toward the band with
///               a soft bounce while the "Calculating" caption crossfades to
///               the band label
///
/// The dial is driven by `TimelineView(.animation)` (a real per-frame clock)
/// because `Canvas` does NOT interpolate a `withAnimation`-driven `@State` — it
/// reads the final value immediately. The readout number lives OUTSIDE the
/// canvas so `.contentTransition(.numericText)` can roll its digits. After the
/// intro everything freezes to a static render (no battery drain). Reduce
/// Motion shows the settled state immediately.
/// Session gate for the Watchtower intro animations: the intro is a data-arrival
/// moment, not a tab decoration — it replays only when the persona changes or the
/// user pulls to refresh (the screen encodes both in `introKey`), never on every
/// tab switch.
@MainActor enum WatchtowerIntroGate {
    static var ring: String?
    static var bar: String?
}

struct WatchtowerScoreRing: View {

    let score: Int
    /// Identity of the current data context ("persona|refreshCount"). The intro
    /// plays once per key; revisiting the tab with the same key shows the settled
    /// dial. Empty = ungated (always play on appear).
    var introKey: String = ""

    // MARK: Geometry (proportional — scaled by GeometryReader)
    private enum Geo {
        static let baseWidth: CGFloat  = 272
        static let baseHeight: CGFloat = 230
        static let cx: CGFloat = baseWidth / 2     // 136
        /// Must keep the band's outer edge (cy − radius − bandWidth/2) ≥ 1pt
        /// inside the canvas or the arc apex gets clipped flat.
        static let cy: CGFloat = 124
        static let radius: CGFloat = 106
        static let bandWidth: CGFloat = 30
        static let startDeg: CGFloat = 135
        static let sweepDeg: CGFloat = 270
        /// Ticks tile the FULL disc (they rotate through the window). 28 divides
        /// 360° so the pattern is seamless, alternates long/short cleanly, and
        /// puts a tick exactly on both window ends once the disc settles.
        static let discTickCount = 28
    }

    // MARK: Intro timeline (fractions of `duration`)
    private enum Intro {
        static let duration: Double = 2.3
        static let igniteEnd: Double   = 0.16   // grey → red crossfade
        static let holdEnd: Double     = 0.25   // beat at red, number 0
        static let countEnd: Double    = 0.83   // roll-up + hue morph
        static let markerStart: Double = 0.74   // marker rise window start
        static let spinFadeStart: Double = 0.88 // blend residual spin → rest pose
        /// Readout update cadence — fast enough that `.numericText` rolls
        /// continuously (the odometer blur), slow enough to stay cheap.
        static let tickMs: Int = 40
    }

    // MARK: Disc spring (the flywheel spin: forward, overshoot, reverse, settle)
    private enum Spin {
        static let travelDeg: CGFloat = 80      // rest-pose rotation the spring aims for
        static let zeta: CGFloat = 0.28         // damping ratio (underdamped → reversals)
        static let omega: CGFloat = 4.2         // natural frequency, rad/s
    }

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // While true the TimelineView clock runs the intro; flips false when it finishes.
    @State private var animating = false
    @State private var startDate = Date()
    // Readout state — driven by `introTask` so digits roll via numericText.
    @State private var displayedScore = 0
    @State private var rolling = false
    @State private var settled = true
    @State private var introTask: Task<Void, Never>?

    private var targetFraction: CGFloat { CGFloat(max(0, min(1000, score))) / 1000 }

    /// The audit now scores on a real 0–1000 scale (six pillars) — the readout
    /// shows it directly; the old ×10 display shim is gone.
    private var displayTarget: Int { max(0, min(1000, score)) }

    var body: some View {
        let theme = env.theme.active
        let band  = scoreBand(for: score)

        GeometryReader { geo in
            let scale = geo.size.width / Geo.baseWidth
            let cx = Geo.cx * scale
            let cy = Geo.cy * scale
            let r  = Geo.radius * scale
            let bw = Geo.bandWidth * scale

            ZStack {
                if animating && !reduceMotion {
                    TimelineView(.animation) { timeline in
                        let p = clamp01(CGFloat(timeline.date.timeIntervalSince(startDate)) / CGFloat(Intro.duration))
                        dial(progress: p, cx: cx, cy: cy, r: r, bw: bw, scale: scale,
                             theme: theme, size: geo.size)
                    }
                } else {
                    // Settled / Reduce-Motion: render the final frame statically.
                    dial(progress: 1, cx: cx, cy: cy, r: r, bw: bw, scale: scale,
                         theme: theme, size: geo.size)
                }

                readout(band: band, color: theme.color(band.role), cy: cy, scale: scale)
            }
        }
        .frame(width: Geo.baseWidth, height: Geo.baseHeight)
        .onAppear {
            if introKey.isEmpty || WatchtowerIntroGate.ring != introKey {
                WatchtowerIntroGate.ring = introKey
                trigger()
            } else {
                settleInstantly()   // same data context — no replay on tab switch
            }
        }
        .onChange(of: introKey) { _, new in
            WatchtowerIntroGate.ring = new
            trigger()
        }
        // Data drift (an item edited elsewhere while this tab stays mounted):
        // update the readout silently — a score change is not an intro moment.
        // Mid-intro the running clock already lands on the live target.
        .onChange(of: score) { _, _ in
            if !animating { settleInstantly() }
        }
        .onDisappear { introTask?.cancel() }
        .accessibilityLabel(Text("Security score: \(displayTarget), ") + Text(band.label))
    }

    // MARK: - Intro trigger

    /// Jump straight to the settled state (no intro) — used when the tab
    /// reappears within the same data context or the score drifts silently.
    private func settleInstantly() {
        introTask?.cancel()
        animating = false
        rolling = false
        displayedScore = displayTarget
        settled = true
    }

    private func trigger() {
        introTask?.cancel()
        guard !reduceMotion else {
            animating = false; displayedScore = displayTarget; rolling = false; settled = true
            return
        }
        startDate = Date()
        animating = true
        displayedScore = 0
        rolling = false
        settled = false
        let start = startDate
        introTask = Task { @MainActor in
            // Roll the readout in lockstep with the canvas hue morph.
            while !Task.isCancelled {
                let p = Date().timeIntervalSince(start) / Intro.duration
                if p >= 1 { break }
                let c = countProgress(CGFloat(p))
                rolling = p >= Intro.holdEnd && p < Intro.countEnd
                withAnimation(.linear(duration: 0.09)) {
                    displayedScore = Int((c * CGFloat(displayTarget)).rounded())
                }
                try? await Task.sleep(for: .milliseconds(Intro.tickMs))
            }
            guard !Task.isCancelled else { return }
            rolling = false
            withAnimation(Motion.standard) {
                displayedScore = displayTarget
                settled = true
            }
            // Freeze the TimelineView clock to a static render.
            animating = false
        }
    }

    // MARK: - Timeline → phase values

    /// Count-up progress (0→1) for intro progress `p` — eased so the number and
    /// the hue morph accelerate in and land softly, like 1Password's roll.
    private func countProgress(_ p: CGFloat) -> CGFloat {
        easeInOut(clamp01((p - Intro.holdEnd) / (Intro.countEnd - Intro.holdEnd)))
    }

    /// Whole-band colour ignition (0 = grey track, 1 = fully coloured).
    private func igniteAmount(_ p: CGFloat) -> CGFloat {
        easeInOut(clamp01(p / Intro.igniteEnd))
    }

    /// Marker rise/fade progress during the settle window.
    private func markerProgress(_ p: CGFloat) -> CGFloat {
        clamp01((p - Intro.markerStart) / (1 - Intro.markerStart))
    }

    /// Disc rotation (degrees) at intro progress `p`. Underdamped spring step
    /// response from the count start: spins forward past the rest pose,
    /// reverses, oscillates and decays — the 1Password flywheel. The residual
    /// wobble is blended to the exact rest pose over the last stretch so the
    /// freeze to the static render is seamless.
    private func discRotation(_ p: CGFloat) -> CGFloat {
        guard p > Intro.holdEnd else { return 0 }
        guard p < 1 else { return Spin.travelDeg }
        let s = (p - Intro.holdEnd) * CGFloat(Intro.duration)   // seconds of spin
        let zw = Spin.zeta * Spin.omega
        let wd = Spin.omega * sqrt(1 - Spin.zeta * Spin.zeta)   // damped frequency
        let decay = exp(-zw * s)
        let response = 1 - decay * (cos(wd * s) + zw / wd * sin(wd * s))
        let spring = Spin.travelDeg * response
        let blend = easeInOut(clamp01((p - Intro.spinFadeStart) / (1 - Intro.spinFadeStart)))
        return spring + (Spin.travelDeg - spring) * blend
    }

    // MARK: - Composed dial (Canvas: track + spinning band/ticks + marker)

    @ViewBuilder
    private func dial(progress p: CGFloat, cx: CGFloat, cy: CGFloat, r: CGFloat,
                      bw: CGFloat, scale: CGFloat, theme: AppTheme, size: CGSize) -> some View {
        let f = countProgress(p) * targetFraction
        // The disc's rotation offset relative to its REST pose: 0 once settled,
        // negative while the spring is still catching up. Applying the delta
        // (not the absolute angle) keeps the settled gradient/tick layout
        // identical to the designed rest pose.
        let spin = discRotation(p) - Spin.travelDeg
        let base = safetyRGB(f, theme: theme)
        Canvas { ctx, _ in
            drawTrack(ctx: ctx, cx: cx, cy: cy, r: r, bw: bw, theme: theme)
            drawBand(ctx: ctx, cx: cx, cy: cy, r: r, bw: bw, base: base,
                     fraction: f, spin: spin, alpha: igniteAmount(p))
            drawTicks(ctx: ctx, cx: cx, cy: cy, r: r, bw: bw, scale: scale,
                      base: base, fraction: f, spin: spin, alpha: igniteAmount(p))
            drawMarker(ctx: ctx, cx: cx, cy: cy, r: r, bw: bw, scale: scale,
                       progress: markerProgress(p),
                       color: Color(rgb: safetyRGB(targetFraction, theme: theme)))
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Drawing helpers

    private func arcPath(cx: CGFloat, cy: CGFloat, r: CGFloat) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                    startAngle: .degrees(Geo.startDeg),
                    endAngle:   .degrees(Geo.startDeg + Geo.sweepDeg),
                    clockwise: false)
        return path
    }

    private func drawTrack(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat,
                           r: CGFloat, bw: CGFloat, theme: AppTheme) {
        ctx.stroke(arcPath(cx: cx, cy: cy, r: r),
                   with: .color(Color(rgb: theme.primaryText).opacity(0.08)),
                   style: StrokeStyle(lineWidth: bw, lineCap: .round))
    }

    /// Band hue at window position `t` (0 = start cap, 1 = end cap): a darker
    /// head eases into the base hue, a plateau carries it, and the last stretch
    /// drifts toward the sky-blue endpoint — the 1P tail gradient. The drift is
    /// scaled by `fraction` so a risky red dial never turns partly blue.
    private func bandRGB(at t: CGFloat, base: UInt32, fraction: CGFloat) -> UInt32 {
        let head = RGBMath.blend(base, 0x000000, 0.16)
        switch t {
        case ..<0.35:
            return RGBMath.blend(head, base, Double(easeInOut(t / 0.35)))
        case ..<0.72:
            return base
        default:
            let drift = Double(clamp01((t - 0.72) / 0.28) * fraction)
            return RGBMath.blend(base, WatchtowerPalette.skyTail, drift)
        }
    }

    /// Full-length coloured band: hue = safety blend for `fraction`. The fill is
    /// a conic gradient painted on the ROTATING DISC (offset by `spin`), so its
    /// darker head and sky-tinted tail sweep through the window while the
    /// flywheel spins — the multi-tone "disc" look. `alpha` runs the grey→colour
    /// ignition. The stops wrap continuously so no seam shows at any rotation.
    private func drawBand(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat,
                          r: CGFloat, bw: CGFloat, base: UInt32,
                          fraction: CGFloat, spin: CGFloat, alpha: CGFloat) {
        guard alpha > 0.001 else { return }
        // The window spans locations 0…0.75 of the conic turn; sample the band
        // curve at fixed window positions (extra stop at 0.87 keeps the tail's
        // curve from flattening into one linear blend); 0.75→1 blends the tail
        // back to the head across the hidden gap (seamless while spinning).
        let stops = [0, 0.35, 0.72, 0.87, 1].map { (t: CGFloat) in
            Gradient.Stop(color: Color(rgb: bandRGB(at: t, base: base, fraction: fraction)),
                          location: t * 0.75)
        } + [Gradient.Stop(color: Color(rgb: bandRGB(at: 0, base: base, fraction: fraction)),
                           location: 1)]
        var layer = ctx
        layer.opacity = Double(alpha)
        layer.stroke(arcPath(cx: cx, cy: cy, r: r),
                     with: .conicGradient(Gradient(stops: stops),
                                          center: CGPoint(x: cx, y: cy),
                                          angle: .degrees(Double(Geo.startDeg + spin))),
                     style: StrokeStyle(lineWidth: bw, lineCap: .round))
    }

    /// Scale ticks drawn ON the band, CENTERED on its midline (1P-style), in a
    /// darker shade of the band hue beneath them. They belong to the rotating
    /// disc: uniform around the full circle, offset by `spin`, and clipped to
    /// the 270° window as they sweep through it. Long/short alternation makes
    /// the rotation legible.
    private func drawTicks(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat,
                           r: CGFloat, bw: CGFloat, scale: CGFloat,
                           base: UInt32, fraction: CGFloat, spin: CGFloat, alpha: CGFloat) {
        guard alpha > 0.001 else { return }
        let spacing = 360 / CGFloat(Geo.discTickCount)
        for i in 0..<Geo.discTickCount {
            // Normalize the tick's disc angle into [0, 360) past the window start.
            var offset = (spacing * CGFloat(i) + spin).truncatingRemainder(dividingBy: 360)
            if offset < 0 { offset += 360 }
            guard offset <= Geo.sweepDeg + 0.5 else { continue } // outside the window
            // The tick and the gradient rotate together, so its band position is
            // its REST angle (spin cancels out) — the colour under it is stable.
            var discDeg = (spacing * CGFloat(i)).truncatingRemainder(dividingBy: 360)
            if discDeg < 0 { discDeg += 360 }
            let bandPos = min(1, discDeg / Geo.sweepDeg)
            let tickColor = Color(rgb: RGBMath.blend(
                bandRGB(at: bandPos, base: base, fraction: fraction), 0x000000, 0.30))
                .opacity(0.85 * Double(alpha))
            let deg = Geo.startDeg + offset
            let isMajor = i % 2 == 0
            let len = bw * (isMajor ? 0.52 : 0.34)
            let innerR = r - len / 2
            let outerR = r + len / 2
            let rad = deg * .pi / 180
            var path = Path()
            path.move(to: CGPoint(x: cx + innerR * cos(rad), y: cy + innerR * sin(rad)))
            path.addLine(to: CGPoint(x: cx + outerR * cos(rad), y: cy + outerR * sin(rad)))
            ctx.stroke(path, with: .color(tickColor),
                       style: StrokeStyle(lineWidth: 1.8 * scale, lineCap: .round))
        }
    }

    /// Triangle marker in the ring interior pointing OUTWARD at the band's apex.
    /// FIXED at top center (1P idiom): position never encodes the score — the
    /// number and the band hue do — so the marker only rises, points up, and
    /// takes the score's safety color. During the settle window it rises from
    /// the readout toward the band with a soft overshoot bounce while fading in.
    private func drawMarker(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat,
                            r: CGFloat, bw: CGFloat, scale: CGFloat,
                            progress: CGFloat, color: Color) {
        guard progress > 0.001 else { return }
        // 270° = straight up in screen coordinates (y grows downward).
        let rad: CGFloat = 270 * .pi / 180
        let triH: CGFloat = 13 * scale
        let triW: CGFloat = 16 * scale
        let gap:  CGFloat = 6  * scale
        let strokeW: CGFloat = 4 * scale   // round-joined stroke = rounded corners
        // Radial rise: starts 26pt closer to the readout, overshoots slightly
        // past the rest position (easeOutBack), then settles — the soft bounce.
        let rise = (1 - easeOutBack(progress)) * 26 * scale
        let centreR = r - bw / 2 - gap - triH / 2 - rise
        let mcx = cx + centreR * cos(rad)
        let mcy = cy + centreR * sin(rad)
        var tri = Path()
        tri.move(to: CGPoint(x: 0, y: -triH / 2))            // tip → points at the band
        tri.addLine(to: CGPoint(x: -triW / 2, y: triH / 2))
        tri.addLine(to: CGPoint(x:  triW / 2, y: triH / 2))
        tri.closeSubpath()
        tri = tri.applying(
            CGAffineTransform(translationX: mcx, y: mcy).rotated(by: rad + .pi / 2))
        var layer = ctx
        layer.opacity = Double(easeOut(progress))
        layer.fill(tri, with: .color(color))
        layer.stroke(tri, with: .color(color),
                     style: StrokeStyle(lineWidth: strokeW, lineJoin: .round))
    }

    // MARK: - Readout (rolling number + label crossfade)

    @ViewBuilder
    private func readout(band: ScoreBand, color: Color, cy: CGFloat, scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Display-size figure centered on the dial's center (1P proportions):
            // the spacer puts the number's vertical middle on `cy`, which drops
            // the status line to the arc's lower opening.
            Spacer().frame(height: cy - 38 * scale)
            // SF (not vaultCode): the score is a headline figure, not a secret;
            // monospacedDigit keeps the odometer roll from jittering sideways.
            Text("\(displayedScore)")
                .vaultType(.scoreDisplay)
                .themedForeground(.primary)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(displayedScore)))
                .blur(radius: rolling ? 1.1 : 0)
                .animation(Motion.standard, value: rolling)

            // Band label uses the DISCRETE semantic role (not the continuous
            // sweep tint) so it always matches the exact 80/50 thresholds. The
            // "Calculating" caption crossfades out when the roll settles.
            // Uppercased at render (1P's "FANTASTIC" register) — the catalog
            // strings stay sentence case for every other surface.
            ZStack {
                Text("Calculating")
                    .vaultType(.sectionLabel)
                    .themedForeground(.secondary)
                    .kerning(1.4)
                    .opacity(settled ? 0 : 1)
                Text(band.label)
                    .vaultType(.sectionLabel)
                    .foregroundStyle(color)
                    .kerning(1.4)
                    .opacity(settled ? 1 : 0)
            }
            .textCase(.uppercase)
            .animation(Motion.standard, value: settled)
            .padding(.top, 12 * scale)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Colour + easing

    /// Safety colour for a fraction: red (0) → amber (0.5) → green (1), on the
    /// fixed `WatchtowerPalette` display hues — the same ramp the strength bar's
    /// grades use, so the dial and the bar always speak one palette.
    private func safetyRGB(_ f: CGFloat, theme: AppTheme) -> UInt32 {
        let t = Double(max(0, min(1, f)))
        if t < 0.5 {
            return RGBMath.blend(WatchtowerPalette.red, watchtowerGaugeAmber(theme), t / 0.5)
        } else {
            return RGBMath.blend(watchtowerGaugeAmber(theme), watchtowerGaugeGreen(theme), (t - 0.5) / 0.5)
        }
    }

    private func clamp01(_ x: CGFloat) -> CGFloat { max(0, min(1, x)) }
    private func easeOut(_ t: CGFloat) -> CGFloat { 1 - pow(1 - t, 3) }
    private func easeInOut(_ t: CGFloat) -> CGFloat {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
    /// Ease-out with a gentle overshoot past 1 (the marker's bounce).
    private func easeOutBack(_ t: CGFloat) -> CGFloat {
        let c1: CGFloat = 1.70158
        let c3 = c1 + 1
        let u = t - 1
        return 1 + c3 * u * u * u + c1 * u * u
    }
}
