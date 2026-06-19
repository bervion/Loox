import CoreMotion
import Foundation

/// Detects a deliberate device shake (privacy "panic" gesture) and fires `onShake` so the app
/// can lock the vault. Tuned to ignore everyday motion (walking, lifting, glancing): it needs
/// the acceleration magnitude to spike past a threshold at least twice within a short window,
/// then enforces a cooldown so one shake locks exactly once.
///
/// Lifecycle is caller-driven: `start` while unlocked + foreground, `stop` otherwise — the
/// accelerometer only runs when it's actually useful, so there's no idle battery cost.
@MainActor final class ShakeToLockService {
    private let motion = CMMotionManager()

    private var onShake: (() -> Void)?
    private var peaks: [Date] = []
    private var lastFire = Date.distantPast

    /// Total acceleration magnitude (in g, gravity included so rest ≈ 1.0) that counts as a
    /// shake peak. ~2.3 g clears normal handling/walking (< ~1.8 g) but a moderate shake meets.
    private let threshold = 2.3
    private let requiredPeaks = 2
    private let window: TimeInterval = 0.6
    private let cooldown: TimeInterval = 2

    var isRunning: Bool { motion.isAccelerometerActive }

    func start(onShake: @escaping () -> Void) {
        guard motion.isAccelerometerAvailable, !motion.isAccelerometerActive else { return }
        self.onShake = onShake
        peaks.removeAll()
        motion.accelerometerUpdateInterval = 1.0 / 30
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let a = data?.acceleration else { return }
            self.handle(magnitude: (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot())
        }
    }

    func stop() {
        if motion.isAccelerometerActive { motion.stopAccelerometerUpdates() }
        peaks.removeAll()
        onShake = nil
    }

    private func handle(magnitude: Double) {
        guard magnitude >= threshold else { return }
        let now = Date()
        guard now.timeIntervalSince(lastFire) > cooldown else { return }
        peaks.append(now)
        peaks.removeAll { now.timeIntervalSince($0) > window }
        if peaks.count >= requiredPeaks {
            peaks.removeAll()
            lastFire = now
            onShake?()
        }
    }
}
