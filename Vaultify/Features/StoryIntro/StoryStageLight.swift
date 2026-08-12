import SwiftUI

/// Every light source on the story stage. Pure drawing: give it a context and
/// a place, and it paints. Nothing here reads view state, which is why it
/// lives outside `StoryStageView`.
///
/// The shared rule: a light is a FALLOFF, never a disc. A blurred solid circle
/// keeps a flat plateau in its middle and prints a soft-but-visible rim — which
/// is exactly what read as "a sun" sitting behind the copy. Everything below
/// goes through `StoryGalaxy.softGradient`, whose eased stops reach zero inside
/// their own bounds, so there is no edge to see.
enum StoryStageLight {

    /// A light source with no edge.
    static func bloom(_ ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat,
                      color: Color, opacity: Double) {
        guard opacity > 0.01, radius > 1 else { return }
        let rect = CGRect(x: center.x - radius, y: center.y - radius,
                          width: radius * 2, height: radius * 2)
        ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
            StoryGalaxy.softGradient(color, peak: opacity),
            center: center, startRadius: 0, endRadius: radius))
    }

    /// Lens streaks across a light source: one long horizontal, one shorter
    /// diagonal. This is what turns a bright disc into a flare — the note the
    /// bare glow was missing.
    static func flare(_ ctx: inout GraphicsContext, size: CGSize, center: CGPoint,
                      strength: Double, color: Color = StoryPalette.glow) {
        guard strength > 0.01 else { return }
        streak(&ctx, center: center, length: size.width * 1.30, thinness: 0.055,
               angle: 0, color: color, opacity: 0.42 * strength)
        streak(&ctx, center: center, length: size.width * 0.72, thinness: 0.10,
               angle: -0.55, color: color, opacity: 0.24 * strength)
    }

    /// Amber unease pooling under the consequence beat.
    static func warningPool(_ ctx: inout GraphicsContext, size: CGSize,
                            ripple: Double, veilFade: Double) {
        bloom(&ctx,
              center: CGPoint(x: StoryField.sharedChip.x * size.width,
                              y: StoryField.sharedChip.y * size.height),
              radius: 0.55 * min(size.width, size.height),
              color: StoryPalette.warning,
              opacity: 0.28 * ripple * veilFade)
    }

    /// One soft anamorphic streak: a radial falloff squashed onto one axis, so
    /// it keeps the same edgeless gradient the pools use.
    private static func streak(_ ctx: inout GraphicsContext, center: CGPoint,
                               length: CGFloat, thinness: CGFloat, angle: Double,
                               color: Color, opacity: Double) {
        var layer = ctx
        layer.translateBy(x: center.x, y: center.y)
        layer.rotate(by: .radians(angle))
        layer.scaleBy(x: 1, y: thinness)
        let radius = length / 2
        let rect = CGRect(x: -radius, y: -radius, width: length, height: length)
        layer.fill(Path(ellipseIn: rect), with: .radialGradient(
            StoryGalaxy.softGradient(color, peak: opacity),
            center: .zero, startRadius: 0, endRadius: radius))
    }
}
