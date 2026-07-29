import SwiftUI

/// Whether the accelerometer should be running right now.
///
/// A pure decision so the answer depends on the app's STATE, never on which screen happens to be
/// on top. Shake-to-lock was previously armed from a view's `onAppear`/`onDisappear`, and on
/// iPhone the tab shell is the root of a `UINavigationController` — so every push (an item,
/// Settings, a Watchtower category) sent that view through `viewDidDisappear` and tore the
/// detector down. The panic gesture died exactly when the user had a secret on screen.
nonisolated enum ShakeToLockPolicy {
    static func shouldMonitor(enabled: Bool, isUnlocked: Bool, isActive: Bool, isUITest: Bool) -> Bool {
        guard !isUITest else { return false }
        // Locked or backgrounded, the gesture has nothing to protect, so the accelerometer stays
        // off and costs no battery — the reason it was lifecycle-driven in the first place.
        return enabled && isUnlocked && isActive
    }
}

/// Arms shake-to-lock for as long as the vault is unlocked and frontmost.
///
/// Applied at the SwiftUI root, ABOVE the UIKit navigation shell, and driven only by state
/// changes — it deliberately has no `onDisappear` teardown, because being covered by a pushed
/// screen is not a reason to disarm a panic gesture.
struct ShakeToLockMonitor: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var detector = ShakeToLockService()

    private var shouldMonitor: Bool {
        ShakeToLockPolicy.shouldMonitor(enabled: env.settings.shakeToLock,
                                        isUnlocked: env.session.state == .unlocked,
                                        isActive: scenePhase == .active,
                                        isUITest: env.uiTestConfiguration.isEnabled)
    }

    func body(content: Content) -> some View {
        content
            .onAppear { sync() }
            .onChange(of: shouldMonitor) { _, _ in sync() }
    }

    private func sync() {
        guard shouldMonitor else {
            detector.stop()
            return
        }
        detector.start {
            Haptics.success()
            env.session.lock(deliberate: true)
        }
    }
}

extension View {
    /// Arm the privacy panic gesture. Apply once, at the app root.
    func shakeToLockMonitor() -> some View { modifier(ShakeToLockMonitor()) }
}
