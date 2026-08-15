import XCTest

/// Verifying walkthrough of the one-time story intro: unlocks the fixture
/// vault (the deliberate-lock gate persists across relaunch since the panic
/// fix, so every launch starts locked), then pages through all six beats,
/// exercising the beat-3 send tap and the hold-to-seal exit, saving a
/// screenshot per beat so the stage art can be reviewed frame by frame.
///
/// Every step ASSERTS: the story must actually appear after the unlock, each
/// page's frame must actually be on screen after its turn, and Home must
/// arrive after the seal. The first version of this rig was screenshots-only —
/// and kept passing for days while the fixture booted into the lock gate and
/// the story never mounted at all. A walkthrough that cannot fail is a camera,
/// not a test.
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

        unlockFixtureVault()

        // The story must mount once the session unlocks (the fixture launches
        // with `-ui-test-story`, so the completion flag is down).
        XCTAssertTrue(beatPage(1).waitForExistence(timeout: 10),
                      "story intro never appeared after the unlock")

        // Beat 1 (hook): let the entrance and the breathing dot settle.
        sleep(2)
        assertOnScreen(beat: 1)
        shoot("beat1-hook")

        pageDown()
        assertOnScreen(beat: 2)
        shoot("beat2-chaos")

        pageDown()
        assertOnScreen(beat: 3)
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
        assertOnScreen(beat: 4)
        shoot("beat4-turn")

        pageDown()
        assertOnScreen(beat: 5)
        shoot("beat5-sanctuary")

        pageDown()
        assertOnScreen(beat: 6)
        shoot("beat6-commitment")

        // Hold-to-seal: 0.9s hold on the CTA, then the exit burst.
        let cta = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88))
        cta.press(forDuration: 1.2)
        usleep(300_000)
        shoot("beat6-seal-burst")

        // The seal must actually land on Home (the settings button is Home
        // chrome that exists nowhere on the story or the lock screen).
        XCTAssertTrue(app.buttons["home.settings"].firstMatch
            .waitForExistence(timeout: 8),
                      "the seal did not arrive on Home")
        shoot("after-arrival")
    }

    /// Unlock ONLY when the deliberate-lock gate is up. The gate's persisted
    /// flag lives outside the per-process isolation, so the first launch after
    /// a panic-fixture run boots locked and the next boots straight into the
    /// story — the walkthrough must survive both orders. The story assertion
    /// right after this call is the real gate: whichever path ran, the story
    /// MUST be on screen or the test fails there.
    private func unlockFixtureVault() {
        let slide = app.buttons["lock.slide"].firstMatch
        guard slide.waitForExistence(timeout: 6) else { return }
        let knob = slide.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5))
        let end = slide.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        knob.press(forDuration: 0.1, thenDragTo: end)

        let password = app.secureTextFields.firstMatch
        XCTAssertTrue(password.waitForExistence(timeout: 8),
                      "password unlock did not appear after the slide")
        password.tap()
        // The fixture's seeded master password (UITestConfiguration.fixturePassword
        // app-side; UI test targets do not link app sources, so the literal is
        // the convention here — same as VaultEditSaveRelockUITests).
        password.typeText("vaultify-ui-test-password\n")
    }

    /// SwiftUI stamps a container's `accessibilityIdentifier` onto its child
    /// static texts (there is no "Other" wrapper element unless the page is
    /// regrouped), so the query targets the texts — firstMatch is the beat's
    /// title.
    private func beatPage(_ beat: Int) -> XCUIElement {
        app.staticTexts.matching(identifier: "story.beat.\(beat)").firstMatch
    }

    /// All six pages exist in the scroll column at all times (the VStack is
    /// not lazy), so EXISTENCE alone says nothing about the scroll. The real
    /// assertion is geometric: after a turn, the beat's title must sit inside
    /// the window — a walkthrough parked on the wrong page (or the wrong
    /// screen entirely) fails here.
    private func assertOnScreen(beat: Int) {
        let title = beatPage(beat)
        XCTAssertTrue(title.exists, "story.beat.\(beat) is not in the tree")
        let window = app.windows.firstMatch.frame
        let centre = CGPoint(x: title.frame.midX, y: title.frame.midY)
        XCTAssertTrue(window.contains(centre),
                      "beat \(beat) is not the page on screen (title \(title.frame))")
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
