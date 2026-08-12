import SwiftUI

/// The story's sky: graded deep space, drifting nebula clouds, a parallaxing
/// star field, a few flare stars and the odd meteor.
///
/// Pure drawing on a `GraphicsContext`, NOT a view. The stage used to stack a
/// second `Canvas` behind its own, which meant two full-screen layers
/// rasterised and composited every frame for one picture; the stage now calls
/// `draw` first inside its single Canvas instead.
///
/// `fade` is the committed-dark veil's strength (1 while the story is in the
/// dark world, 0 once the canvas has resolved into the user's theme) — the
/// whole sky rides it out, because stars on a light theme would be litter.
enum StorySky {

    /// - Parameters:
    ///   - parallax: Reduce Motion is OFF. Gates the multi-rate scroll
    ///     parallax, which pausing the timeline does NOT stop (it rides `beat`,
    ///     not `t`) and which is the vestibular effect Reduce Motion removes.
    ///   - live: the timeline is running. Gates meteors only: frozen, one
    ///     caught mid-streak hangs in the sky as a scratch. Deliberately
    ///     separate from `parallax` — the app switcher pauses the timeline
    ///     while the screen is still fully visible, and zeroing the parallax
    ///     there would snap the whole sky sideways in front of the user.
    static func draw(_ ctx: inout GraphicsContext, size: CGSize,
                     t: TimeInterval, beat: Double, fade: Double,
                     parallax: Bool, live: Bool) {
        guard fade > 0.01 else { return }
        let drift = parallax ? beat : 0
        drawSpace(&ctx, size: size, fade: fade)
        for cloud in StoryGalaxy.clouds {
            draw(cloud, &ctx, size: size, t: t, drift: drift, fade: fade)
        }
        drawStars(&ctx, size: size, t: t, drift: drift, fade: fade)
        drawFlareStars(&ctx, size: size, t: t, drift: drift, fade: fade)
        if live { drawMeteors(&ctx, size: size, t: t, fade: fade) }
    }

    /// Graded void rather than flat black: a top-lit navy that falls to near
    /// black gives the sky somewhere to be, so the clouds read as inside it.
    private static func drawSpace(_ ctx: inout GraphicsContext, size: CGSize,
                                  fade: Double) {
        let rect = CGRect(origin: .zero, size: size)
        ctx.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [StoryGalaxy.spaceTop.opacity(fade),
                              StoryGalaxy.spaceBottom.opacity(fade)]),
            startPoint: CGPoint(x: size.width * 0.3, y: 0),
            endPoint: CGPoint(x: size.width * 0.7, y: size.height)))
    }

    /// One nebula pool. Drawn into an anisotropically scaled layer so the cloud
    /// is an ellipse, never a disc — a circular pool is exactly what read as a
    /// sun sitting behind the copy.
    private static func draw(_ cloud: StoryGalaxy.Cloud, _ ctx: inout GraphicsContext,
                             size: CGSize, t: TimeInterval, drift: Double, fade: Double) {
        let unit = StoryGalaxy.cloudCenter(cloud, t: t, beat: drift)
        let center = CGPoint(x: unit.x * size.width, y: unit.y * size.height)
        // Off the SHORT side: a full-screen-diagonal pool is mostly overdraw,
        // and three of those every frame is the one thing here that could cost
        // a phone its frame budget.
        let radius = cloud.radius * min(size.width, size.height)
        let squash = 0.72 + 0.10 * sin(t * cloud.driftRate * 1.7 + cloud.driftPhase)

        var layer = ctx
        layer.translateBy(x: center.x, y: center.y)
        layer.scaleBy(x: 1, y: squash)
        let rect = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
        layer.fill(Path(ellipseIn: rect), with: .radialGradient(
            StoryGalaxy.softGradient(cloud.color, peak: cloud.opacity * fade),
            center: .zero, startRadius: 0, endRadius: radius))
    }

    /// The star field as `brightnessBuckets` accumulated paths: one fill per
    /// bucket instead of one per star, so 170 twinkling stars cost six draws.
    private static func drawStars(_ ctx: inout GraphicsContext, size: CGSize,
                                  t: TimeInterval, drift: Double, fade: Double) {
        var buckets = [Path](repeating: Path(), count: StoryGalaxy.brightnessBuckets)
        for index in 0..<StoryGalaxy.starCount {
            let star = StoryGalaxy.star(index: index, t: t, beat: drift)
            guard star.position.y > -0.05, star.position.y < 1.05 else { continue }
            let bucket = min(Int(star.brightness * Double(StoryGalaxy.brightnessBuckets)),
                             StoryGalaxy.brightnessBuckets - 1)
            let x = star.position.x * size.width
            let y = star.position.y * size.height
            buckets[bucket].addEllipse(in: CGRect(x: x - star.radius, y: y - star.radius,
                                                  width: star.radius * 2,
                                                  height: star.radius * 2))
        }
        for (bucket, path) in buckets.enumerated() where !path.isEmpty {
            let level = (Double(bucket) + 0.5) / Double(StoryGalaxy.brightnessBuckets)
            ctx.fill(path, with: .color(StoryGalaxy.starInk.opacity(level * fade)))
        }
    }

    /// Distant bright stars: a soft halo plus a four-point cross. The cross is
    /// two thin strokes, not a symbol — at this size a resolved image would
    /// cost more than the geometry.
    private static func drawFlareStars(_ ctx: inout GraphicsContext, size: CGSize,
                                       t: TimeInterval, drift: Double, fade: Double) {
        for index in 0..<StoryGalaxy.flareStarCount {
            let star = StoryGalaxy.flareStar(index: index, t: t, beat: drift)
            let center = CGPoint(x: star.position.x * size.width,
                                 y: star.position.y * size.height)
            let alpha = star.brightness * fade
            guard alpha > 0.02 else { continue }

            let halo = star.radius * 2.6
            let haloRect = CGRect(x: center.x - halo, y: center.y - halo,
                                  width: halo * 2, height: halo * 2)
            ctx.fill(Path(ellipseIn: haloRect), with: .radialGradient(
                StoryGalaxy.softGradient(StoryGalaxy.starInk, peak: 0.32 * alpha),
                center: center, startRadius: 0, endRadius: halo))

            var spikes = Path()
            spikes.move(to: CGPoint(x: center.x - star.radius, y: center.y))
            spikes.addLine(to: CGPoint(x: center.x + star.radius, y: center.y))
            spikes.move(to: CGPoint(x: center.x, y: center.y - star.radius))
            spikes.addLine(to: CGPoint(x: center.x, y: center.y + star.radius))
            ctx.stroke(spikes, with: .color(StoryGalaxy.starInk.opacity(0.42 * alpha)),
                       style: StrokeStyle(lineWidth: 1, lineCap: .round))

            let core = CGRect(x: center.x - 1.2, y: center.y - 1.2, width: 2.4, height: 2.4)
            ctx.fill(Path(ellipseIn: core), with: .color(StoryGalaxy.starInk.opacity(0.9 * alpha)))
        }
    }

    /// Shooting stars: a tapered streak that brightens toward the head, plus a
    /// small head glow. Rare and quick by design.
    private static func drawMeteors(_ ctx: inout GraphicsContext, size: CGSize,
                                    t: TimeInterval, fade: Double) {
        for index in 0..<StoryGalaxy.meteorCount {
            guard let meteor = StoryGalaxy.meteor(index: index, t: t) else { continue }
            let head = CGPoint(x: meteor.head.x * size.width, y: meteor.head.y * size.height)
            let tail = CGPoint(x: meteor.tail.x * size.width, y: meteor.tail.y * size.height)
            let alpha = meteor.brightness * fade
            guard alpha > 0.02 else { continue }

            var streak = Path()
            streak.move(to: tail)
            streak.addLine(to: head)
            ctx.stroke(streak, with: .linearGradient(
                Gradient(colors: [StoryGalaxy.meteorInk.opacity(0),
                                  StoryGalaxy.meteorInk.opacity(0.75 * alpha)]),
                startPoint: tail, endPoint: head),
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round))

            let glow: CGFloat = 9
            let rect = CGRect(x: head.x - glow, y: head.y - glow,
                              width: glow * 2, height: glow * 2)
            ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
                StoryGalaxy.softGradient(StoryGalaxy.starInk, peak: 0.85 * alpha),
                center: head, startRadius: 0, endRadius: glow))
        }
    }
}

/// The sky as a standalone view, for the reader presentation's static poster.
/// The journey does not use this — its stage draws the sky into its own Canvas.
struct StoryGalaxyCanvas: View {
    var t: TimeInterval = 0
    var beat: Double = 0
    var fade: Double = 1
    var parallax = false
    var live = false

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { ctx, size in
            StorySky.draw(&ctx, size: size, t: t, beat: beat, fade: fade,
                          parallax: parallax, live: live)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
