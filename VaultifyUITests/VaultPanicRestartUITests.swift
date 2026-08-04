import XCTest

/// A deliberate lock must survive a force-quit: after Settings "Lock Now",
/// killing and relaunching the app may not fall back to the frictionless
/// unlock path — the slide-to-confirm requirement has to persist.
final class VaultPanicRestartUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        // No `-ui-test-tutorials`: an isolated launch marks every guided tour
        // answered, so the first-run scrim cannot swallow this test's taps.
        // A test that wants to drive a tour adds that argument back.
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-fixture", "vault-panic-restart",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()
    }

    func testDeliberateLockSurvivesRelaunch() throws {
        // The panic-restart fixture launches unlocked; reach Settings and lock
        // through the real control.
        let settings = button("home.settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()

        let lockNow = button("settings.lock-now")
        scrollUntilHittable(lockNow)
        lockNow.tap()

        // Deliberate lock shows the slide-to-confirm gate.
        XCTAssertTrue(button("lock.slide").waitForExistence(timeout: 5))

        // Force-quit and relaunch: the gate must still be there. Before the
        // persistence fix the app relaunched straight into the unlocked home.
        app.terminate()
        app.launch()

        XCTAssertTrue(button("lock.slide").waitForExistence(timeout: 10))
        XCTAssertFalse(button("home.settings").exists)
    }

    private func button(_ identifier: String) -> XCUIElement {
        app.buttons[identifier].firstMatch
    }

    private func scrollUntilHittable(_ element: XCUIElement) {
        for _ in 0..<6 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
}
