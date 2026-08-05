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
        Canvas { ctx, size in
            drawVeil(&ctx, size: size, t: t, fade: veilFade)

            let dot = StoryField.originDot(t: t, beat: beat)
            if dot.opacity > 0.01 {
                stamp(&ctx, symbol: StageSymbol.glow, at: dot, in: size, baseSize: 88)
                stamp(&ctx, symbol: StageSymbol.dot, at: dot, in: size, baseSize: 10)
            }

            for index in 0..<StoryField.scrapCount {
                let sample = StoryField.sample(index: index, t: t, beat: beat)
                guard sample.opacity > 0.01 else { continue }
                let symbol = StageSymbol(scrap: StoryField.kind(index))
                stamp(&ctx, symbol: symbol, at: sample, in: size, baseSize: 44)
            }
        } symbols: {
            // Rendered ONCE per Canvas pass and stamped per scrap — the glow is
            // pre-blurred here so no per-particle blur filter ever runs.
            StoryScrapCard(icon: "dt_note_sticky").tag(StageSymbol.note)
            StoryScrapCard(icon: "dt_message").tag(StageSymbol.chat)
            StoryScrapCard(icon: "dt_globe", wide: true).tag(StageSymbol.browser)
            StoryScrapCard(icon: "dt_key").tag(StageSymbol.key)
            Circle().fill(StoryPalette.textPrimary).frame(width: 10, height: 10)
                .tag(StageSymbol.dot)
            Circle().fill(StoryPalette.glow).frame(width: 88, height: 88).blur(radius: 18)
                .tag(StageSymbol.glow)
        }
    }

    private enum StageSymbol: Int, Hashable {
        case note, chat, browser, key, dot, glow

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

    var body: some View {
        VaultIcon(icon, size: 16)
            .foregroundStyle(StoryPalette.textSecondary)
            .frame(width: wide ? 52 : 44, height: 34)
            .background(StoryPalette.scrapFill)
            .vaultCornerRadius(Radius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(StoryPalette.scrapStroke, lineWidth: 1))
    }
}
