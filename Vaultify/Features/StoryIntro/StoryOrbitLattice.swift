import SwiftUI

/// Where the gathered passwords come to rest: a three-orbit bubble cluster in
/// the brand's own language (the Loox cloud), not a single necklace.
///
/// The single ring this replaced put 24 scrap CARDS on one 82pt-radius orbit —
/// 1,056pt of card on a 518pt circumference, three deep while the surplus was
/// still fading — which is why the gather read as a pile-up.
///
/// EVERY length here is a fraction of `reach`: orbit radii, bubble diameters,
/// the mark, the sigils and the ambient motes. That makes each clearance an
/// ANGULAR fact rather than a point measurement, so it holds at any canvas size
/// and through the commitment beat's contraction. (Radii as fractions with
/// bubble sizes in absolute points was the earlier bug: shrink the canvas and
/// the constant-size bubbles closed every gap.)
nonisolated enum StoryOrbitLattice {

    /// One orbit: how many bubbles ride it, its radius and its bubble DIAMETER
    /// as fractions of `reach`, and how fast (and which way) it revolves.
    struct Ring {
        let count: Int
        let radius: Double
        let diameter: Double
        let spin: Double
        let phase: Double
    }

    /// Inner lobes read as the logo's cloud, the outer ones as its spray.
    /// Counter-rotating, so the cluster never looks like one rigid wheel.
    /// The gaps these produce, in fractions of reach: mark↔A 0.18, A↔B 0.13,
    /// B↔C 0.21, C↔sigil 0.10, and at least 0.41 between neighbours on any one
    /// orbit. `StoryIntroTests` pins them.
    static let rings: [Ring] = [
        Ring(count: 5, radius: 0.72, diameter: 0.36, spin: 0.070, phase: 0),
        Ring(count: 10, radius: 1.16, diameter: 0.26, spin: -0.048, phase: 0.38),
        Ring(count: 17, radius: 1.58, diameter: 0.17, spin: 0.031, phase: 0.71),
    ]

    /// Scraps that survive the convergence and become bubbles.
    static let slotCount = 32

    /// The bubble symbol's native side. Sizes are expressed against it because
    /// `GraphicsContext` stamps a resolved symbol by scale, and the lattice
    /// only ever scales it DOWN.
    static let bubbleBase: CGFloat = 44

    /// The two sigil arcs, as multiples of `reach` — outside the outermost
    /// orbit with room to spare, so nothing ever draws through a bubble.
    static let sigilRadii: [Double] = [1.76, 1.94]

    /// How far down the frame ANY of the cluster's art may reach — the outer
    /// sigil, the outermost bubble, and the ambient motes alike — as a fraction
    /// of the canvas height. The copy column's own clearance is derived from
    /// this same number: art and copy used to be two independent constants,
    /// which is how the sigils ended up sweeping through the sanctuary title on
    /// a small phone.
    static let artFloor = 0.44

    /// How far down the frame the outermost BUBBLE reaches. The sigils go a
    /// little further (out to `artFloor`), but they are 2pt arcs while these
    /// are solid brand colour, so the turn beat — which has no sigils yet —
    /// clears to here rather than to the full floor.
    /// Stored, not computed: `StoryBeatView` reads it while laying out every
    /// beat page, and it is a constant folded out of three other constants.
    static let bubbleFloor: Double = {
        let outermost = rings.map { $0.radius + $0.diameter / 2 }.max() ?? 0
        return StoryField.origin.y
            + outermost / (sigilRadii.max() ?? 1) * (artFloor - StoryField.origin.y)
    }()

    /// The cluster's base orbit reach in points. Bounded twice: by the canvas's
    /// short side (so it stays a cluster, not a band) and by `artFloor` (so it
    /// never grows into the copy, whatever the aspect).
    static func reach(_ size: CGSize) -> CGFloat {
        let shortSide = StoryField.ringRadius * min(size.width, size.height)
        let floorBound = (artFloor - StoryField.origin.y)
            / (sigilRadii.max() ?? 1) * Double(size.height)
        return min(shortSide, CGFloat(floorBound))
    }

    /// The Loox mark at the cluster's heart — sized FROM the cluster like
    /// everything else. A constant 56pt swallowed the inner orbit on a small
    /// phone, where the orbits scale with the canvas but a constant does not.
    static func markDiameter(reach: CGFloat) -> CGFloat {
        reach * CGFloat(markDiameterFraction)
    }

    /// The commitment beat drawing the cluster in. Because every length here is
    /// a fraction of reach, applying it to reach alone contracts the whole
    /// cluster self-similarly and preserves every clearance.
    static func tighten(_ beat: Double) -> Double {
        1 - 0.30 * StoryField.smoothstep(beat, 4.30, 5.0)
    }

    /// Which ring a survivor slot rides, and its index on that ring.
    static func placement(slot: Int) -> (ring: Ring, position: Int) {
        var remaining = ((slot % slotCount) + slotCount) % slotCount
        for ring in rings {
            if remaining < ring.count { return (ring, remaining) }
            remaining -= ring.count
        }
        return (rings[0], 0)
    }

    /// A survivor's live orbit point in unit space. `scale` converts the unit
    /// radius into a TRUE circle on the target canvas (unit space is stretched
    /// by the screen aspect).
    static func point(slot: Int, t: TimeInterval, tighten: Double,
                      scale: CGSize) -> CGPoint {
        let (ring, position) = placement(slot: slot)
        let radius = StoryField.ringRadius * ring.radius * tighten
        let angle = (Double(position) / Double(ring.count)) * .pi * 2
            + ring.phase + t * ring.spin
        return CGPoint(x: StoryField.origin.x + radius * cos(angle) * scale.width,
                       y: StoryField.origin.y + radius * sin(angle) * scale.height)
    }

    /// A slot's bubble size as a multiple of `bubbleBase`, for a cluster of the
    /// given reach.
    static func bubbleSize(slot: Int, reach: CGFloat) -> Double {
        Double(reach) * placement(slot: slot).ring.diameter / Double(bubbleBase)
    }

    /// Smallest edge-to-edge gap between neighbours on any one orbit, as a
    /// fraction of reach. Positive means nothing touches — at every canvas
    /// size, because it is dimensionless.
    static var minimumNeighbourGap: Double {
        rings.map { 2 * $0.radius * sin(.pi / Double($0.count)) - $0.diameter }.min() ?? 0
    }

    /// Smallest radial gap between consecutive shells (mark → A → B → C →
    /// sigil), as a fraction of reach.
    static var minimumShellGap: Double {
        var edges: [(inner: Double, outer: Double)] = [(0, markDiameterFraction / 2)]
        edges += rings.map { ($0.radius - $0.diameter / 2, $0.radius + $0.diameter / 2) }
        edges.append((sigilRadii.min() ?? 0, sigilRadii.max() ?? 0))
        return zip(edges, edges.dropFirst()).map { $1.inner - $0.outer }.min() ?? 0
    }

    static let markDiameterFraction = 0.72

    // MARK: Ambient motes

    /// Small free bubbles drifting around the cluster once the vault exists —
    /// the brand loop's bubble language at a whisper, and the depth cue that
    /// keeps the sanctuary from being one flat ring.
    static let ambientCount = 34

    /// A mote's live sample, or nil before it has any presence. `burst` is the
    /// seal flinging everything out.
    static func mote(index: Int, t: TimeInterval, beat: Double, burst: Double,
                     scale: CGSize, reach: CGFloat) -> StoryField.Sample? {
        let appear = StoryField.smoothstep(beat, 2.90, 3.90) * (1 - burst)
        guard appear > 0.01 else { return nil }

        // Seeded shell from just outside the mark out to the sigils, so the
        // motes fill the space the orbits leave rather than queueing up on a
        // ring of their own. Bounded by the sigil radius on purpose: `artFloor`
        // is the whole cluster's contract with the copy column, and a mote is
        // solid brand colour drifting behind a title, not a faint arc.
        let shell = 0.70 + 1.19 * StoryField.unitRandom(index, salt: 0x51)
        let bob = 0.05 * sin(t * (0.25 + 0.35 * StoryField.unitRandom(index, salt: 0x52))
                             + StoryField.unitRandom(index, salt: 0x53) * .pi * 2)
        let draw = tighten(beat)
        let radius = StoryField.ringRadius * (shell + bob) * draw

        let direction: Double = index % 2 == 0 ? 1 : -1
        let angle = StoryField.unitRandom(index, salt: 0x54) * .pi * 2
            + t * (0.020 + 0.045 * StoryField.unitRandom(index, salt: 0x55)) * direction

        var position = CGPoint(x: StoryField.origin.x + radius * cos(angle) * scale.width,
                               y: StoryField.origin.y + radius * sin(angle) * scale.height)

        // Depth: the small ones sit far back and stay dim, the near few carry
        // the highlight. Motes never compete with the mark at the centre.
        let near = StoryField.unitRandom(index, salt: 0x56)
        let size = Double(reach) * (0.06 + 0.15 * near) / Double(bubbleBase) * draw
        var opacity = appear * (0.22 + 0.42 * near)

        if burst > 0 {
            position.x += (position.x - StoryField.origin.x) * burst * 1.9
            position.y += (position.y - StoryField.origin.y) * burst * 1.9
            opacity *= 1 - burst
        }
        return StoryField.Sample(position: position, opacity: opacity, scale: size)
    }
}
