import XCTest

/// Diagnostic walkthrough of the one-time story intro: pages through all six
/// beats, exercising the beat-3 send tap and the hold-to-seal exit, saving a
/// screenshot per beat so the stage art can be reviewed frame by frame.
/// Shot directory and app language come from the runner environment
/// (`TEST_RUNNER_STORY_SHOT_DIR`, `TEST_RUNNER_STORY_LANG`).
final class StoryIntroWalkthroughUITests: XCTestCase {
    private let app = XCUIApplication()

    private var shotDir: String {
        ProcessInfo.processInfo.environment["STORY_SHOT_DIR"] ?? "/tmp/story-shots"
    }
    private var language: String {
        ProcessInfo.processInfo.environment["STORY_LANG"] ?? "en"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-fixture", "vault-panic-restart",
            "-ui-test-story",
            "-ui-test-language", language,
            "-AppleLanguages", "(\(language))",
        ]
        app.launch()
    }

    func testWalkthroughCapturesEveryBeat() throws {
        try FileManager.default.createDirectory(
            atPath: shotDir, withIntermediateDirectories: true)

        // Beat 1 (hook): let the entrance and the breathing dot settle.
        sleep(2)
        shoot("beat1-hook")

        pageDown()
        shoot("beat2-chaos")

        pageDown()
        shoot("beat3-consequence")
        // The optional send tap: ripple + ghost copies.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)).tap()
        usleep(600_000)
        shoot("beat3-consequence-sent")

        // The signature moment: drag three quarters of a page toward the turn
        // and hold — scraps mid-flight into the ring while the canvas resolves.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        let mid = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.10))
        start.press(forDuration: 0.1, thenDragTo: mid,
                    withVelocity: .slow, thenHoldForDuration: 0.5)
        shoot("beat4-mid-gather")

        // Released past the halfway line, the page settles on the turn.
        usleep(900_000)
        shoot("beat4-turn")

        pageDown()
        shoot("beat5-sanctuary")

        pageDown()
        shoot("beat6-commitment")

        // Hold-to-seal: 0.9s hold on the CTA, then the exit burst.
        let cta = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88))
        cta.press(forDuration: 1.2)
        usleep(300_000)
        shoot("beat6-seal-burst")
        sleep(2)
        shoot("after-arrival")
    }

    private func pageDown() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        start.press(forDuration: 0.05, thenDragTo: end)
        usleep(900_000)
    }

    private func shoot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let url = URL(fileURLWithPath: shotDir).appendingPathComponent("\(name).png")
        try? png.write(to: url)
    }
}
