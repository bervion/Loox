import XCTest
@testable import Vaultify

/// Shake-to-lock is a panic gesture: it has to work at the moment the user most wants it, which
/// is precisely when a secret is on screen — inside an item, in Settings, anywhere but the tab
/// root. It used to be armed from a view's `onAppear`/`onDisappear`, and because the iPhone tab
/// shell is the root of a `UINavigationController`, every push tore it down. These tests pin the
/// replacement: arming depends on app STATE only, so no screen can disarm it.
final class ShakeToLockPolicyTests: XCTestCase {

    private func monitor(enabled: Bool = true, unlocked: Bool = true,
                         active: Bool = true, uiTest: Bool = false) -> Bool {
        ShakeToLockPolicy.shouldMonitor(enabled: enabled, isUnlocked: unlocked,
                                        isActive: active, isUITest: uiTest)
    }

    func testArmedWheneverUnlockedAndFrontmost() {
        XCTAssertTrue(monitor())
    }

    func testEachGuardCanDisarmOnItsOwn() {
        XCTAssertFalse(monitor(enabled: false), "opt-in setting off")
        XCTAssertFalse(monitor(unlocked: false), "nothing to protect while locked")
        XCTAssertFalse(monitor(active: false), "no accelerometer cost in the background")
        XCTAssertFalse(monitor(uiTest: true), "UI tests must not trip the panic gesture")
    }

    func testDecisionTakesNoScreenOrNavigationInput() {
        // The regression in one assertion: the policy's inputs are app state, full stop. There is
        // no tab, route, presented sheet or navigation depth to pass, so "works on Home only"
        // has no way to be expressed. If someone adds such a parameter, this stops compiling.
        let armed = ShakeToLockPolicy.shouldMonitor(enabled: true, isUnlocked: true,
                                                    isActive: true, isUITest: false)
        XCTAssertTrue(armed)
    }

    func testDisarmingIsNotStickyAcrossStateChanges() {
        // Backgrounding disarms; returning to the foreground must arm again. The old wiring could
        // stop and never restart, which is what made the gesture dead for the rest of a session.
        XCTAssertTrue(monitor(active: true))
        XCTAssertFalse(monitor(active: false))
        XCTAssertTrue(monitor(active: true))
    }
}
