import CoreGraphics

/// Pure geometry for the animated mesh gradient, ported faithfully from Telegram's
/// `SoftwareGradientBackground`. `nonisolated` + deterministic → unit-testable and
/// runnable off-main. The animated view (Phase 04) plays baked frames via Core
/// Animation; this supplies the control points per phase.
nonisolated enum MeshMath {
    /// 8 fixed control points in normalized [0,1] space.
    static let basePositions: [CGPoint] = [
        CGPoint(x: 0.80, y: 0.10), CGPoint(x: 0.60, y: 0.20),
        CGPoint(x: 0.35, y: 0.25), CGPoint(x: 0.25, y: 0.60),
        CGPoint(x: 0.20, y: 0.90), CGPoint(x: 0.40, y: 0.80),
        CGPoint(x: 0.65, y: 0.75), CGPoint(x: 0.75, y: 0.40),
    ]

    /// Rotate-left by `offset` (Telegram's removeFirst→append shift).
    static func shiftArray(_ array: [CGPoint], offset: Int) -> [CGPoint] {
        guard !array.isEmpty else { return array }
        let n = array.count
        let k = ((offset % n) + n) % n
        if k == 0 { return array }
        return Array(array[k...] + array[..<k])
    }

    /// Sample every 2nd element → the 4 active color anchors.
    static func gatherPositions(_ list: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = []
        var i = 0
        while i < list.count {
            result.append(list[i])
            i += 2
        }
        return result
    }

    static func interpolate(_ a: CGPoint, _ b: CGPoint, at t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// The 4 active anchor positions for a given animation phase (0…7).
    static func positions(phase: Int) -> [CGPoint] {
        gatherPositions(shiftArray(basePositions, offset: phase))
    }
}
