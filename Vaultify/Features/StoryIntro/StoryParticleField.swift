import SwiftUI

/// The stage's population: seeded password "scraps" (note cards, chat bubbles,
/// browser pills, key dots) whose every visual property is a pure function of
/// (wall-clock time, beat position, per-index seed) — the LooxAnimationEngine
/// house pattern. No per-frame state anywhere: the Canvas samples this field
/// fresh each tick, so scrubbing the scroll backwards replays the story in
/// reverse for free.
nonisolated enum StoryField {

    static let scrapCount = 90
    /// Scraps that survive the convergence and form the sanctuary ring.
    static let ringCount = 24

    enum ScrapKind: Int, CaseIterable {
        case note, chat, browser, key
    }

    /// Where a scrap is and how it looks at this instant, in unit space
    /// (0…1 both axes; the stage view scales to points). `rotation` is a
    /// small card tilt in radians — the mess is never perfectly aligned.
    struct Sample {
        var position: CGPoint
        var opacity: Double
        var scale: Double
        var rotation: Double = 0
    }

    /// The lone glowing dot the story opens on: centre-high, breathing at the
    /// LooxLogoBreathe cadence, handing its light over to the newborn scraps.
    /// Beat windows all COMPLETE on the integer their page rests at
    /// (`beatPosition` is 0…5 and each composed page sits exactly on its
    /// index). A window that ends past the integer leaves the scene half-built
    /// while the user is looking straight at it.
    static func originDot(t: TimeInterval, beat: Double) -> Sample {
        let breathe = 1 + 0.03 * sin(t * (.pi * 2 / 4))
        // Holds through the hook, dissolves as the swarm takes over.
        let fade = 1 - smoothstep(beat, 0.45, 0.95)
        return Sample(position: origin, opacity: fade, scale: breathe)
    }

    static func kind(_ index: Int) -> ScrapKind {
        ScrapKind(rawValue: index % ScrapKind.allCases.count) ?? .note
    }

    /// The full life of one scrap: born from the origin dot across the chaos
    /// beat, drifting until the consequence stills it, reeled into the ring by
    /// the turn's scroll scrub, then orbiting (survivors) or dissolving.
    /// `burst` (0…1) is the seal's exit: the ring flings outward and fades —
    /// the LooxSwirl dismiss verb as the curtain-raise for the real app.
    /// `ringScale` corrects the orbit for the canvas aspect (see `ringPoint`);
    /// the default keeps the field aspect-agnostic for tests and previews.
    static func sample(index: Int, t: TimeInterval, beat: Double, burst: Double = 0,
                       ringScale: CGSize = CGSize(width: 1, height: 1)) -> Sample {
        let birthOrder = unitRandom(index, salt: 0x01)
        // Last scrap is fully born by 0.95, so the chaos page (index 1) rests
        // on a complete swarm rather than one still spawning.
        let birthBeat = 0.20 + birthOrder * 0.50
        let birth = smoothstep(beat, birthBeat, birthBeat + 0.25)
        guard birth > 0 else { return Sample(position: origin, opacity: 0, scale: 1) }

        let scatter = CGPoint(x: 0.10 + 0.80 * unitRandom(index, salt: 0x02),
                              y: 0.08 + 0.76 * unitRandom(index, salt: 0x03))

        // Chaos drift: seeded Lissajous wander, stilled to a tense near-freeze
        // as the consequence beat lands.
        let driftPhase = unitRandom(index, salt: 0x04) * .pi * 2
        let driftSpeed = 0.25 + 0.45 * unitRandom(index, salt: 0x05)
        // Drift is fully stilled by the consequence page (index 2).
        let stillness = 1 - smoothstep(beat, 1.55, 1.95)
        let driftAmp = 0.022 * stillness
        let drifted = CGPoint(
            x: scatter.x + driftAmp * sin(t * driftSpeed + driftPhase),
            y: scatter.y + driftAmp * cos(t * driftSpeed * 0.8 + driftPhase * 1.3))

        // Birth path: out of the origin dot toward the scatter home.
        let placed = lerp(origin, drifted, easeOut(birth))

        // The turn: position becomes a scroll-scrubbed blend toward the ring —
        // reversing the scroll visibly scatters them again.
        // The gather IS the turn: it runs from leaving the consequence page to
        // arriving on the turn page (index 3), so the ring is closed at rest.
        let gather = easeInOut(smoothstep(beat, 2.10, 3.0))
        let slot = index % ringCount
        var position = lerp(placed, ringPoint(slot: slot, t: t, beat: beat, scale: ringScale),
                            gather)

        // Only ring survivors persist into the sanctuary; the surplus is gone
        // before the sanctuary page (index 4) settles.
        let survives = index < ringCount
        let dissolve = survives ? 0 : smoothstep(beat, 3.30, 3.90)

        // Depth: the swarm reads in layers, not as a flat sheet of equal
        // cards. Gathering lifts every survivor to full presence — the ring
        // is one ordered thing, so the sanctuary orbit glows evenly.
        let depth = 0.72 + 0.28 * unitRandom(index, salt: 0x08)
        let presence = depth + (1 - depth) * gather

        // The consequence beat's spotlight: the swarm recedes a step while
        // the one shared chip takes the light — the mistake is singular,
        // the mess is not. Matches the chip's own appear window.
        let spotlight = smoothstep(beat, 1.55, 1.95) * (1 - smoothstep(beat, 2.30, 2.90))
        var opacity = Double(birth) * presence * (1 - dissolve) * (1 - 0.30 * spotlight)

        if burst > 0 {
            let away = CGPoint(x: position.x - origin.x, y: position.y - origin.y)
            position.x += away.x * burst * 1.6
            position.y += away.y * burst * 1.6
            opacity *= 1 - burst
        }

        // A loose scatter of tilts (±8°) with a slow wobble while drifting;
        // the gather straightens every card — order is the turn's whole point.
        let baseTilt = (unitRandom(index, salt: 0x07) - 0.5) * 0.28
        let wobble = 0.05 * stillness * sin(t * driftSpeed * 1.4 + driftPhase)
        let rotation = (baseTilt + wobble) * (1 - gather)

        let scale = 0.75 + 0.5 * unitRandom(index, salt: 0x06)
        return Sample(position: position, opacity: opacity, scale: scale, rotation: rotation)
    }

    /// Sanctuary orbit: polar slots around the mark, drifting slowly with time,
    /// tightening as the commitment beat closes in. `scale` converts the unit
    /// radius into a TRUE circle on the target canvas (unit space is stretched
    /// by the screen aspect; without the correction the "ring" renders as a
    /// tall ellipse that never nests inside the sanctuary's sigil arcs).
    private static func ringPoint(slot: Int, t: TimeInterval, beat: Double,
                                  scale: CGSize) -> CGPoint {
        let tighten = 1 - 0.35 * smoothstep(beat, 4.30, 5.0)
        let radius = ringRadius * tighten
        let angle = (Double(slot) / Double(ringCount)) * .pi * 2 + t * 0.08
        return CGPoint(x: origin.x + radius * cos(angle) * scale.width,
                       y: origin.y + radius * sin(angle) * scale.height)
    }

    /// Centre-high anchor the story revolves around (unit space). High enough
    /// that the dot, the mark, and the sanctuary ring all sit clear of the
    /// copy column, which lives in the lower half of every page.
    static let origin = CGPoint(x: 0.5, y: 0.30)

    /// Sanctuary orbit radius as a fraction of the canvas's SHORT side.
    static let ringRadius = 0.21

    /// Where the consequence beat's shared password chip glows (unit space) —
    /// in the gap the consequence copy leaves between its title and prompt.
    static let sharedChip = CGPoint(x: 0.5, y: 0.42)

    // MARK: Pure math

    /// Deterministic per-index doubles in 0…1 (SplitMix64). Seeded, never
    /// random at runtime: the same install always tells the same story, and
    /// scrubbing backwards retraces it exactly.
    static func unitRandom(_ index: Int, salt: UInt64) -> Double {
        var z = UInt64(bitPattern: Int64(index)) &* 0x9E37_79B9_7F4A_7C15 &+ salt
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }

    static func smoothstep(_ x: Double, _ from: Double, _ to: Double) -> Double {
        guard to > from else { return x < from ? 0 : 1 }
        let u = min(max((x - from) / (to - from), 0), 1)
        return u * u * (3 - 2 * u)
    }

    static func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }

    static func easeInOut(_ x: Double) -> Double {
        x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    static func lerp(_ a: CGPoint, _ b: CGPoint, _ u: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u)
    }
}
