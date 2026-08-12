import SwiftUI

/// The stage's population: seeded password "scraps" (note cards, chat bubbles,
/// browser pills, key dots) whose every visual property is a pure function of
/// (wall-clock time, beat position, per-index seed) — the LooxAnimationEngine
/// house pattern. No per-frame state anywhere: the Canvas samples this field
/// fresh each tick, so scrubbing the scroll backwards replays the story in
/// reverse for free.
nonisolated enum StoryField {

    static let scrapCount = 90
    /// Scraps that survive the convergence and become the bubble cluster.
    static var ringCount: Int { StoryOrbitLattice.slotCount }

    enum ScrapKind: Int, CaseIterable {
        case note, chat, browser, key
    }

    /// Where a scrap is and how it looks at this instant, in unit space
    /// (0…1 both axes; the stage view scales to points). `rotation` is a
    /// small card tilt in radians — the mess is never perfectly aligned.
    /// `bubbleMix` crossfades the scrap card into its brand bubble as the
    /// gather lands (0 = card, 1 = bubble), and `bubbleScale` is that bubble's
    /// own size multiplier, which grows from the card's toward its ring slot's.
    struct Sample {
        var position: CGPoint
        var opacity: Double
        var scale: Double
        var rotation: Double = 0
        var bubbleMix: Double = 0
        var bubbleScale: Double = 1
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

    /// A nominal orbit reach for tests and previews that do not model a canvas.
    /// Roughly what a 6.1" phone produces.
    static let nominalReach: CGFloat = 61

    /// The turn's gather in beat coordinates: the earliest a scrap can leave,
    /// and the beat by which the last survivor is home. The haptic ratchet in
    /// `StoryScrollProgressModel` reads these same two numbers, so what the
    /// finger feels cannot drift from what the eye sees.
    static let gatherWindow = (start: 2.10, end: 3.00)

    /// The full life of one scrap: born from the origin dot across the chaos
    /// beat, drifting until the consequence stills it, reeled into the cluster
    /// by the turn's scroll scrub, then orbiting as a bubble (survivors) or
    /// dissolving into the halo on the way in (the surplus).
    /// `burst` (0…1) is the seal's exit: the cluster flings outward and fades —
    /// the LooxSwirl dismiss verb as the curtain-raise for the real app.
    /// `ringScale` corrects the orbit for the canvas aspect; the default keeps
    /// the field aspect-agnostic for tests and previews.
    static func sample(index: Int, t: TimeInterval, beat: Double, burst: Double = 0,
                       ringScale: CGSize = CGSize(width: 1, height: 1),
                       reach: CGFloat = StoryField.nominalReach) -> Sample {
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

        // Only lattice slots persist into the sanctuary.
        let survives = index < ringCount
        let scale = 0.75 + 0.5 * unitRandom(index, salt: 0x06)

        // The turn: position becomes a scroll-scrubbed blend toward the
        // cluster — reversing the scroll visibly scatters them again. Each
        // scrap leaves on its OWN beat inside the window, so the cluster
        // assembles in waves rather than snapping shut in a single frame; the
        // last survivor is home by beat 3, the turn page's rest.
        let lead = unitRandom(index, salt: 0x09)
        let gatherStart = gatherWindow.start + 0.34 * lead
        let gatherEnd = survives ? gatherWindow.end - 0.14 * (1 - lead) : gatherStart + 0.55
        let flight = smoothstep(beat, gatherStart, gatherEnd)
        let gather = easeInOut(flight)

        let target = survives
            ? StoryOrbitLattice.point(slot: index, t: t,
                                      tighten: StoryOrbitLattice.tighten(beat), scale: ringScale)
            : haloPoint(index: index, t: t, scale: ringScale)
        var position = lerp(placed, target, gather)
        applySwirl(&position, index: index, gather: gather)

        // The surplus is ABSORBED, not stacked: it fades on the way in, so the
        // orbits close on exactly one bubble per slot. (Letting it ride all the
        // way in is what put three cards on every slot at the turn.) The window
        // must END before beat 3 for EVERY seed — the turn page rests there,
        // and a straggler still at 2% is a scrap floating over a clean cluster.
        let dissolve = survives ? 0 : smoothstep(beat, gatherStart + 0.15, gatherStart + 0.50)

        // Depth: the swarm reads in layers, not as a flat sheet of equal
        // cards. Gathering lifts every survivor to full presence — the cluster
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

        // Card → bubble: complete a little BEFORE arrival, so the cluster is
        // already speaking the brand's bubble language as it closes. The size
        // comes off the same `reach` the orbits do and carries the commitment
        // beat's contraction — radii shrinking while the bubbles held their
        // size is what closed the gaps between orbits.
        let restSize = survives
            ? StoryOrbitLattice.bubbleSize(slot: index, reach: reach)
            : Double(reach) * 0.10 / Double(StoryOrbitLattice.bubbleBase)
        let targetSize = restSize * StoryOrbitLattice.tighten(beat)
        return Sample(position: position, opacity: opacity, scale: scale,
                      rotation: rotation,
                      bubbleMix: smoothstep(flight, 0.30, 0.78),
                      bubbleScale: scale + (targetSize - scale) * flight)
    }

    /// Curved flight: a tangential bulge peaking mid-gather, so scraps swirl
    /// into the cluster instead of sliding along straight rails. Zero at both
    /// ends of the window, so rest positions stay exactly on the lattice.
    private static func applySwirl(_ position: inout CGPoint, index: Int, gather: Double) {
        guard gather > 0.001, gather < 0.999 else { return }
        let direction: Double = index % 2 == 0 ? 1 : -1
        let arc = sin(gather * .pi) * 0.075 * direction
            * (0.4 + 0.9 * unitRandom(index, salt: 0x0A))
        let dx = position.x - origin.x, dy = position.y - origin.y
        let length = max((dx * dx + dy * dy).squareRoot(), 0.0001)
        position.x += -dy / length * arc
        position.y += dx / length * arc
    }

    /// Where the surplus is absorbed: a loose shell OUTSIDE the cluster, so
    /// what is fading never overlaps what is arriving.
    private static func haloPoint(index: Int, t: TimeInterval, scale: CGSize) -> CGPoint {
        let radius = ringRadius * (1.70 + 0.75 * unitRandom(index, salt: 0x0B))
        let angle = unitRandom(index, salt: 0x0C) * .pi * 2 + t * 0.05
        return CGPoint(x: origin.x + radius * cos(angle) * scale.width,
                       y: origin.y + radius * sin(angle) * scale.height)
    }

    /// Centre-high anchor the story revolves around (unit space). High enough
    /// that the dot, the mark, and the bubble cluster all sit clear of the
    /// copy column, which lives in the lower half of every page.
    static let origin = CGPoint(x: 0.5, y: 0.30)

    /// Base orbit radius as a fraction of the canvas's SHORT side. The lattice
    /// multiplies this per ring (0.52…1.30), so the cluster's outer edge lands
    /// where the single 0.21 ring used to — same footprint, three orbits.
    static let ringRadius = 0.19

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

    // Cubes by multiplication, not `pow`. These two run ~180 times per frame
    // (once per scrap for the birth curve, once for the gather) on top of the
    // galaxy's own sampling, and `pow` is a general-purpose call the optimiser
    // cannot reduce to three multiplies on its own.
    static func easeOut(_ x: Double) -> Double {
        let u = 1 - x
        return 1 - u * u * u
    }

    static func easeInOut(_ x: Double) -> Double {
        if x < 0.5 { return 4 * x * x * x }
        let u = -2 * x + 2
        return 1 - u * u * u / 2
    }

    static func lerp(_ a: CGPoint, _ b: CGPoint, _ u: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u)
    }
}
