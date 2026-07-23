//
//  LooxLaunchController.swift
//  Vaultify
//
//  Drives the button-triggered scene transition: whatever the loop is
//  doing, the animation is frozen and smoothly reverted to the logo,
//  squeezes for anticipation, then the six brand circles surge outward
//  to flood the screen and reveal the next scene. Haptic taps land on
//  the same keyframes so the gesture "feels" the animation.
//

import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum LooxLaunchPhase: Equatable {
    case idle
    case launching(start: Date, frozenLoopTime: TimeInterval)
    case presented
}

final class LooxLaunchController: ObservableObject {
    @Published var phase: LooxLaunchPhase = .idle

    /// Origin of the landing loop. Reset on dismiss so the animation
    /// always greets the user again from the resting logo.
    @Published var loopEpoch: Date = .now

    func loopTime(at date: Date) -> TimeInterval {
        max(0, date.timeIntervalSince(loopEpoch))
            .truncatingRemainder(dividingBy: LooxTimeline.duration)
    }

    func memojiRestartKeys(at date: Date) -> [Int] {
        let elapsed = date.timeIntervalSince(loopEpoch)
        return LooxTimeline.sceneStarts.map {
            Int(((elapsed - $0) / LooxTimeline.duration).rounded(.down))
        }
    }

    func press() {
        guard case .idle = phase else { return }
        let now = Date.now
        phase = .launching(start: now, frozenLoopTime: loopTime(at: now))
        LooxLaunchHaptics.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + LooxLaunchTimeline.total) { [weak self] in
            guard case .launching = self?.phase else { return }
            self?.phase = .presented
        }
    }

    func dismiss() {
        loopEpoch = .now
        withAnimation(.easeInOut(duration: 0.35)) {
            phase = .idle
        }
    }
}

/// Impact taps aligned with the launch keyframes: acknowledge the press,
/// mark the logo snapping back, punch the burst, and ease into the reveal.
/// macOS has no impact haptics — the launch animation simply plays silent.
enum LooxLaunchHaptics {
    #if canImport(UIKit)
    static func play() {
        let soft = UIImpactFeedbackGenerator(style: .soft)
        let light = UIImpactFeedbackGenerator(style: .light)
        let medium = UIImpactFeedbackGenerator(style: .medium)
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        let rigid = UIImpactFeedbackGenerator(style: .rigid)
        [soft, light, medium, heavy, rigid].forEach { $0.prepare() }

        let beats: [(TimeInterval, UIImpactFeedbackGenerator, CGFloat)] = [
            (0.00, soft, 0.6),    // press acknowledged
            (0.35, light, 0.7),   // logo re-formed
            (0.44, medium, 0.9),  // squash bounce
            (0.90, light, 0.5),   // spiral ticks, rhythm tightening…
            (1.08, light, 0.65),
            (1.22, rigid, 0.75),
            (1.36, heavy, 1.0),   // slam into the dot
            // 40 ms of silence — the held breath before the bloom
            (1.46, rigid, 0.9),   // the disc rips open
            (1.72, soft, 0.5),    // settle into the new scene
        ]
        for (delay, generator, intensity) in beats {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                generator.impactOccurred(intensity: intensity)
            }
        }
    }
    #else
    static func play() {}
    #endif
}
