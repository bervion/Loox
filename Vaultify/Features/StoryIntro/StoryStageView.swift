import SwiftUI

/// The pinned full-bleed stage behind the story's scroll column: the galaxy
/// backdrop, the origin dot, and the scrap swarm that becomes the brand's
/// bubble cluster — all sampled from `StoryField` / `StoryOrbitLattice` pure
/// functions each Canvas tick, driven by one scalar from the scroll model.
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
            // One timeline drives BOTH canvases, so the sky and the swarm can
            // never disagree about the frame. No `minimumInterval`: the brand
            // animation runs at the display's own cadence and the story is the
            // same picture, so it gets ProMotion's 120Hz too.
            TimelineView(.animation(paused: paused)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let beat = model.beatPosition
                ZStack {
                    StoryGalaxyCanvas(t: t, beat: beat, fade: 1 - themeMix,
                                      parallax: !reduceMotion, live: !paused)
                    canvas(t: t, beat: beat, veilFade: 1 - themeMix)
                }
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
            // Every symbol resolved ONCE per pass. Resolving inside the
            // particle loop meant ~120 lookups a frame for 13 distinct images.
            var symbols: [StageSymbol: GraphicsContext.ResolvedSymbol] = [:]
            for symbol in StageSymbol.allCases {
                symbols[symbol] = ctx.resolveSymbol(id: symbol)
            }

            // Orbit geometry lands as TRUE circles: unit-space offsets are
            // rescaled so the ring's point radius comes off the short side
            // (unit space alone would stretch it into a tall ellipse that
            // never nests inside the sigil arcs). The height cap keeps the
            // cluster clear of the copy column on squat canvases (iPad
            // landscape), where the short side is no longer the tight axis.
            let reach = StoryOrbitLattice.reach(size)
            let ringScale = CGSize(
                width: reach / (StoryField.ringRadius * max(size.width, 1)),
                height: reach / (StoryField.ringRadius * max(size.height, 1)))

            StoryStageLight.warningPool(&ctx, size: size, ripple: ripple, veilFade: veilFade)

            let dot = StoryField.originDot(t: t, beat: beat)
            if dot.opacity > 0.01 {
                // The hook's light source: a falloff plus lens streaks, so it
                // reads as a flare in deep space rather than a disc pasted on.
                let center = CGPoint(x: StoryField.origin.x * size.width,
                                     y: StoryField.origin.y * size.height)
                StoryStageLight.flare(&ctx, size: size, center: center,
                                      strength: dot.opacity * veilFade)
                StoryStageLight.bloom(&ctx, center: center, radius: 46 * dot.scale,
                                      color: StoryPalette.glow, opacity: dot.opacity)
                stamp(&ctx, symbols[.dot], at: dot, in: size, baseSize: 10)
            }

            drawSwarm(&ctx, symbols: symbols, size: size, t: t, beat: beat,
                      burst: burst, ringScale: ringScale, reach: reach)
            drawMotes(&ctx, symbols: symbols, size: size, t: t, beat: beat,
                      burst: burst, ringScale: ringScale, reach: reach)
            drawConsequence(&ctx, symbols: symbols, size: size, t: t, beat: beat,
                            ripple: ripple, veilFade: veilFade)
            drawSanctuary(&ctx, symbols: symbols, size: size, t: t, beat: beat,
                          burst: burst)
        } symbols: {
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
            // Glows are NOT symbols: the seal blooms the sanctuary halo to
            // ~2.7x, and a raster resolved big enough to survive that would be
            // re-rendered every frame for one draw. `bloom` draws gradients
            // straight into the context instead — resolution independent, and
            // free of the raster entirely.
            //
            // The mark is resolved above the largest `markDiameter` any
            // supported canvas produces, so it is only ever scaled down.
            Image("BrandSymbol").resizable().scaledToFit()
                .frame(width: 96, height: 96)
                .tag(StageSymbol.mark)
            ForEach(0..<StageSymbol.bubbleCount, id: \.self) { lobe in
                StoryBubbleOrb(lobe: lobe).tag(StageSymbol.bubble(lobe))
            }
        }
    }

    // MARK: The swarm and its cluster

    /// Every scrap, drawn as a card crossfading into its brand bubble. Both
    /// layers are stamped while `bubbleMix` is mid-flight; at either end one of
    /// them costs nothing because its opacity gate rejects it.
    private func drawSwarm(_ ctx: inout GraphicsContext,
                           symbols: [StageSymbol: GraphicsContext.ResolvedSymbol],
                           size: CGSize, t: TimeInterval, beat: Double,
                           burst: Double, ringScale: CGSize, reach: CGFloat) {
        for index in 0..<StoryField.scrapCount {
            let sample = StoryField.sample(index: index, t: t, beat: beat,
                                           burst: burst, ringScale: ringScale,
                                           reach: reach)
            guard sample.opacity > 0.01 else { continue }

            if sample.bubbleMix < 0.99 {
                var card = sample
                card.opacity = sample.opacity * (1 - sample.bubbleMix)
                let kind = StoryField.kind(index)
                // The browser card is drawn 52pt wide; stamping every kind at
                // 44 squashed it to 44x28.8 instead — the same width as its
                // siblings and shorter, which is the opposite of a pill.
                stamp(&ctx, symbols[StageSymbol(scrap: kind)], at: card, in: size,
                      baseSize: kind == .browser ? 52 : 44)
            }
            if sample.bubbleMix > 0.01 {
                var orb = sample
                orb.opacity = sample.opacity * sample.bubbleMix
                orb.scale = sample.bubbleScale
                orb.rotation = 0
                stamp(&ctx, symbols[StageSymbol.lobe(index)], at: orb, in: size,
                      baseSize: StoryOrbitLattice.bubbleBase)
            }
        }
    }

    /// The ambient motes drifting around the cluster — many, small, and quiet.
    private func drawMotes(_ ctx: inout GraphicsContext,
                           symbols: [StageSymbol: GraphicsContext.ResolvedSymbol],
                           size: CGSize, t: TimeInterval, beat: Double,
                           burst: Double, ringScale: CGSize, reach: CGFloat) {
        for index in 0..<StoryOrbitLattice.ambientCount {
            guard let mote = StoryOrbitLattice.mote(index: index, t: t, beat: beat,
                                                    burst: burst, scale: ringScale,
                                                    reach: reach),
                  mote.opacity > 0.01 else { continue }
            stamp(&ctx, symbols[StageSymbol.lobe(index)], at: mote, in: size,
                  baseSize: StoryOrbitLattice.bubbleBase)
        }
    }

    /// Seal exit: 0…1 over 0.8s after the hold completes, easing the cluster
    /// outward while the route crossfade lands on Home behind it.
    private func burstProgress(t: TimeInterval) -> Double {
        guard let seal = model.sealTime else { return 0 }
        return StoryField.easeOut(min(max((t - seal) / 0.8, 0), 1))
    }

    // MARK: Sanctuary (the mark and its sigils)

    /// The Loox mark settles at the cluster's centre as the theme resolves;
    /// concentric sigil arcs draw themselves around the orbits.
    private func drawSanctuary(_ ctx: inout GraphicsContext,
                               symbols: [StageSymbol: GraphicsContext.ResolvedSymbol],
                               size: CGSize, t: TimeInterval, beat: Double, burst: Double) {
        // Assembled by the sanctuary page (index 4), not on the way out of it.
        let appear = StoryField.smoothstep(beat, 3.50, 3.95) * (1 - burst)
        guard appear > 0.01 else { return }

        let breathe = 1 + 0.02 * sin(t * (.pi * 2 / 4))
        // The seal blooms the mark's halo as the cluster flings outward — the
        // vault flaring shut is the story's final frame.
        let flare = 1 + burst * 1.6
        // The mark is sized FROM the cluster and contracts with it, so the
        // inner orbit always has somewhere to be (a constant 56pt sat on top
        // of those bubbles on a small phone).
        let draw = StoryOrbitLattice.tighten(beat)
        let markSide = StoryOrbitLattice.markDiameter(reach: StoryOrbitLattice.reach(size)) * draw
        let mark = StoryField.Sample(position: StoryField.origin,
                                     opacity: appear, scale: breathe)
        let center = CGPoint(x: StoryField.origin.x * size.width,
                             y: StoryField.origin.y * size.height)
        // Accent, not the fixed cool glow: this beat lands AFTER the canvas
        // has resolved into the user's theme, where a cold bloom is invisible
        // on a light background. Matches the sigils drawn just below.
        StoryStageLight.bloom(&ctx, center: center,
                              radius: markSide * 1.3 * breathe * flare,
                              color: Color(rgb: theme.accentFill), opacity: 0.5 * appear)
        stamp(&ctx, symbols[.mark], at: mark, in: size, baseSize: markSide)

        // Sigil arcs: accent-tinted, trim-drawn, counter-rotating slowly. Drawn
        // in as the sanctuary arrives, complete on its resting frame. They sit
        // OUTSIDE the outermost bubble orbit and tighten with it, so the
        // cluster keeps its silhouette while the commitment beat draws it in.
        let trim = StoryField.smoothstep(beat, 3.60, 4.0)
        guard trim > 0.01 else { return }
        let accent = Color(rgb: theme.accentFill)
        let reach = StoryOrbitLattice.reach(size) * draw
        for (index, factor) in StoryOrbitLattice.sigilRadii.enumerated() {
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

    private func drawConsequence(_ ctx: inout GraphicsContext,
                                 symbols: [StageSymbol: GraphicsContext.ResolvedSymbol],
                                 size: CGSize, t: TimeInterval, beat: Double,
                                 ripple: Double, veilFade: Double) {
        // The one shared chip, glowing centre-stage as the drift stills — fully
        // present when the consequence page (index 2) rests, because the copy
        // there tells the user to tap it.
        let appear = StoryField.smoothstep(beat, 1.60, 1.95)
            * (1 - StoryField.smoothstep(beat, 2.30, 2.90))
        guard appear > 0.01 else { return }

        let chip = StoryField.Sample(position: StoryField.sharedChip,
                                     opacity: appear, scale: 1.15)
        let center = CGPoint(x: StoryField.sharedChip.x * size.width,
                             y: StoryField.sharedChip.y * size.height)
        StoryStageLight.flare(&ctx, size: size, center: center,
                              strength: 0.5 * appear * veilFade,
                              color: StoryPalette.warning)
        StoryStageLight.bloom(&ctx, center: center, radius: 72,
                              color: StoryPalette.warning.opacity(0.5),
                              opacity: appear * (0.7 + 0.3 * sin(t * 2.2)))
        stamp(&ctx, symbols[.chat], at: chip, in: size, baseSize: 48)

        guard ripple > 0.01 else { return }
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
            stamp(&ctx, symbols[.chatWarning], at: sample, in: size, baseSize: 44)
        }
    }

    // MARK: Symbols

    enum StageSymbol: Hashable, CaseIterable {
        case note, chat, browser, key, chatWarning, dot, mark
        /// One per lobe of the brand mark's six-circle gradient set.
        case bubble(Int)

        static let bubbleCount = 6

        static var allCases: [StageSymbol] {
            [.note, .chat, .browser, .key, .chatWarning, .dot, .mark]
                + (0..<bubbleCount).map { StageSymbol.bubble($0) }
        }

        /// Any particle index maps onto one of the six lobes, so callers can
        /// pass a raw index and still land on a symbol that was resolved.
        static func lobe(_ index: Int) -> StageSymbol {
            .bubble(((index % bubbleCount) + bubbleCount) % bubbleCount)
        }

        init(scrap: StoryField.ScrapKind) {
            switch scrap {
            case .note: self = .note
            case .chat: self = .chat
            case .browser: self = .browser
            case .key: self = .key
            }
        }
    }

    private func stamp(_ ctx: inout GraphicsContext,
                       _ resolved: GraphicsContext.ResolvedSymbol?,
                       at sample: StoryField.Sample, in size: CGSize, baseSize: CGFloat) {
        guard let resolved, sample.opacity > 0.005 else { return }
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
}
