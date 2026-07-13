import SwiftUI

/// Apple-boot-style brand swirl: the Loox six-circle symbol centred in rings of
/// rainbow dots (the `SwirlGradient` mesh masked into moving circles, so each dot
/// takes the gradient colour at its position). A reusable loading/brand indicator
/// with three modes:
///
/// - `.reveal` — plays once: dots emanate from the logo and settle into the four
///   static rings, then hold. (Default; the calm brand mark.)
/// - `.loop` — a continuous loading pulse: dots stream outward from the inner ring
///   to the outer ring, growing and fading to alpha 0 as they reach it, forever.
/// - `.dismiss` — the settled rings burst outward and fade to nothing, once.
///
/// Same mathematical layout throughout: four equally-spaced rings, 24 dots each,
/// odd rings offset half a step (interleave), dot radius ∝ ring radius. Driven by
/// `TimelineView(.animation)` at 60fps; it stops ticking once a one-shot completes.
struct LooxSwirlAnimationView: View {
    enum Mode: Equatable { case reveal, loop, dismiss }

    var mode: Mode = .reveal
    /// Centre logo height as a fraction of the view's smaller dimension.
    var logoFraction: CGFloat = 0.26

    // Layout (fractions of the view's smaller dimension).
    private let perRing = 24
    private let dotK: CGFloat = 0.047
    private let ringInner: CGFloat = 0.32      // ring 1
    private let ringStep: CGFloat = 0.047      // → ring 4 at 0.461
    private var ringOuter: CGFloat { ringInner + 3 * ringStep }
    private var halfStep: Double { .pi / Double(perRing) }
    /// Emanation origin — measured off the reference video: dots spawn at ~54% of
    /// the outer ring's radius (just outside the logo), tiny and faint.
    private var spawnR: CGFloat { 0.54 * ringOuter }
    /// Total pattern swirl during a journey (~57°, ease-out), also measured.
    private let swirl: Double = 57 * .pi / 180

    // Timings (from the reference: ~0.2s ring stagger, ~1s travel per ring).
    private let ringStagger: Double = 0.20
    private let travel: Double = 1.0
    private var revealDur: Double { 3 * ringStagger + travel }   // 1.6s
    /// Dispersal (measured off the Apple reference): a ~0.75s ease-out particle
    /// scatter, then the dots linger in place and fade for ~1.1s.
    private let scatterFlight: Double = 0.75
    private let scatterLinger: Double = 1.1
    private var dismissDur: Double { scatterFlight + scatterLinger }
    /// Slow constant rotation layered over the loop cycle so the pattern never
    /// visibly stalls (rad/s ≈ 15°/s).
    private let loopDrift: Double = 15 * .pi / 180

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    @State private var ticking = true
    @State private var runID = 0

    /// Drawing area beyond the nominal frame so scattering dots spill past the
    /// square instead of being cut off (the measured dispersal reaches ~2.1x the
    /// outer ring radius).
    private let overscan: CGFloat = 2.2

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image("SwirlGradient")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width * overscan, height: geo.size.height * overscan)
                    .mask { maskContent }
                    .frame(width: geo.size.width * overscan, height: geo.size.height * overscan)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                Image("BrandSymbol")
                    .resizable()
                    .scaledToFit()
                    .frame(height: min(geo.size.width, geo.size.height) * logoFraction)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
        .onAppear(perform: restart)
        .onChange(of: mode) { _, _ in restart() }
    }

    @ViewBuilder private var maskContent: some View {
        if ticking && !reduceMotion {
            TimelineView(.animation) { context in
                canvas(t: context.date.timeIntervalSince(start))
            }
        } else {
            // Frozen frame once a one-shot finishes (or under Reduce Motion).
            canvas(t: frozenTime)
        }
    }

    private var frozenTime: Double {
        switch mode {
        case .reveal: return revealDur       // settled rings
        case .loop:   return 0               // Reduce Motion: hold the settled look
        case .dismiss: return dismissDur     // fully dismissed (empty)
        }
    }

    private func canvas(t: Double) -> some View {
        Canvas { gc, size in draw(gc, size, t) }
    }

    /// Restart the animation from the top; loop keeps ticking, one-shots stop.
    private func restart() {
        start = .now
        runID += 1
        let id = runID
        ticking = true
        guard !reduceMotion else { ticking = false; return }
        let stopAfter: Double? = mode == .loop ? nil : (mode == .reveal ? revealDur : dismissDur)
        if let stopAfter {
            Task {
                try? await Task.sleep(for: .seconds(stopAfter + 0.05))
                if runID == id { ticking = false }
            }
        }
    }

    // MARK: Drawing

    private func draw(_ gc: GraphicsContext, _ size: CGSize, _ t: Double) {
        // The canvas is overscan-sized; ring geometry stays relative to the
        // NOMINAL frame so only the spill-over gains room, not the layout.
        let d = min(size.width, size.height) / overscan
        let c = CGPoint(x: size.width / 2, y: size.height / 2)

        // Reduce Motion: a calm, fully settled ring set (nothing for dismiss).
        if reduceMotion {
            if mode != .dismiss { drawSettled(gc, c, d) }
            return
        }

        switch mode {
        case .reveal:  drawReveal(gc, c, d, t)
        case .loop:    drawLoop(gc, c, d, t)
        case .dismiss: drawFadeOut(gc, c, d, t)
        }
    }

    /// The measured emanation (shared by reveal and the loop's first act): the
    /// OUTER ring blooms first from just outside the logo, trailing rings launch
    /// ~0.2s apart and settle inward-last. Each ring swirls ~57° along ITS OWN
    /// journey (later rings still turning while earlier ones have settled — the
    /// staggered, non-uniform look of the reference). Dot size follows its
    /// current radius; alpha follows ring progress.
    private func drawEmanate(_ gc: GraphicsContext, _ c: CGPoint, _ d: CGFloat, _ t: Double,
                             drift: Double = 0) {
        for k in 0..<4 {                            // k = 0 OUTER … 3 inner
            let p = easeOutCubic(clamp01((t - Double(k) * ringStagger) / travel))
            guard p > 0.001 else { continue }
            let rf = ringOuter - CGFloat(k) * ringStep
            let radius = (spawnR + (rf - spawnR) * p) * d
            let dotR = dotK * radius * (0.6 + 0.4 * p)
            // Interleave parity by the ring's FINAL slot (settled pattern matches
            // the static layout); the ring turns INTO its final angle as p → 1.
            ring(gc, c, radius: radius, dotR: dotR, alpha: p,
                 angleOffset: Double((3 - k) % 2) * halfStep - swirl * (1 - p) + drift)
        }
    }

    /// One-shot reveal: the emanation, frozen once settled.
    private func drawReveal(_ gc: GraphicsContext, _ c: CGPoint, _ d: CGFloat, _ t: Double) {
        drawEmanate(gc, c, d, min(t, revealDur))
    }

    /// Loading loop: one full breath per cycle — the emanation plays out, then
    /// everything drifts outward and fades to 0 completely, rests a beat empty,
    /// and starts over. The pattern NEVER stops turning: a slow constant drift
    /// rides on top of the journey swirl (fast at spawn, easing as it grows),
    /// so the settled beat keeps rotating instead of stalling.
    private func drawLoop(_ gc: GraphicsContext, _ c: CGPoint, _ d: CGFloat, _ t: Double) {
        let hold = 0.35, rest = 0.25
        let cycle = revealDur + hold + dismissDur + rest
        let tc = t.truncatingRemainder(dividingBy: cycle)
        if tc < revealDur + hold {
            drawEmanate(gc, c, d, min(tc, revealDur), drift: loopDrift * tc)
        } else if tc < revealDur + hold + dismissDur {
            // Scatter: dots fly on their own — the group rotation freezes at the
            // orientation it had when the dispersal began.
            drawFadeOut(gc, c, d, tc - revealDur - hold,
                        drift: loopDrift * (revealDur + hold))
        }
        // else: rest — empty beat before the next breath (the drift reset at the
        // cycle wrap is invisible: nothing is on screen).
    }

    /// The measured Apple dispersal: each dot flies off on its OWN outward-biased
    /// random direction with an ease-out (dots grow ~25% and dim to half), then
    /// LINGERS in place, fading out completely. Deterministic per-dot randomness
    /// (hash of ring/index), so every frame agrees without stored state. Used for
    /// the dismiss one-shot and the fade act of each loop cycle.
    private func drawFadeOut(_ gc: GraphicsContext, _ c: CGPoint, _ d: CGFloat, _ t: Double,
                             drift: Double = 0) {
        let p1 = easeOutCubic(clamp01(t / scatterFlight))                 // flight
        let tail = 1 - clamp01((t - scatterFlight) / scatterLinger)      // linger fade
        let alpha = (1 - 0.5 * p1) * tail
        guard alpha > 0.01 else { return }
        for k in 0..<4 {
            let rf = ringInner + CGFloat(k) * ringStep
            let dotR = dotK * rf * d * (1 + 0.25 * p1)
            for i in 0..<perRing {
                let a = 2 * .pi * Double(i) / Double(perRing) + Double(k % 2) * halfStep + drift
                let sx = c.x + rf * d * cos(a)
                let sy = c.y + rf * d * sin(a)
                // Outward-biased random direction + distance per dot.
                let dir = a + (hash(k, i, 1) - 0.5) * 1.7
                let dist = (0.45 + 0.85 * hash(k, i, 2)) * ringOuter * d * p1
                let x = sx + dist * cos(dir)
                let y = sy + dist * sin(dir)
                gc.fill(Path(ellipseIn: CGRect(x: x - dotR, y: y - dotR,
                                               width: 2 * dotR, height: 2 * dotR)),
                        with: .color(.white.opacity(alpha)))
            }
        }
    }

    /// Deterministic per-dot pseudo-random in [0, 1) (classic fract-sin hash).
    private func hash(_ k: Int, _ i: Int, _ salt: Int) -> Double {
        let x = sin(Double(k) * 12.9898 + Double(i) * 78.233 + Double(salt) * 37.719) * 43758.5453
        return x - floor(x)
    }

    /// The static four-ring set (Reduce Motion fallback).
    private func drawSettled(_ gc: GraphicsContext, _ c: CGPoint, _ d: CGFloat) {
        for k in 0..<4 {
            let rf = ringInner + CGFloat(k) * ringStep
            let radius = rf * d
            ring(gc, c, radius: radius, dotR: dotK * radius, alpha: 1,
                 angleOffset: Double(k % 2) * halfStep)
        }
    }

    /// Draw one ring of `perRing` dots at `radius` with `alpha`.
    private func ring(_ gc: GraphicsContext, _ c: CGPoint, radius: CGFloat, dotR: CGFloat,
                      alpha: Double, angleOffset: Double) {
        guard dotR > 0.2 else { return }
        for i in 0..<perRing {
            let a = 2 * .pi * Double(i) / Double(perRing) + angleOffset
            let x = c.x + radius * cos(a)
            let y = c.y + radius * sin(a)
            gc.fill(Path(ellipseIn: CGRect(x: x - dotR, y: y - dotR, width: 2 * dotR, height: 2 * dotR)),
                    with: .color(.white.opacity(alpha)))
        }
    }

    private func clamp01(_ x: Double) -> Double { max(0, min(1, x)) }
    private func easeOutCubic(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
}
