import SwiftUI

/// The Loox four-point sparkle as a vector shape, transcribed from the brand
/// symbol (`loox-s.svg`, the white star at the centre of the six-circle mark).
/// Unit-normalized in a 1:1 box so any frame renders it undistorted. This is
/// the focal glyph of the Controlled Reveal motion language: stroking its trim
/// "draws the mark in" while the vault unlocks.
nonisolated struct LooxSparkShape: Shape {
    /// Width : height of the sparkle's bounding box in the source artwork (square).
    static let aspectRatio: CGFloat = 1.0

    func path(in rect: CGRect) -> Path {
        let rect = Self.fitted(in: rect)
        var p = Path()
        // Concave four-point star: tips at top/right/bottom/left, control points
        // pulled toward the centre so each arm curves in (matching the symbol).
        p.move(to: pt(rect, 0.5, 0.0))
        p.addCurve(to: pt(rect, 1.0, 0.5),
                   control1: pt(rect, 0.5, 0.3333), control2: pt(rect, 0.6667, 0.5))
        p.addCurve(to: pt(rect, 0.5, 1.0),
                   control1: pt(rect, 0.6667, 0.5), control2: pt(rect, 0.5, 0.6667))
        p.addCurve(to: pt(rect, 0.0, 0.5),
                   control1: pt(rect, 0.5, 0.6667), control2: pt(rect, 0.3333, 0.5))
        p.addCurve(to: pt(rect, 0.5, 0.0),
                   control1: pt(rect, 0.3333, 0.5), control2: pt(rect, 0.5, 0.3333))
        p.closeSubpath()
        return p
    }

    /// Largest aspect-correct rect centered inside `rect`.
    private static func fitted(in rect: CGRect) -> CGRect {
        let scale = min(rect.width / aspectRatio, rect.height)
        let size = CGSize(width: scale * aspectRatio, height: scale)
        return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    private func pt(_ rect: CGRect, _ ux: CGFloat, _ uy: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + ux * rect.width, y: rect.minY + uy * rect.height)
    }
}

/// The animated mark: the sparkle stroked in the brand gradient. While
/// `animating`, a trim segment continuously draws the outline — the mark
/// working itself in during unlock. Reduce Motion (or `animating == false`)
/// shows the full static sparkle.
struct LooxSparkMark: View {
    var animating = false
    var lineWidth: CGFloat = 3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0

    /// Brand gradient from the symbol artwork (deep blue → cyan).
    private var gradient: LinearGradient {
        LinearGradient(colors: [Color(red: 0x0D / 255, green: 0x47 / 255, blue: 0xFF / 255),
                                Color(red: 0x00 / 255, green: 0xB2 / 255, blue: 0xFF / 255)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var isDrawing: Bool { animating && !reduceMotion }

    var body: some View {
        LooxSparkShape()
            .trim(from: 0, to: isDrawing ? drawn : 1)
            .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .aspectRatio(LooxSparkShape.aspectRatio, contentMode: .fit)
            .task(id: isDrawing) {
                guard isDrawing else { drawn = 1; return }
                drawn = 0
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    drawn = 1
                }
            }
            .accessibilityHidden(true)
    }
}
