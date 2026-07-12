//
//  LooxCloudAnimationView.swift
//  Vaultify
//
//  Renders the looping brand animation: the Loox cloud unfolds into an
//  orbiting cluster of capability bubbles, cycles through themes, and
//  gathers back into the logo. All state is derived from the timeline in
//  LooxAnimationEngine, driven by TimelineView at display refresh rate.
//

import SwiftUI

struct LooxCloudAnimationView: View {
    @ObservedObject var controller: LooxLaunchController

    var body: some View {
        TimelineView(.animation) { context in
            let now = context.date
            GeometryReader { geo in
                let scale = min(geo.size.width / LooxCanvas.size.width,
                                geo.size.height / LooxCanvas.size.height)
                let origin = CGPoint(
                    x: (geo.size.width - LooxCanvas.size.width * scale) / 2,
                    y: (geo.size.height - LooxCanvas.size.height * scale) / 2
                )
                let center = centerFrame(at: now)
                let squash = groupSquash(at: now)
                let canvasCenter = CGPoint(x: origin.x + LooxCanvas.center.x * scale,
                                           y: origin.y + LooxCanvas.center.y * scale)

                ZStack {
                    // Fake motion blur: ghost copies of the two leading
                    // discs, sampled a beat in the past, drawn underneath.
                    ForEach([5, 2], id: \.self) { i in
                        ForEach(Array(ghostFrames(index: i, at: now).enumerated()), id: \.offset) { _, ghost in
                            LooxOrbLayer(slot: i, frame: ghost, scale: scale, origin: origin)
                        }
                    }

                    // Back lobes / bubbles. Slot 5 renders above the center
                    // disc, matching how the big mail bubble overlaps the
                    // avatar on the iCloud landing page.
                    ForEach(0..<5) { i in
                        LooxOrbLayer(slot: i, frame: orbFrame(index: i, at: now), scale: scale, origin: origin)
                    }
                    LooxCenterDisc(frame: center, scale: scale, origin: origin,
                                   restartKeys: controller.memojiRestartKeys(at: now))
                    LooxOrbLayer(slot: 5, frame: orbFrame(index: 5, at: now), scale: scale, origin: origin)
                    LooxGlowLayer(opacity: center.glowOpacity, scale: scale, origin: origin)
                    LooxStarLayer(frame: center, scale: scale, origin: origin)

                    // The final disc of the story: erupts from the frozen
                    // dot, its brand gradient dissolving into the theme
                    // background — it IS the destination screen.
                    let bloom = bloomState(at: now)
                    if bloom.diameter > 0 {
                        ZStack {
                            Circle().fill(Color(.systemBackground))
                            Circle()
                                .fill(LinearGradient(colors: [.looxBlue, .looxDeep],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .opacity(bloom.gradientOpacity)
                        }
                        .frame(width: bloom.diameter * scale, height: bloom.diameter * scale)
                        .position(canvasCenter)
                    }
                }
                .scaleEffect(x: squash.x, y: squash.y,
                             anchor: UnitPoint(x: canvasCenter.x / max(geo.size.width, 1),
                                               y: canvasCenter.y / max(geo.size.height, 1)))
                .opacity(overlayOpacity(at: now))
            }
        }
        .accessibilityHidden(true)
    }

    private func orbFrame(index i: Int, at now: Date) -> LooxOrbFrame {
        if case .launching(let start, let frozen) = controller.phase {
            return LooxLaunchResolver.orbFrame(index: i, elapsed: now.timeIntervalSince(start), frozenLoopTime: frozen)
        }
        return LooxResolver.orbFrame(index: i, time: controller.loopTime(at: now))
    }

    private func centerFrame(at now: Date) -> LooxCenterFrame {
        if case .launching(let start, let frozen) = controller.phase {
            return LooxLaunchResolver.centerFrame(elapsed: now.timeIntervalSince(start), frozenLoopTime: frozen)
        }
        return LooxResolver.centerFrame(time: controller.loopTime(at: now))
    }

    private func overlayOpacity(at now: Date) -> Double {
        if case .launching(let start, _) = controller.phase {
            return LooxLaunchResolver.overlayOpacity(elapsed: now.timeIntervalSince(start))
        }
        return 1
    }

    private func bloomState(at now: Date) -> (diameter: CGFloat, gradientOpacity: Double) {
        if case .launching(let start, _) = controller.phase {
            return LooxLaunchResolver.bloomState(elapsed: now.timeIntervalSince(start))
        }
        return (0, 1)
    }

    private func groupSquash(at now: Date) -> (x: CGFloat, y: CGFloat) {
        if case .launching(let start, _) = controller.phase {
            return LooxLaunchResolver.groupSquash(elapsed: now.timeIntervalSince(start))
        }
        return (1, 1)
    }

    private func ghostFrames(index i: Int, at now: Date) -> [LooxOrbFrame] {
        if case .launching(let start, let frozen) = controller.phase {
            return LooxLaunchResolver.ghostFrames(index: i, elapsed: now.timeIntervalSince(start), frozenLoopTime: frozen)
        }
        return []
    }
}

/// One of the six circles that morph between cloud lobe and icon bubble.
private struct LooxOrbLayer: View {
    let slot: Int
    let frame: LooxOrbFrame
    let scale: CGFloat
    let origin: CGPoint

    var body: some View {
        let d = frame.diameter * scale
        ZStack {
            // Icon bubble (cluster look), crossfading between themes.
            ZStack {
                if frame.crossfade < 1 {
                    LooxBubble(spec: currentSpec(frame.fromTheme), diameter: d)
                        .opacity(1 - frame.crossfade)
                }
                if frame.crossfade > 0 {
                    LooxBubble(spec: currentSpec(frame.toTheme), diameter: d)
                        .opacity(frame.crossfade)
                }
            }
            .compositingGroup()
            .opacity(frame.bubbleOpacity)
            .shadow(color: .black.opacity(0.16 * frame.shadowOpacity), radius: d * 0.10, y: d * 0.05)

            // Brand gradient veil (logo look).
            Circle()
                .fill(gradient.linear)
                .opacity(frame.logoOpacity)
        }
        .frame(width: d, height: d)
        .position(position)
    }

    private func currentSpec(_ theme: Int) -> LooxOrbitSpec {
        LooxTheme.all[theme].slots[slot]
    }

    private var gradient: LooxLogoGradient {
        LooxCanvas.logoGradients[slot]
    }

    private var position: CGPoint {
        CGPoint(x: origin.x + frame.center.x * scale,
                y: origin.y + frame.center.y * scale)
    }
}

/// A single capability bubble: solid gradient disc with white glyph, or
/// white disc with colored glyph — mirroring the iCloud icon treatments.
private struct LooxBubble: View {
    let spec: LooxOrbitSpec
    let diameter: CGFloat

    var body: some View {
        ZStack {
            switch spec.style {
            case .solid(let colors):
                Circle().fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: spec.symbol)
                    .font(.system(size: diameter * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            case .glyphOnWhite(let tint):
                Circle().fill(.white)
                Image(systemName: spec.symbol)
                    .font(.system(size: diameter * 0.44, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
    }
}

/// Pastel identity disc at the cluster's heart.
private struct LooxCenterDisc: View {
    let frame: LooxCenterFrame
    let scale: CGFloat
    let origin: CGPoint
    /// Per-theme loop counters; a change rewinds that theme's Memoji clip.
    let restartKeys: [Int]

    var body: some View {
        let d = frame.diameter * scale
        let from = LooxTheme.all[frame.fromTheme].tint
        let to = LooxTheme.all[frame.toTheme].tint
        ZStack {
            ZStack {
                Circle().fill(from).opacity(1 - frame.crossfade)
                Circle().fill(to).opacity(frame.crossfade)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.12 * frame.tintOpacity), radius: d * 0.08, y: d * 0.04)

            // All three Memoji clips stay mounted and looping; only their
            // opacity changes, so theme swaps never hitch on player startup.
            // Each head is zoomed slightly, nudged down to sit optically
            // centered, and clipped to the disc so long hair stays inside.
            ForEach(0..<LooxTheme.all.count, id: \.self) { k in
                let theme = LooxTheme.all[k]
                LooxMemojiPlayerView(resourceName: theme.memoji, restartKey: restartKeys[k])
                    .frame(width: d * theme.memojiZoom, height: d * theme.memojiZoom)
                    .offset(y: d * theme.memojiDrop)
                    .frame(width: d, height: d)
                    .clipShape(Circle())
                    .opacity(memojiOpacity(theme: k))
            }
        }
        .opacity(frame.tintOpacity)
        .frame(width: d, height: d)
        .position(x: origin.x + LooxCanvas.center.x * scale,
                  y: origin.y + LooxCanvas.center.y * scale)
    }

    private func memojiOpacity(theme k: Int) -> Double {
        if k == frame.fromTheme && k == frame.toTheme { return 1 }
        if k == frame.fromTheme { return 1 - frame.crossfade }
        if k == frame.toTheme { return frame.crossfade }
        return 0
    }
}

/// Radial white highlight from the brand mark, visible in the logo state.
private struct LooxGlowLayer: View {
    let opacity: Double
    let scale: CGFloat
    let origin: CGPoint

    var body: some View {
        let d = LooxCanvas.glowDiameter * scale
        Circle()
            .fill(RadialGradient(
                colors: [Color.white.opacity(opacity), Color.white.opacity(0)],
                center: .center, startRadius: 0, endRadius: d / 2))
            .frame(width: d, height: d)
            .position(x: origin.x + LooxCanvas.glowCenter.x * scale,
                      y: origin.y + LooxCanvas.glowCenter.y * scale)
    }
}

/// The white four-point sparkle, shared between logo and cluster states.
private struct LooxStarLayer: View {
    let frame: LooxCenterFrame
    let scale: CGFloat
    let origin: CGPoint

    var body: some View {
        let d = frame.starDiameter * scale
        LooxStarShape()
            .fill(.white)
            .rotationEffect(.degrees(frame.starRotation))
            .opacity(frame.starOpacity)
            .frame(width: d, height: d)
            .position(x: origin.x + LooxCanvas.center.x * scale,
                      y: origin.y + LooxCanvas.center.y * scale)
    }
}

#Preview {
    LooxCloudAnimationView(controller: LooxLaunchController())
        .frame(width: 320, height: 280)
}
