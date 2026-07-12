//
//  LooxAnimationEngine.swift
//  Vaultify
//
//  Deterministic timeline for the landing loop. Every visual property is a
//  pure function of the loop-local time, so the animation loops seamlessly
//  and never drifts: logo → burst → three floating clusters → converge → logo.
//

import SwiftUI

enum LooxPhase {
    case logo
    case burst(Double)
    case cluster(Int)
    case swap(from: Int, to: Int, progress: Double)
    case converge(Double)
}

enum LooxTimeline {
    static let duration: TimeInterval = 12.5

    static func phase(at t: TimeInterval) -> LooxPhase {
        switch t {
        case ..<1.6: .logo
        case ..<2.5: .burst((t - 1.6) / 0.9)
        case ..<4.7: .cluster(0)
        case ..<5.4: .swap(from: 0, to: 1, progress: (t - 4.7) / 0.7)
        case ..<7.6: .cluster(1)
        case ..<8.3: .swap(from: 1, to: 2, progress: (t - 7.6) / 0.7)
        case ..<10.3: .cluster(2)
        case ..<11.2: .converge((t - 10.3) / 0.9)
        default: .logo
        }
    }

    /// Loop-local instants at which each theme's cluster scene begins:
    /// theme 0 enters with the burst, themes 1 and 2 with their swaps.
    /// Used to rewind the matching Memoji clip at every scene entry.
    static let sceneStarts: [TimeInterval] = [1.6, 4.7, 7.6]

    // Wave frequencies are integer multiples of 2π/duration so idle motion
    // is continuous across the loop boundary.
    static let waveSlow = 2 * .pi / duration        // 1 cycle per loop
    static let waveMid = 4 * .pi / duration         // 2 cycles
    static let waveFast = 6 * .pi / duration        // 3 cycles
}

enum LooxEase {
    static func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }

    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = clamp01((x - edge0) / (edge1 - edge0))
        return t * t * (3 - 2 * t)
    }

    static func inOut(_ p: Double) -> Double {
        let t = clamp01(p)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    /// Ease-out with a soft overshoot, for bubbles settling into orbit.
    static func outBack(_ p: Double, overshoot: Double = 1.35) -> Double {
        let t = clamp01(p) - 1
        return 1 + t * t * ((overshoot + 1) * t + overshoot)
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
}

/// Resolved per-frame state of one of the six morphing orbs.
struct LooxOrbFrame {
    var center: CGPoint
    var diameter: CGFloat
    var logoOpacity: Double       // brand gradient overlay (cloud look)
    var bubbleOpacity: Double     // icon bubble underneath
    var shadowOpacity: Double
    var fromTheme: Int
    var toTheme: Int
    var crossfade: Double         // 0 = fromTheme bubble, 1 = toTheme bubble
}

/// Resolved per-frame state of the central disc, star, and glow.
struct LooxCenterFrame {
    var diameter: CGFloat
    var tintOpacity: Double
    var fromTheme: Int
    var toTheme: Int
    var crossfade: Double
    var starDiameter: CGFloat
    var starOpacity: Double
    var glowOpacity: Double
    /// Degrees; only the launch transition spins the sparkle.
    var starRotation: Double = 0
}

enum LooxResolver {

    /// Clockwise revolution speed of the orbiting bubbles, degrees/second.
    private static let orbitDriftRate: Double = 6

    /// The whole cluster slowly revolves around the center while it is on
    /// screen, like the iCloud landing page. The angle grows continuously
    /// from the moment the burst starts, so every phase handoff is smooth;
    /// it is only consumed between burst and converge, which is why the
    /// reset at the loop boundary is invisible.
    private static func orbitPoint(theme: Int, slot: Int, time t: TimeInterval) -> CGPoint {
        let spec = LooxTheme.all[theme].slots[slot]
        let theta = orbitDriftRate * .pi / 180 * max(0, t - 1.6)
        let p = spec.point
        let c = LooxCanvas.center
        let dx = p.x - c.x
        let dy = p.y - c.y
        return CGPoint(
            x: c.x + dx * cos(theta) - dy * sin(theta),
            y: c.y + dx * sin(theta) + dy * cos(theta)
        )
    }

    /// Gentle bobbing applied while a cluster is on screen.
    private static func floatOffset(_ i: Int, _ t: TimeInterval) -> CGPoint {
        let phase = Double(i) * 1.9
        return CGPoint(
            x: sin(t * LooxTimeline.waveMid + phase) * 3.2,
            y: sin(t * LooxTimeline.waveFast + phase * 2.1) * 4.0
        )
    }

    /// Subtle drift of the cloud lobes while the logo idles.
    private static func breatheOffset(_ i: Int, _ t: TimeInterval) -> CGPoint {
        let phase = Double(i) * 1.3
        return CGPoint(
            x: sin(t * LooxTimeline.waveSlow + phase) * 1.6,
            y: cos(t * LooxTimeline.waveMid + phase) * 1.6
        )
    }

    static func orbFrame(index i: Int, time t: TimeInterval) -> LooxOrbFrame {
        let logoCenter = LooxCanvas.logoCenters[i]
        let logoAlpha = LooxCanvas.logoOpacities[i]

        switch LooxTimeline.phase(at: t) {
        case .logo:
            return LooxOrbFrame(
                center: logoCenter.looxOffset(by: breatheOffset(i, t)),
                diameter: LooxCanvas.logoDiameter,
                logoOpacity: logoAlpha, bubbleOpacity: 0, shadowOpacity: 0,
                fromTheme: 0, toTheme: 0, crossfade: 0
            )

        case .burst(let p):
            // Stagger each lobe slightly so the cloud unfolds organically.
            let pi = LooxEase.clamp01((p - Double(i) * 0.05) / 0.75)
            let e = LooxEase.outBack(pi)
            let spec = LooxTheme.all[0].slots[i]
            let drift = floatOffset(i, t)
            let target = orbitPoint(theme: 0, slot: i, time: t)
                .looxOffset(by: CGPoint(x: drift.x * pi, y: drift.y * pi))
            return LooxOrbFrame(
                center: CGPoint.looxLerp(logoCenter, target, e),
                diameter: CGFloat(LooxEase.lerp(LooxCanvas.logoDiameter, spec.diameter, e)),
                logoOpacity: logoAlpha * (1 - LooxEase.smoothstep(0.25, 0.7, pi)),
                bubbleOpacity: LooxEase.smoothstep(0.15, 0.55, pi),
                shadowOpacity: LooxEase.smoothstep(0.5, 0.9, pi),
                fromTheme: 0, toTheme: 0, crossfade: 0
            )

        case .cluster(let k):
            let spec = LooxTheme.all[k].slots[i]
            return LooxOrbFrame(
                center: orbitPoint(theme: k, slot: i, time: t).looxOffset(by: floatOffset(i, t)),
                diameter: spec.diameter,
                logoOpacity: 0, bubbleOpacity: 1, shadowOpacity: 1,
                fromTheme: k, toTheme: k, crossfade: 0
            )

        case .swap(let a, let b, let p):
            let from = LooxTheme.all[a].slots[i]
            let to = LooxTheme.all[b].slots[i]
            let e = LooxEase.inOut(p)
            let fromPoint = orbitPoint(theme: a, slot: i, time: t)
            let toPoint = orbitPoint(theme: b, slot: i, time: t)
            // iCloud-style arrival bounce: a damped spring on scale only —
            // the bubble overshoots ~10%, dips back ~6%, and settles.
            // Staggered per slot so the cluster ripples, not pulses.
            let u = LooxEase.clamp01((p - Double(i) * 0.05) / 0.78)
            let pop = exp(-3.5 * u) * sin(2 * .pi * u)
            return LooxOrbFrame(
                center: CGPoint.looxLerp(fromPoint, toPoint, e).looxOffset(by: floatOffset(i, t)),
                diameter: CGFloat(LooxEase.lerp(from.diameter, to.diameter, e)) * CGFloat(1 + 0.25 * pop),
                logoOpacity: 0, bubbleOpacity: 1, shadowOpacity: 1,
                fromTheme: a, toTheme: b,
                crossfade: LooxEase.smoothstep(0.15, 0.85, p)
            )

        case .converge(let p):
            // Blue veil grows over each bubble first, then the blobs glide
            // home and stack back into the cloud silhouette.
            let spec = LooxTheme.all[2].slots[i]
            let veil = LooxEase.smoothstep(0, 0.25, p)
            let travel = LooxEase.inOut(LooxEase.clamp01((p - 0.2) / 0.75))
            let grow = LooxEase.inOut(LooxEase.clamp01((p - 0.05) / 0.9))
            let drift = floatOffset(i, t)
            let start = orbitPoint(theme: 2, slot: i, time: t)
                .looxOffset(by: CGPoint(x: drift.x * (1 - p), y: drift.y * (1 - p)))
            let settle = 0.75 + 0.25 * LooxEase.smoothstep(0.7, 1, p)
            return LooxOrbFrame(
                center: CGPoint.looxLerp(start, LooxCanvas.logoCenters[i], travel),
                diameter: CGFloat(LooxEase.lerp(spec.diameter, LooxCanvas.logoDiameter, grow)),
                logoOpacity: logoAlpha * veil * settle,
                bubbleOpacity: 1 - LooxEase.smoothstep(0.05, 0.4, p),
                shadowOpacity: 1 - LooxEase.smoothstep(0, 0.25, p),
                fromTheme: 2, toTheme: 2, crossfade: 0
            )
        }
    }

    static func centerFrame(time t: TimeInterval) -> LooxCenterFrame {
        let starPulse = 1 + 0.015 * sin(t * LooxTimeline.waveMid)

        switch LooxTimeline.phase(at: t) {
        case .logo:
            return LooxCenterFrame(
                diameter: LooxTheme.centerDiameter, tintOpacity: 0,
                fromTheme: 0, toTheme: 0, crossfade: 0,
                starDiameter: LooxCanvas.starDiameter * starPulse,
                starOpacity: 1, glowOpacity: 0.45
            )

        case .burst(let p):
            let e = LooxEase.outBack(LooxEase.clamp01(p / 0.85))
            return LooxCenterFrame(
                diameter: CGFloat(LooxEase.lerp(LooxTheme.centerDiameter * 0.7, LooxTheme.centerDiameter, e)),
                tintOpacity: LooxEase.smoothstep(0.25, 0.7, p),
                fromTheme: 0, toTheme: 0, crossfade: 0,
                starDiameter: CGFloat(LooxEase.lerp(LooxCanvas.starDiameter, LooxTheme.centerStarDiameter, LooxEase.inOut(p))),
                starOpacity: 1 - LooxEase.smoothstep(0.45, 0.8, p),
                glowOpacity: 0.45 * (1 - LooxEase.smoothstep(0, 0.5, p))
            )

        case .cluster(let k):
            let bob = sin(t * LooxTimeline.waveMid) * 2
            return LooxCenterFrame(
                diameter: LooxTheme.centerDiameter + bob,
                tintOpacity: 1,
                fromTheme: k, toTheme: k, crossfade: 0,
                starDiameter: LooxTheme.centerStarDiameter * starPulse,
                starOpacity: 0, glowOpacity: 0
            )

        case .swap(let a, let b, let p):
            // The identity disc takes a smaller spring bounce, in sympathy
            // with the icon bubbles around it.
            let pop = exp(-3.5 * p) * sin(2 * .pi * p)
            return LooxCenterFrame(
                diameter: LooxTheme.centerDiameter * CGFloat(1 + 0.12 * pop), tintOpacity: 1,
                fromTheme: a, toTheme: b,
                crossfade: LooxEase.smoothstep(0.15, 0.85, p),
                starDiameter: LooxTheme.centerStarDiameter * starPulse,
                starOpacity: 0, glowOpacity: 0
            )

        case .converge(let p):
            // The sparkle pops back in at full logo size once the cloud
            // has reformed.
            let reveal = LooxEase.smoothstep(0.82, 1, p)
            let pop = 0.75 + 0.25 * LooxEase.outBack(LooxEase.clamp01((p - 0.82) / 0.18))
            return LooxCenterFrame(
                diameter: LooxTheme.centerDiameter,
                tintOpacity: 1 - LooxEase.smoothstep(0.1, 0.45, p),
                fromTheme: 2, toTheme: 2, crossfade: 0,
                starDiameter: LooxCanvas.starDiameter * CGFloat(pop),
                starOpacity: reveal,
                glowOpacity: 0.45 * LooxEase.smoothstep(0.8, 1, p)
            )
        }
    }
}
