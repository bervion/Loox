import SwiftUI

/// Deep-space backdrop math for the story stage: a seeded star field with three
/// depth layers, a few flare stars, drifting nebula clouds and scheduled
/// meteors. Pure functions of (index, wall-clock time, beat) in the
/// `StoryField` house style — no per-frame state anywhere, so scrubbing the
/// scroll backwards replays the same sky.
///
/// The falloff curves here are the reason the backdrop stopped reading as a
/// "sun": a two-stop radial gradient interpolates linearly and prints a visible
/// disc edge, so every pool below is stacked from eased stops that die well
/// inside their own radius.
nonisolated enum StoryGalaxy {

    static let starCount = 170
    /// Brighter stars that earn a small cross flare.
    static let flareStarCount = 7
    static let meteorCount = 3
    /// Opacity buckets the star field is quantised into, so the whole sky costs
    /// that many path fills per frame instead of one per star.
    static let brightnessBuckets = 6

    // MARK: Colors (fixed decorative, committed-dark canvas only)

    static let spaceTop = Color(red: 0.035, green: 0.047, blue: 0.098)
    static let spaceBottom = Color(red: 0.008, green: 0.010, blue: 0.031)
    static let starInk = Color(red: 0.86, green: 0.91, blue: 1.0)
    static let meteorInk = Color(red: 0.78, green: 0.87, blue: 1.0)

    /// The clouds the stage floats in. Deliberately off-centre and of different
    /// sizes: two symmetric pools read as lighting, a scatter reads as depth.
    struct Cloud {
        var center: CGPoint
        var radius: Double
        var color: Color
        var opacity: Double
        /// Radians per second of the slow parallax wander.
        var driftRate: Double
        var driftPhase: Double
        /// How far the cloud slides against the scroll (unit space per beat).
        var parallax: Double
    }

    static let clouds: [Cloud] = [
        Cloud(center: CGPoint(x: 0.26, y: 0.20), radius: 0.86,
              color: Color(red: 0.24, green: 0.38, blue: 0.78), opacity: 0.42,
              driftRate: 0.035, driftPhase: 0, parallax: 0.014),
        Cloud(center: CGPoint(x: 0.82, y: 0.66), radius: 0.72,
              color: Color(red: 0.34, green: 0.20, blue: 0.62), opacity: 0.34,
              driftRate: 0.028, driftPhase: 2.2, parallax: 0.022),
        Cloud(center: CGPoint(x: 0.52, y: 1.02), radius: 0.60,
              color: Color(red: 0.10, green: 0.42, blue: 0.66), opacity: 0.26,
              driftRate: 0.041, driftPhase: 4.1, parallax: 0.030),
    ]

    /// A cloud's live centre: a slow Lissajous wander plus scroll parallax, so
    /// the sky has its own depth against the swarm in front of it.
    static func cloudCenter(_ cloud: Cloud, t: TimeInterval, beat: Double) -> CGPoint {
        CGPoint(x: cloud.center.x + 0.035 * sin(t * cloud.driftRate + cloud.driftPhase),
                y: cloud.center.y + 0.022 * cos(t * cloud.driftRate * 0.8 + cloud.driftPhase)
                    - beat * cloud.parallax)
    }

    /// Eased stops for one soft pool. Seven stops on an inverse-square-ish
    /// curve reaching zero at 0.88 of the radius: the gradient is fully clear
    /// before its own bounds, which is what removes the disc edge.
    static func softGradient(_ color: Color, peak: Double) -> Gradient {
        Gradient(stops: [
            .init(color: color.opacity(peak), location: 0),
            .init(color: color.opacity(peak * 0.70), location: 0.14),
            .init(color: color.opacity(peak * 0.42), location: 0.29),
            .init(color: color.opacity(peak * 0.21), location: 0.46),
            .init(color: color.opacity(peak * 0.08), location: 0.64),
            .init(color: color.opacity(peak * 0.02), location: 0.80),
            .init(color: color.opacity(0), location: 0.88),
            .init(color: color.opacity(0), location: 1),
        ])
    }

    // MARK: Stars

    struct Star {
        var position: CGPoint
        var radius: CGFloat
        var brightness: Double
    }

    /// 0 = furthest. Near layers are bigger, brighter, and slide further
    /// against the scroll — the parallax IS the depth.
    static func depth(_ index: Int) -> Int { index % 3 }

    private static let layerBrightness = [0.30, 0.52, 0.80]
    private static let layerRadius: [CGFloat] = [0.7, 1.05, 1.5]
    private static let layerParallax = [0.006, 0.013, 0.024]

    static func star(index: Int, t: TimeInterval, beat: Double) -> Star {
        let layer = depth(index)
        // Seeded outside 0…1 on the vertical axis so the band the parallax
        // uncovers is already populated — a star must never pop into being.
        let x = StoryField.unitRandom(index, salt: 0x21)
        let y = -0.06 + 1.22 * StoryField.unitRandom(index, salt: 0x22)
        let phase = StoryField.unitRandom(index, salt: 0x23) * .pi * 2
        let speed = 0.5 + 1.5 * StoryField.unitRandom(index, salt: 0x24)
        // Squared sine: mostly dim with brief sparkles, rather than the whole
        // sky pulsing in unison.
        let twinkle = 0.40 + 0.60 * pow(0.5 + 0.5 * sin(t * speed + phase), 2)
        let jitter = 0.85 + 0.30 * StoryField.unitRandom(index, salt: 0x25)
        return Star(position: CGPoint(x: x, y: y - beat * layerParallax[layer]),
                    radius: layerRadius[layer] * jitter,
                    brightness: layerBrightness[layer] * twinkle)
    }

    /// The handful of near stars that carry a cross flare. Kept on the far
    /// plane on purpose: a flare that slides with the scroll reads as a lamp,
    /// one that holds still reads as distance.
    static func flareStar(index: Int, t: TimeInterval, beat: Double) -> Star {
        let x = 0.06 + 0.88 * StoryField.unitRandom(index, salt: 0x31)
        let y = 0.02 + 0.92 * StoryField.unitRandom(index, salt: 0x32)
        let phase = StoryField.unitRandom(index, salt: 0x33) * .pi * 2
        let breathe = 0.55 + 0.45 * pow(0.5 + 0.5 * sin(t * 0.55 + phase), 2)
        let size = 5.0 + 6.0 * StoryField.unitRandom(index, salt: 0x34)
        return Star(position: CGPoint(x: x, y: y - beat * 0.004),
                    radius: size, brightness: breathe)
    }

    // MARK: Meteors

    /// One meteor's live streak, or nil while its lane is resting. Each lane
    /// has its own period and offset, so they never fire in step.
    struct Meteor {
        var head: CGPoint
        var tail: CGPoint
        var brightness: Double
    }

    /// Seconds a streak is in flight. Short: a shooting star that lingers
    /// reads as a comet, and the story is not about the sky.
    private static let meteorFlight: TimeInterval = 1.15

    static func meteor(index: Int, t: TimeInterval) -> Meteor? {
        let cycle = 8.0 + 5.0 * StoryField.unitRandom(index, salt: 0x41)
        let offset = StoryField.unitRandom(index, salt: 0x42) * cycle
        let local = (t + offset).truncatingRemainder(dividingBy: cycle)
        guard local < meteorFlight else { return nil }

        let progress = local / meteorFlight
        let origin = CGPoint(x: -0.15 + 0.85 * StoryField.unitRandom(index, salt: 0x43),
                             y: -0.10 + 0.55 * StoryField.unitRandom(index, salt: 0x44))
        // Shallow down-right fall, varied per lane.
        let angle = 0.42 + 0.30 * StoryField.unitRandom(index, salt: 0x45)
        let travel = 0.75 + 0.45 * StoryField.unitRandom(index, salt: 0x46)
        let flown = StoryField.easeOut(progress) * travel
        let head = CGPoint(x: origin.x + flown * cos(angle),
                           y: origin.y + flown * sin(angle))
        // The tail grows in, then is swallowed as the head fades.
        let length = 0.16 * sin(progress * .pi)
        let tail = CGPoint(x: head.x - length * cos(angle),
                           y: head.y - length * sin(angle))
        return Meteor(head: head, tail: tail, brightness: sin(progress * .pi))
    }
}
