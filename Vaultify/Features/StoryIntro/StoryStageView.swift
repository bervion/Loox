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

    private var paused: Bool { reduceMotion || scenePhase != .active }
    /// Beat-4 relief: the fixed-dark canvas cross-fades into the user's own
    /// theme background as the scraps converge — "light returns" IS the
    /// sanctuary (owner decision, concept-final §1).
    private var themeMix: Double { StoryField.smoothstep(model.beatPosition, 2.9, 4.0) }

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
            drawVeil(&ctx, size: size, t: t, fade: veilFade)
            drawWarningPool(&ctx, size: size, ripple: ripple, beat: beat, veilFade: veilFade)

            let dot = StoryField.originDot(t: t, beat: beat)
            if dot.opacity > 0.01 {
                stamp(&ctx, symbol: StageSymbol.glow, at: dot, in: size, baseSize: 88)
                stamp(&ctx, symbol: StageSymbol.dot, at: dot, in: size, baseSize: 10)
            }

            for index in 0..<StoryField.scrapCount {
                let sample = StoryField.sample(index: index, t: t, beat: beat, burst: burst)
                guard sample.opacity > 0.01 else { continue }
                let symbol = StageSymbol(scrap: StoryField.kind(index))
                stamp(&ctx, symbol: symbol, at: sample, in: size, baseSize: 44)
            }

            drawConsequence(&ctx, size: size, t: t, beat: beat, ripple: ripple)
            drawSanctuary(&ctx, size: size, t: t, beat: beat, burst: burst)
        } symbols: {
            // Rendered ONCE per Canvas pass and stamped per scrap — the glow is
            // pre-blurred here so no per-particle blur filter ever runs.
            StoryScrapCard(icon: "dt_note_sticky").tag(StageSymbol.note)
            StoryScrapCard(icon: "dt_message").tag(StageSymbol.chat)
            StoryScrapCard(icon: "dt_globe", wide: true).tag(StageSymbol.browser)
            StoryScrapCard(icon: "dt_key").tag(StageSymbol.key)
            StoryScrapCard(icon: "dt_message", tint: StoryPalette.warning)
                .tag(StageSymbol.chatWarning)
            Circle().fill(StoryPalette.textPrimary).frame(width: 10, height: 10)
                .tag(StageSymbol.dot)
            Circle().fill(StoryPalette.glow).frame(width: 88, height: 88).blur(radius: 18)
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

    // MARK: Sanctuary (the mark and its sigils)

    /// The Loox mark settles at the ring's centre as the theme resolves;
    /// concentric sigil arcs draw themselves around the orbit.
    private func drawSanctuary(_ ctx: inout GraphicsContext, size: CGSize,
                               t: TimeInterval, beat: Double, burst: Double) {
        let appear = StoryField.smoothstep(beat, 3.75, 4.25) * (1 - burst)
        guard appear > 0.01 else { return }

        let breathe = 1 + 0.02 * sin(t * (.pi * 2 / 4))
        let mark = StoryField.Sample(position: StoryField.origin,
                                     opacity: appear, scale: breathe)
        stamp(&ctx, symbol: .glow, at: mark, in: size, baseSize: 120)
        stamp(&ctx, symbol: .mark, at: mark, in: size, baseSize: 56)

        // Sigil arcs: accent-tinted, trim-drawn, counter-rotating slowly.
        let trim = StoryField.smoothstep(beat, 4.15, 4.85)
        guard trim > 0.01 else { return }
        let center = CGPoint(x: StoryField.origin.x * size.width,
                             y: StoryField.origin.y * size.height)
        let accent = Color(rgb: theme.accentFill)
        for (index, factor) in [1.34, 1.52].enumerated() {
            let radius = 0.24 * factor * min(size.width, size.height) * (1 + burst * 0.6)
            let direction: Double = index == 0 ? 1 : -1
            let start = Angle(radians: t * 0.10 * direction + Double(index) * 2.1)
            var path = Path()
            path.addArc(center: center, radius: radius,
                        startAngle: start,
                        endAngle: start + Angle(radians: trim * 4.4),
                        clockwise: false)
            ctx.stroke(path,
                       with: .color(accent.opacity(0.35 * appear * trim)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
    }

    // MARK: Consequence beat (the shared password ripples out)

    /// The send ripple: the user's tap drives it hard (a 0.9s one-shot that
    /// then holds — sent is sent), and scrolling deeper into the beat plays a
    /// softer version for non-tappers. Reeling into the turn drains it away.
    private func rippleProgress(t: TimeInterval, beat: Double) -> Double {
        let scrolled = StoryField.smoothstep(beat, 2.45, 2.95) * 0.7
        let tapped: Double
        if let tap = model.sendTapTime {
            tapped = StoryField.easeOut(min(max((t - tap) / 0.9, 0), 1))
        } else {
            tapped = 0
        }
        return max(scrolled, tapped) * (1 - StoryField.smoothstep(beat, 3.0, 3.6))
    }

    private func drawConsequence(_ ctx: inout GraphicsContext, size: CGSize,
                                 t: TimeInterval, beat: Double, ripple: Double) {
        // The one shared chip, glowing centre-stage as the drift stills.
        let appear = StoryField.smoothstep(beat, 2.05, 2.35)
            * (1 - StoryField.smoothstep(beat, 3.0, 3.5))
        guard appear > 0.01 else { return }

        let chip = StoryField.Sample(position: StoryField.sharedChip,
                                     opacity: appear, scale: 1.15)
        let pulse = StoryField.Sample(position: StoryField.sharedChip,
                                      opacity: appear * (0.7 + 0.3 * sin(t * 2.2)),
                                      scale: 1)
        stamp(&ctx, symbol: .glow, at: pulse, in: size, baseSize: 96)
        stamp(&ctx, symbol: .chat, at: chip, in: size, baseSize: 48)

        guard ripple > 0.01 else { return }
        let center = CGPoint(x: StoryField.sharedChip.x * size.width,
                             y: StoryField.sharedChip.y * size.height)
        let reach = 0.34 * min(size.width, size.height)

        // Three concentric rings expanding with the ripple.
        for ring in 1...3 {
            let radius = ripple * reach * Double(ring) / 3
            let fade = (1 - ripple) * 0.45 * appear
            guard radius > 1, fade > 0.01 else { continue }
            let rect = CGRect(x: center.x - radius, y: center.y - radius,
                              width: radius * 2, height: radius * 2)
            ctx.stroke(Path(ellipseIn: rect),
                       with: .color(StoryPalette.warning.opacity(fade)), lineWidth: 1)
        }

        // Ghost copies stamping in as the ripple crosses them — the reused
        // password surfacing everywhere at once.
        for clone in 0..<10 {
            let angle = StoryField.unitRandom(clone, salt: 0x10) * .pi * 2
            let distance = 0.10 + 0.22 * StoryField.unitRandom(clone, salt: 0x11)
            let arrival = distance / 0.32
            let reveal = StoryField.smoothstep(ripple, arrival, arrival + 0.25)
            guard reveal > 0.01 else { continue }
            let sample = StoryField.Sample(
                position: CGPoint(x: StoryField.sharedChip.x + distance * cos(angle),
                                  y: StoryField.sharedChip.y + distance * sin(angle) * 0.9),
                opacity: reveal * appear * (0.35 + 0.4 * (1 - arrival)),
                scale: 0.8)
            stamp(&ctx, symbol: .chatWarning, at: sample, in: size, baseSize: 44)
        }
    }

    /// Amber unease pooling under the consequence beat, gone with the turn.
    private func drawWarningPool(_ ctx: inout GraphicsContext, size: CGSize,
                                 ripple: Double, beat: Double, veilFade: Double) {
        let strength = 0.20 * ripple * veilFade
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
        let rect = CGRect(x: sample.position.x * size.width - side / 2,
                          y: sample.position.y * size.height - side / 2,
                          width: side, height: side * resolved.size.height / max(resolved.size.width, 1))
        layer.draw(resolved, in: rect)
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
/// theme roles — by design the scraps belong to the "before" world.
private struct StoryScrapCard: View {
    let icon: String
    var wide = false
    /// Warning-tinted variant for the consequence beat's ghost copies.
    var tint: Color?

    var body: some View {
        VaultIcon(icon, size: 16)
            .foregroundStyle(tint ?? StoryPalette.textSecondary)
            .frame(width: wide ? 52 : 44, height: 34)
            .background(StoryPalette.scrapFill)
            .vaultCornerRadius(Radius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(tint?.opacity(0.4) ?? StoryPalette.scrapStroke, lineWidth: 1))
    }
}
