//
//  LooxAnimationGeometry.swift
//  Vaultify
//
//  Brand geometry extracted from "Loox — Symbol.svg": six overlapping
//  gradient circles, a radial highlight, and a four-point sparkle.
//  All coordinates live in the SVG unit space (357 x 337) and are scaled
//  to the rendered view at draw time.
//

import SwiftUI

enum LooxCanvas {
    static let size = CGSize(width: 357, height: 337)
    static let center = CGPoint(x: 178.5, y: 168.05)
    static let logoDiameter: CGFloat = 201
    static let starDiameter: CGFloat = 215
    static let glowCenter = CGPoint(x: 195.5, y: 186.05)
    static let glowDiameter: CGFloat = 237

    /// Circle centers in SVG draw order (back to front).
    static let logoCenters: [CGPoint] = [
        CGPoint(x: 139.5, y: 235.6),   // bottom-left, pale
        CGPoint(x: 100.5, y: 168.05),  // left
        CGPoint(x: 217.5, y: 235.6),   // bottom-right
        CGPoint(x: 139.5, y: 100.5),   // top-left
        CGPoint(x: 217.5, y: 100.5),   // top-right
        CGPoint(x: 256.5, y: 168.05),  // right
    ]

    static let logoOpacities: [Double] = [1.0, 0.85, 0.85, 0.85, 0.85, 0.85]

    static let logoGradients: [LooxLogoGradient] = [
        .init(colors: [.looxPale, .looxBlue], start: UnitPoint(x: 0.25, y: 0.933), end: UnitPoint(x: 0.75, y: 0.067)),
        .init(colors: [.looxSky, .looxBlue], start: .leading, end: .trailing),
        .init(colors: [.looxSky, .looxRoyal], start: UnitPoint(x: 0.75, y: 0.933), end: UnitPoint(x: 0.25, y: 0.067)),
        .init(colors: [.looxBlue, .looxRoyal], start: UnitPoint(x: 0.25, y: 0.067), end: UnitPoint(x: 0.75, y: 0.933)),
        .init(colors: [.looxRoyal, .looxDeep], start: UnitPoint(x: 0.75, y: 0.067), end: UnitPoint(x: 0.25, y: 0.933)),
        .init(colors: [.looxBlue, .looxDeep], start: .trailing, end: .leading),
    ]
}

struct LooxLogoGradient {
    let colors: [Color]
    let start: UnitPoint
    let end: UnitPoint

    var linear: LinearGradient {
        LinearGradient(colors: colors, startPoint: start, endPoint: end)
    }
}

/// Four-point sparkle from the brand mark. Each quarter is a cubic curve
/// whose control points sit one third of the way toward the center along
/// each axis, producing the concave "spark" silhouette of the SVG path.
struct LooxStarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let tips = [
            CGPoint(x: 0, y: -r), CGPoint(x: r, y: 0),
            CGPoint(x: 0, y: r), CGPoint(x: -r, y: 0),
        ]
        var path = Path()
        path.move(to: CGPoint(x: c.x + tips[0].x, y: c.y + tips[0].y))
        for i in 0..<4 {
            let from = tips[i]
            let to = tips[(i + 1) % 4]
            path.addCurve(
                to: CGPoint(x: c.x + to.x, y: c.y + to.y),
                control1: CGPoint(x: c.x + from.x / 3, y: c.y + from.y / 3),
                control2: CGPoint(x: c.x + to.x / 3, y: c.y + to.y / 3)
            )
        }
        path.closeSubpath()
        return path
    }
}

extension Color {
    /// Brand palette from the Loox symbol gradients.
    static let looxPale = Color(looxHex: 0xE6F3FF)
    static let looxSky = Color(looxHex: 0x7DD3FC)
    static let looxBlue = Color(looxHex: 0x00B2FF)
    static let looxRoyal = Color(looxHex: 0x2979FF)
    static let looxDeep = Color(looxHex: 0x0D47FF)

    init(looxHex hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension CGPoint {
    static func looxLerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    func looxOffset(by delta: CGPoint) -> CGPoint {
        CGPoint(x: x + delta.x, y: y + delta.y)
    }
}
