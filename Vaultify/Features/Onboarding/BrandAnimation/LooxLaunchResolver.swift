//
//  LooxLaunchResolver.swift
//  Vaultify
//
//  Launch choreography, told as an energy story rather than a rotation:
//  the logo squashes (anticipation), shatters apart (the discs become
//  particles), whirls into an uneven, depth-sorted spiral with ghost
//  trails, slams back into a single dense dot (80 ms), holds a beat of
//  silence (40 ms), and then that one disc blooms explosively — its brand
//  gradient dissolving into the theme background so the new screen IS the
//  final disc of the chase. Pure functions of elapsed time throughout.
//

import SwiftUI

enum LooxLaunchTimeline {
    static let revertEnd: TimeInterval = 0.35   // frozen loop → logo
    static let squashEnd: TimeInterval = 0.50   // squash & stretch
    static let breakEnd: TimeInterval = 0.72    // discs shear apart
    static let spiralEnd: TimeInterval = 1.30   // accelerating vortex
    static let contractEnd: TimeInterval = 1.38 // 80 ms slam to center
    static let freezeEnd: TimeInterval = 1.42   // 40 ms of silence
    static let bloomEnd: TimeInterval = 1.70    // one disc becomes the screen
    static let total: TimeInterval = 1.85
}

enum LooxLaunchResolver {

    /// Discs ordered by their angle around the logo center; index 0 leads.
    private static let ringPosition: [Int] = [2, 3, 1, 4, 5, 0]
    /// Deliberately uneven chase lags — organic, not a loading spinner.
    private static let lags: [Double] = [0, 0.02, 0.07, 0.11, 0.18, 0.27]
    /// Leading discs read as near/front, trailing ones fall behind.
    private static let depthScale: [Double] = [1.15, 1.05, 0.95, 0.88, 0.80, 0.74]
    private static let depthOpacity: [Double] = [1.0, 0.96, 0.90, 0.84, 0.76, 0.70]

    private static let spiralTurns: Double = 2 * .pi * 1.7
    private static let contractedDiameter: Double = 121

    // MARK: Group squash (applied as a whole-canvas transform)

    /// Squash & stretch keyframes: rest → squash → overshoot → rest.
    static func groupSquash(elapsed e: TimeInterval) -> (x: CGFloat, y: CGFloat) {
        guard e > LooxLaunchTimeline.revertEnd, e < LooxLaunchTimeline.squashEnd else { return (1, 1) }
        let p = (e - LooxLaunchTimeline.revertEnd) / (LooxLaunchTimeline.squashEnd - LooxLaunchTimeline.revertEnd)
        let times: [Double] = [0, 0.4, 0.75, 1]
        let xs: [Double] = [1, 1.06, 0.97, 1]
        let ys: [Double] = [1, 0.88, 1.04, 1]
        func sample(_ keys: [Double]) -> CGFloat {
            for s in 1..<times.count where p <= times[s] {
                let u = LooxEase.inOut((p - times[s - 1]) / (times[s] - times[s - 1]))
                return CGFloat(LooxEase.lerp(keys[s - 1], keys[s], u))
            }
            return CGFloat(keys[times.count - 1])
        }
        return (sample(xs), sample(ys))
    }

    // MARK: Discs

    static func orbFrame(index i: Int, elapsed e: TimeInterval, frozenLoopTime: TimeInterval) -> LooxOrbFrame {
        let frozen = LooxResolver.orbFrame(index: i, time: frozenLoopTime)
        let logo = logoOrbFrame(index: i, keepingThemesOf: frozen)
        if e < LooxLaunchTimeline.revertEnd {
            return blend(frozen, logo, LooxEase.inOut(e / LooxLaunchTimeline.revertEnd))
        }
        if e < LooxLaunchTimeline.squashEnd { return logo }

        var frame = logo
        let c = LooxCanvas.center
        let offset = CGPoint(x: logo.center.x - c.x, y: logo.center.y - c.y)
        let rp = ringPosition[i]

        // Shatter: the logo loosens, discs shear apart with a hint of spin.
        if e < LooxLaunchTimeline.breakEnd {
            let p = (e - LooxLaunchTimeline.squashEnd) / (LooxLaunchTimeline.breakEnd - LooxLaunchTimeline.squashEnd)
            frame.center = spun(offset, by: 0.05 * .pi * p * p, radiusFactor: 1 + 0.38 * p * p, around: c)
            return frame
        }

        // Spiral with per-disc lag, depth scaling, and fading tails.
        let qRaw = LooxEase.clamp01((e - LooxLaunchTimeline.breakEnd) / (LooxLaunchTimeline.spiralEnd - LooxLaunchTimeline.breakEnd))
        let q = LooxEase.clamp01((qRaw - lags[rp]) / (1 - lags[rp]))
        let depthIn = LooxEase.smoothstep(0, 0.35, q)
        let spiralAngle = 0.05 * .pi + spiralTurns * pow(q, 2.1)
        let spiralRadius = 1.38 + 2.1 * pow(q, 1.9)
        let spiralDiameter = LooxCanvas.logoDiameter * (1 + 0.65 * LooxEase.inOut(q)) * CGFloat(LooxEase.lerp(1, depthScale[rp], depthIn))
        let spiralAlpha = logo.logoOpacity * LooxEase.lerp(1, depthOpacity[rp], LooxEase.smoothstep(0, 0.3, q))

        if e < LooxLaunchTimeline.spiralEnd {
            frame.center = spun(offset, by: spiralAngle, radiusFactor: spiralRadius, around: c)
            frame.diameter = spiralDiameter
            frame.logoOpacity = spiralAlpha
            return frame
        }

        // Slam: 80 ms rush into one dense dot, then hold through the silence.
        let endAngle = 0.05 * .pi + spiralTurns
        let pc = pow(LooxEase.clamp01((e - LooxLaunchTimeline.spiralEnd) / (LooxLaunchTimeline.contractEnd - LooxLaunchTimeline.spiralEnd)), 1.7)
        frame.center = spun(offset, by: endAngle + 0.25 * .pi * pc, radiusFactor: LooxEase.lerp(3.48, 0.10, pc), around: c)
        frame.diameter = CGFloat(LooxEase.lerp(LooxCanvas.logoDiameter * 1.65 * depthScale[rp], contractedDiameter, pc))
        frame.logoOpacity = LooxEase.lerp(logo.logoOpacity * depthOpacity[rp], 1, pc)

        // Bloom: the merged discs hand off to the single blooming disc.
        if e >= LooxLaunchTimeline.freezeEnd {
            let pb = LooxEase.clamp01((e - LooxLaunchTimeline.freezeEnd) / (LooxLaunchTimeline.bloomEnd - LooxLaunchTimeline.freezeEnd))
            frame.logoOpacity *= 1 - LooxEase.smoothstep(0, 0.25, pb)
        }
        return frame
    }

    /// Fake motion blur: the same disc sampled a beat earlier, ghosted.
    /// Only meaningful while the spiral is moving fast.
    static func ghostFrames(index i: Int, elapsed e: TimeInterval, frozenLoopTime: TimeInterval) -> [LooxOrbFrame] {
        guard e > LooxLaunchTimeline.breakEnd + 0.06, e < LooxLaunchTimeline.contractEnd else { return [] }
        return [(0.024, 0.35), (0.048, 0.16)].map { dt, alpha in
            var ghost = orbFrame(index: i, elapsed: e - dt, frozenLoopTime: frozenLoopTime)
            ghost.logoOpacity *= alpha
            ghost.bubbleOpacity = 0
            ghost.shadowOpacity = 0
            return ghost
        }
    }

    // MARK: Star & center disc

    static func centerFrame(elapsed e: TimeInterval, frozenLoopTime: TimeInterval) -> LooxCenterFrame {
        let frozen = LooxResolver.centerFrame(time: frozenLoopTime)
        if e < LooxLaunchTimeline.revertEnd {
            let p = LooxEase.inOut(e / LooxLaunchTimeline.revertEnd)
            var frame = frozen
            frame.tintOpacity = frozen.tintOpacity * (1 - p)
            frame.starDiameter = CGFloat(LooxEase.lerp(frozen.starDiameter, LooxCanvas.starDiameter, p))
            frame.starOpacity = LooxEase.lerp(frozen.starOpacity, 1, p)
            frame.glowOpacity = LooxEase.lerp(frozen.glowOpacity, 0.45, p)
            return frame
        }

        var frame = frozen
        frame.tintOpacity = 0
        frame.starDiameter = LooxCanvas.starDiameter
        frame.starOpacity = 1
        frame.glowOpacity = 0.45

        if e < LooxLaunchTimeline.breakEnd { return frame }

        // The sparkle counter-spins and is drawn into the forming vortex.
        let q = LooxEase.clamp01((e - LooxLaunchTimeline.breakEnd) / (LooxLaunchTimeline.spiralEnd - LooxLaunchTimeline.breakEnd))
        frame.starDiameter = LooxCanvas.starDiameter * CGFloat(1 - 0.55 * LooxEase.inOut(q))
        frame.starOpacity = 1 - LooxEase.smoothstep(0.15, 0.5, q)
        frame.starRotation = -(0.04 * .pi + 0.9 * .pi * q * q) * 180 / .pi
        frame.glowOpacity = 0.45 * (1 - LooxEase.smoothstep(0, 0.25, q))
        return frame
    }

    // MARK: Bloom disc — the destination screen itself

    /// After the silence, one disc erupts from the dot. Its brand gradient
    /// dissolves into the theme background mid-flight, so by the time it
    /// fills the screen it already is the next scene.
    /// Canvas-space diameter the bloom flight ends at — exposed so the view can
    /// compute how much boost a larger host display needs (see
    /// `LooxCloudAnimationView.floodDiameter`).
    static let bloomFinalDiameter: CGFloat = 1950

    static func bloomState(elapsed e: TimeInterval) -> (diameter: CGFloat, gradientOpacity: Double) {
        guard e >= LooxLaunchTimeline.freezeEnd else { return (0, 1) }
        let pb = LooxEase.clamp01((e - LooxLaunchTimeline.freezeEnd) / (LooxLaunchTimeline.bloomEnd - LooxLaunchTimeline.freezeEnd))
        let ease = 1 - pow(1 - pb, 4)
        return (
            CGFloat(LooxEase.lerp(contractedDiameter, Double(bloomFinalDiameter), ease)),
            1 - LooxEase.smoothstep(0.25, 0.7, pb)
        )
    }

    static func overlayOpacity(elapsed e: TimeInterval) -> Double {
        1 - LooxEase.smoothstep(LooxLaunchTimeline.bloomEnd, LooxLaunchTimeline.total, e)
    }

    // MARK: Helpers

    private static func spun(_ offset: CGPoint, by angle: Double, radiusFactor: Double, around c: CGPoint) -> CGPoint {
        let cosA = cos(angle)
        let sinA = sin(angle)
        return CGPoint(
            x: c.x + (offset.x * cosA - offset.y * sinA) * radiusFactor,
            y: c.y + (offset.x * sinA + offset.y * cosA) * radiusFactor
        )
    }

    private static func logoOrbFrame(index i: Int, keepingThemesOf frozen: LooxOrbFrame) -> LooxOrbFrame {
        LooxOrbFrame(
            center: LooxCanvas.logoCenters[i],
            diameter: LooxCanvas.logoDiameter,
            logoOpacity: LooxCanvas.logoOpacities[i],
            bubbleOpacity: 0, shadowOpacity: 0,
            fromTheme: frozen.fromTheme, toTheme: frozen.toTheme, crossfade: frozen.crossfade
        )
    }

    private static func blend(_ a: LooxOrbFrame, _ b: LooxOrbFrame, _ t: Double) -> LooxOrbFrame {
        LooxOrbFrame(
            center: CGPoint.looxLerp(a.center, b.center, t),
            diameter: CGFloat(LooxEase.lerp(a.diameter, b.diameter, t)),
            logoOpacity: LooxEase.lerp(a.logoOpacity, b.logoOpacity, t),
            bubbleOpacity: LooxEase.lerp(a.bubbleOpacity, b.bubbleOpacity, t),
            shadowOpacity: LooxEase.lerp(a.shadowOpacity, b.shadowOpacity, t),
            fromTheme: a.fromTheme, toTheme: a.toTheme, crossfade: a.crossfade
        )
    }
}
