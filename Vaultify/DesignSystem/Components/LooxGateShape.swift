import SwiftUI

/// The Loox ∞ loop as a vector shape, transcribed from the brand wordmark SVG
/// (`Assets.xcassets/logo.imageset/logo.svg`, the middle glyph of L-∞-X).
/// Unit-normalized and aspect-fitted (≈1.893:1) so any frame renders the loop
/// undistorted. This is the gate of the Controlled Reveal motion language:
/// stroking its trim "draws the gate open" while the vault unlocks.
nonisolated struct LooxGateShape: Shape {
    /// Width : height of the loop's own bounding box in the source artwork.
    static let aspectRatio: CGFloat = 1.8928

    func path(in rect: CGRect) -> Path {
        let rect = Self.fitted(in: rect)
        var p = Path()
        p.move(to: pt(rect, 0.4874, 0.7064))
        p.addCurve(to: pt(rect, 0.1796, 0.9215), control1: pt(rect, 0.3867, 0.9281), control2: pt(rect, 0.2841, 0.9998))
        p.addCurve(to: pt(rect, 0.0377, 0.4110), control1: pt(rect, 0.1248, 0.8805), control2: pt(rect, 0.0000, 0.7503))
        p.addCurve(to: pt(rect, 0.3594, 0.1466), control1: pt(rect, 0.0484, 0.3144), control2: pt(rect, 0.1456, 0.0000))
        p.addCurve(to: pt(rect, 0.5050, 0.3879), control1: pt(rect, 0.3750, 0.1573), control2: pt(rect, 0.4258, 0.2155))
        p.addCurve(to: pt(rect, 0.5976, 0.5904), control1: pt(rect, 0.5247, 0.4307), control2: pt(rect, 0.5605, 0.5119))
        p.addCurve(to: pt(rect, 0.7043, 0.7590), control1: pt(rect, 0.6296, 0.6582), control2: pt(rect, 0.6607, 0.7243))
        p.addCurve(to: pt(rect, 0.8077, 0.7590), control1: pt(rect, 0.7070, 0.7612), control2: pt(rect, 0.7589, 0.7954))
        p.addCurve(to: pt(rect, 0.8908, 0.5014), control1: pt(rect, 0.8552, 0.7237), control2: pt(rect, 0.8999, 0.6196))
        p.addCurve(to: pt(rect, 0.7043, 0.2932), control1: pt(rect, 0.8797, 0.3566), control2: pt(rect, 0.8078, 0.2307))
        p.addCurve(to: pt(rect, 0.5883, 0.4827), control1: pt(rect, 0.6791, 0.3084), control2: pt(rect, 0.6405, 0.3716))
        p.addLine(to: pt(rect, 0.5281, 0.3522))
        p.addCurve(to: pt(rect, 0.6559, 0.1466), control1: pt(rect, 0.5836, 0.2420), control2: pt(rect, 0.6262, 0.1734))
        p.addCurve(to: pt(rect, 0.7949, 0.1107), control1: pt(rect, 0.7003, 0.1065), control2: pt(rect, 0.7496, 0.0983))
        p.addCurve(to: pt(rect, 0.9840, 0.5794), control1: pt(rect, 0.8602, 0.1285), control2: pt(rect, 1.0000, 0.2720))
        p.addCurve(to: pt(rect, 0.8342, 0.9215), control1: pt(rect, 0.9789, 0.6780), control2: pt(rect, 0.9473, 0.8514))
        p.addCurve(to: pt(rect, 0.5976, 0.8411), control1: pt(rect, 0.8063, 0.9387), control2: pt(rect, 0.6958, 1.0000))
        p.addCurve(to: pt(rect, 0.3905, 0.4110), control1: pt(rect, 0.5759, 0.8060), control2: pt(rect, 0.5069, 0.6626))
        p.addCurve(to: pt(rect, 0.3036, 0.2897), control1: pt(rect, 0.3537, 0.3397), control2: pt(rect, 0.3247, 0.2993))
        p.addCurve(to: pt(rect, 0.1244, 0.5165), control1: pt(rect, 0.2060, 0.2453), control2: pt(rect, 0.1307, 0.3500))
        p.addCurve(to: pt(rect, 0.3076, 0.7623), control1: pt(rect, 0.1183, 0.6781), control2: pt(rect, 0.1971, 0.8156))
        p.addCurve(to: pt(rect, 0.4255, 0.5794), control1: pt(rect, 0.3344, 0.7494), control2: pt(rect, 0.3737, 0.6884))
        p.addLine(to: pt(rect, 0.4874, 0.7064))
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

/// The animated gate: the ∞ loop stroked in the brand gradient. While
/// `animating`, a trim segment continuously draws the loop — the gate working
/// itself open during unlock. Reduce Motion (or `animating == false`) shows
/// the full static loop.
struct LooxGateMark: View {
    var animating = false
    var lineWidth: CGFloat = 3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0

    /// Brand gradient from the wordmark artwork.
    private var gradient: LinearGradient {
        LinearGradient(colors: [Color(red: 0x15 / 255, green: 0x44 / 255, blue: 0xFD / 255),
                                Color(red: 0x20 / 255, green: 0xBD / 255, blue: 0xFD / 255)],
                       startPoint: .leading, endPoint: .trailing)
    }

    private var isDrawing: Bool { animating && !reduceMotion }

    var body: some View {
        LooxGateShape()
            .trim(from: 0, to: isDrawing ? drawn : 1)
            .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .aspectRatio(LooxGateShape.aspectRatio, contentMode: .fit)
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
