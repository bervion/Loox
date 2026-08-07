import SwiftUI

/// The pinned full-bleed stage behind the story's scroll column: committed-dark
/// veil, the origin dot, and the scrap swarm — all sampled from `StoryField`
/// pure functions each Canvas tick, driven by one scalar from the scroll model.
/// Decorative only: hit-testing off, hidden from accessibility, paused whenever
/// Reduce Motion is on or the scene leaves the foreground (the scroll-scrubbed
/// positions still update — those are functional, not decorative).
struct StoryStageView: View {
    let model: StoryScrollProgressModel

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// Beat window across which the committed-dark canvas resolves into the
    /// user's theme. Shared with the copy column and the Skip control so text
    /// color always tracks the surface it actually sits on. Starts late in the
    /// consequence→turn transition (the outgoing white copy is mostly faded by
    /// then) and completes exactly as the turn page rests — the light
    /// returning IS the gather's payoff (owner decision, concept-final §1).
    ///
    /// `nonisolated` because the copy column reads them from inside
    /// `scrollTransition`'s `@Sendable` closure, which does not inherit the
    /// View's MainActor isolation.
    nonisolated static let themeResolveStart = 2.5
    nonisolated static let themeResolveEnd = 3.0

    private var paused: Bool { reduceMotion || scenePhase != .active }
    private var themeMix: Double {
        StoryField.smoothstep(model.beatPosition, Self.themeResolveStart, Self.themeResolveEnd)
    }

    var body: some View {
        ZStack {
            Color.black
            Color(rgb: theme.background).opacity(themeMix)
            TimelineView(.animation(minimumInterval: 1 / 60, paused: paused)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                canvas(t: t, beat: model.beatPosition, veilFade: 1 - themeMix)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func canvas(t: TimeInterval, beat: Double, veilFade: Double) -> some View {
        let ripple = rippleProgress(t: t, beat: beat)
        let burst = burstProgress(t: t)
        return Canvas { ctx, size in
            // Orbit geometry lands as TRUE circles: unit-space offsets are
            // rescaled so the ring's point radius comes off the short side
            // (unit space alone would stretch it into a tall ellipse that
            // never nests inside the sigil arcs). The height cap keeps the
            // ring clear of the copy column on squat canvases (iPad
            // landscape), where the short side is no longer the tight axis.
            let reach = Self.ringReach(size)
            let ringScale = CGSize(
                width: reach / (StoryField.ringRadius * max(size.width, 1)),
                height: reach / (StoryField.ringRadius * max(size.height, 1)))

            drawVeil(&ctx, size: size, t: t, fade: veilFade)
            drawWarningPool(&ctx, size: size, ripple: ripple, veilFade: veilFade)

            let dot = StoryField.originDot(t: t, beat: beat)
            if dot.opacity > 0.01 {
                stamp(&ctx, symbol: StageSymbol.glow, at: dot, in: size, baseSize: 76)
                stamp(&ctx, symbol: StageSymbol.dot, at: dot, in: size, baseSize: 10)
            }

            for index in 0..<StoryField.scrapCount {
                let sample = StoryField.sample(index: index, t: t, beat: beat,
                                               burst: burst, ringScale: ringScale)
                guard sample.opacity > 0.01 else { continue }
                let symbol = StageSymbol(scrap: StoryField.kind(index))
                stamp(&ctx, symbol: symbol, at: sample, in: size, baseSize: 44)
            }

            drawConsequence(&ctx, size: size, t: t, beat: beat, ripple: ripple)
            drawSanctuary(&ctx, size: size, t: t, beat: beat, burst: burst)
        } symbols: {
            // Rendered ONCE per Canvas pass and stamped per scrap — the glow is
            // pre-blurred here so no per-particle blur filter ever runs.
            // `mix` carries the canvas crossfade into the cards: the ring of
            // gathered scraps survives onto the user's own (possibly light)
            // theme background, where fixed white-alpha would be invisible.
            StoryScrapCard(icon: "dt_note_sticky", mix: themeMix, theme: theme)
                .tag(StageSymbol.note)
            StoryScrapCard(icon: "dt_message", mix: themeMix, theme: theme)
                .tag(StageSymbol.chat)
            StoryScrapCard(icon: "dt_globe", wide: true, mix: themeMix, theme: theme)
                .tag(StageSymbol.browser)
            StoryScrapCard(icon: "dt_key", mix: themeMix, theme: theme)
                .tag(StageSymbol.key)
            StoryScrapCard(icon: "dt_message", tint: StoryPalette.warning,
                           mix: themeMix, theme: theme)
                .tag(StageSymbol.chatWarning)
            Circle().fill(StoryPalette.textPrimary).frame(width: 10, height: 10)
                .tag(StageSymbol.dot)
            // The blur needs room INSIDE the symbol's bounds: blurring a circle
            // that already fills its frame clips the bleed and renders a
            // hard-edged disc instead of a glow.
            Circle().fill(StoryPalette.glow).frame(width: 44, height: 44)
                .blur(radius: 16)
                .frame(width: 76, height: 76)
                .tag(StageSymbol.glow)
            Image("BrandSymbol").resizable().scaledToFit()
                .frame(width: 56, height: 56)
                .tag(StageSymbol.mark)
        }
    }

    /// Seal exit: 0…1 over 0.8s after the hold completes, easing the ring
    /// outward while the route crossfade lands on Home behind it.
    private func burstProgress(t: TimeInterval) -> Double {
        guard let seal = model.sealTime else { return 0 }
        return StoryField.easeOut(min(max((t - seal) / 0.8, 0), 1))
    }

    /// The sanctuary orbit's radius in points: the short side carries it, with
    /// a height cap so squat canvases (iPad landscape) keep the ring inside
    /// the stage's upper half instead of sagging into the copy column.
    private static func ringReach(_ size: CGSize) -> CGFloat {
        min(StoryField.ringRadius * min(size.width, size.height), 0.17 * size.height)
    }

    // MARK: Sanctuary (the mark and its sigils)

    /// The Loox mark settles at the ring's centre as the theme resolves;
    /// concentric sigil arcs draw themselves around the orbit.
    private func drawSanctuary(_ ctx: inout GraphicsContext, size: CGSize,
                               t: TimeInterval, beat: Double, burst: Double) {
        // Assembled by the sanctuary page (index 4), not on the way out of it.
        let appear = StoryField.smoothstep(beat, 3.50, 3.95) * (1 - burst)
        guard appear > 0.01 else { return }

        let breathe = 1 + 0.02 * sin(t * (.pi * 2 / 4))
        // The seal blooms the mark's halo as the ring flings outward — the
        // vault flaring shut is the story's final frame.
        let bloom = 1 + burst * 1.6
        let mark = StoryField.Sample(position: StoryField.origin,
                                     opacity: appear, scale: breathe)
        let halo = StoryField.Sample(position: StoryField.origin,
                                     opacity: appear, scale: breathe * bloom)
        stamp(&ctx, symbol: .glow, at: halo, in: size, baseSize: 132)
        stamp(&ctx, symbol: .mark, at: mark, in: size, baseSize: 56)

        let center = CGPoint(x: StoryField.origin.x * size.width,
                             y: StoryField.origin.y * size.height)
        let accent = Color(rgb: theme.accentFill)
        let reach = Self.ringReach(size)

        // The orbit line the survivors ride: a faint accent circle that
        // tightens with the ring, so the gathered scraps read as HELD by the
        // sanctuary rather than hovering free. Radius mirrors
        // `StoryField.ringPoint` (same tighten window).
        let tighten = 1 - 0.35 * StoryField.smoothstep(beat, 4.30, 5.0)
        let orbitRadius = reach * tighten * (1 + burst * 0.6)
        let orbitRect = CGRect(x: center.x - orbitRadius, y: center.y - orbitRadius,
                               width: orbitRadius * 2, height: orbitRadius * 2)
        ctx.stroke(Path(ellipseIn: orbitRect),
                   with: .color(accent.opacity(0.16 * appear * (1 - burst))),
                   lineWidth: 1)

        // Sigil arcs: accent-tinted, trim-drawn, counter-rotating slowly. Drawn
        // in as the sanctuary arrives, complete on its resting frame.
        let trim = StoryField.smoothstep(beat, 3.60, 4.0)
        guard trim > 0.01 else { return }
        for (index, factor) in [1.34, 1.52].enumerated() {
            let radius = reach * factor * (1 + burst * 0.6)
            let direction: Double = index == 0 ? 1 : -1
            let start = Angle(radians: t * 0.10 * direction + Double(index) * 2.1)
            var path = Path()
            path.addArc(center: center, radius: radius,
                        startAngle: start,
                        endAngle: start + Angle(radians: trim * 4.4),
                        clockwise: false)
            ctx.stroke(path,
                       with: .color(accent.opacity(0.5 * appear * trim)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    // MARK: Consequence beat (the shared password ripples out)

    /// The send ripple: the user's tap drives it hard (a 0.9s one-shot that
    /// then holds — sent is sent), and scrolling deeper into the beat plays a
    /// softer version for non-tappers. Reeling into the turn drains it away.
    /// Everything the ripple feeds (rings, ghost copies, the warning pool) is
    /// gated to the consequence beat's own window — a send tapped here must
    /// not leave amber smoke over the hook when the user scrubs back up.
    private func rippleProgress(t: TimeInterval, beat: Double) -> Double {
        // Present only while the consequence page (index 2) is on screen.
        let window = StoryField.smoothstep(beat, 1.60, 1.95)
            * (1 - StoryField.smoothstep(beat, 2.40, 2.90))
        guard window > 0.001 else { return 0 }

        // Non-tappers get the soft version WHILE the page rests, not on the
        // way out of it.
        let scrolled = StoryField.smoothstep(beat, 1.95, 2.45) * 0.7
        let tapped: Double
        if let tap = model.sendTapTime {
            // Under Reduce Motion the TimelineView is paused, so `t` is frozen
            // and an elapsed-time ramp would never advance: the tap still has
            // to DO something, so it lands its full state at once.
            tapped = paused ? 1 : StoryField.easeOut(min(max((t - tap) / 0.9, 0), 1))
        } else {
            tapped = 0
        }
        return max(scrolled, tapped) * window
    }

    private func drawConsequence(_ ctx: inout GraphicsContext, size: CGSize,
                                 t: TimeInterval, beat: Double, ripple: Double) {
        // The one shared chip, glowing centre-stage as the drift stills — fully
        // present when the consequence page (index 2) rests, because the copy
        // there tells the user to tap it.
        let appear = StoryField.smoothstep(beat, 1.60, 1.95)
            * (1 - StoryField.smoothstep(beat, 2.30, 2.90))
        guard appear > 0.01 else { return }

        let chip = StoryField.Sample(position: StoryField.sharedChip,
                                     opacity: appear, scale: 1.15)
        let pulse = StoryField.Sample(position: StoryField.sharedChip,
                                      opacity: appear * (0.7 + 0.3 * sin(t * 2.2)),
                                      scale: 1.2)
        stamp(&ctx, symbol: .glow, at: pulse, in: size, baseSize: 96)
        stamp(&ctx, symbol: .chat, at: chip, in: size, baseSize: 48)

        guard ripple > 0.01 else { return }
        let center = CGPoint(x: StoryField.sharedChip.x * size.width,
                             y: StoryField.sharedChip.y * size.height)
        let reach = 0.34 * min(size.width, size.height)

        // Concentric rings expanding with the ripple — the send radiating out.
        for ring in 1...4 {
            let radius = ripple * reach * Double(ring) / 4
            let fade = (1 - ripple) * 0.5 * appear
            guard radius > 1, fade > 0.01 else { continue }
            let rect = CGRect(x: center.x - radius, y: center.y - radius,
                              width: radius * 2, height: radius * 2)
            ctx.stroke(Path(ellipseIn: rect),
                       with: .color(StoryPalette.warning.opacity(fade)), lineWidth: 1.5)
        }

        // Ghost copies stamping in as the ripple crosses them — the reused
        // password surfacing everywhere at once, each with a small pop.
        for clone in 0..<10 {
            let angle = StoryField.unitRandom(clone, salt: 0x10) * .pi * 2
            let distance = 0.10 + 0.22 * StoryField.unitRandom(clone, salt: 0x11)
            let arrival = distance / 0.32
            let reveal = StoryField.smoothstep(ripple, arrival, arrival + 0.25)
            guard reveal > 0.01 else { continue }
            let sample = StoryField.Sample(
                position: CGPoint(x: StoryField.sharedChip.x + distance * cos(angle),
                                  y: StoryField.sharedChip.y + distance * sin(angle) * 0.9),
                opacity: reveal * appear * (0.4 + 0.4 * (1 - arrival)),
                scale: 0.6 + 0.25 * reveal)
            stamp(&ctx, symbol: .chatWarning, at: sample, in: size, baseSize: 44)
        }
    }

    /// Amber unease pooling under the consequence beat, gone with the turn
    /// (the ripple itself is already windowed to the beat).
    private func drawWarningPool(_ ctx: inout GraphicsContext, size: CGSize,
                                 ripple: Double, veilFade: Double) {
        let strength = 0.28 * ripple * veilFade
        guard strength > 0.01 else { return }
        pool(&ctx, size: size, center: StoryField.sharedChip, radius: 0.55,
             color: StoryPalette.warning, opacity: strength)
    }

    private enum StageSymbol: Int, Hashable {
        case note, chat, browser, key, chatWarning, dot, glow, mark

        init(scrap: StoryField.ScrapKind) {
            switch scrap {
            case .note: self = .note
            case .chat: self = .chat
            case .browser: self = .browser
            case .key: self = .key
            }
        }
    }

    private func stamp(_ ctx: inout GraphicsContext, symbol: StageSymbol,
                       at sample: StoryField.Sample, in size: CGSize, baseSize: CGFloat) {
        guard let resolved = ctx.resolveSymbol(id: symbol) else { return }
        var layer = ctx
        layer.opacity = sample.opacity
        let side = baseSize * sample.scale
        // Centre on the drawn HEIGHT, not the width: the scrap cards are 44x34
        // (52x34 wide), so backing the origin off by half the width floated
        // every one of them ~5pt above its sampled position.
        let height = side * resolved.size.height / max(resolved.size.width, 1)
        let cx = sample.position.x * size.width
        let cy = sample.position.y * size.height
        if sample.rotation != 0 {
            layer.translateBy(x: cx, y: cy)
            layer.rotate(by: Angle(radians: sample.rotation))
            layer.draw(resolved, in: CGRect(x: -side / 2, y: -height / 2,
                                            width: side, height: height))
        } else {
            layer.draw(resolved, in: CGRect(x: cx - side / 2, y: cy - height / 2,
                                            width: side, height: height))
        }
    }

    /// Cold, barely-there nebula behind the dark beats: two soft radial pools,
    /// gone by the time the theme resolves.
    private func drawVeil(_ ctx: inout GraphicsContext, size: CGSize, t: TimeInterval, fade: Double) {
        guard fade > 0.01 else { return }
        let drift = sin(t * 0.05) * 0.03
        pool(&ctx, size: size,
             center: CGPoint(x: 0.30 + drift, y: 0.25), radius: 0.7,
             color: StoryPalette.nebula, opacity: 0.32 * fade)
        pool(&ctx, size: size,
             center: CGPoint(x: 0.78 - drift, y: 0.72), radius: 0.6,
             color: StoryPalette.nebulaDeep, opacity: 0.26 * fade)
    }

    private func pool(_ ctx: inout GraphicsContext, size: CGSize,
                      center: CGPoint, radius: Double, color: Color, opacity: Double) {
        let c = CGPoint(x: center.x * size.width, y: center.y * size.height)
        let r = radius * min(size.width, size.height)
        let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: rect),
                 with: .radialGradient(Gradient(colors: [color.opacity(opacity), .clear]),
                                       center: c, startRadius: 0, endRadius: r))
    }
}

/// One drifting password scrap: a small dark card with a template Polaris glyph.
/// Fixed decorative colors on the committed-dark canvas (StoryPalette), never
/// theme roles — by design the scraps belong to the "before" world. `mix`
/// crossfades every layer toward the user's theme as the canvas resolves; the
/// theme layers must stay at ZERO strength while the canvas is dark (a light
/// theme's opaque control color painted under the dark-world fill turned the
/// whole swarm into glaring bright chips on black).
private struct StoryScrapCard: View {
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
