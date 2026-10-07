import XCTest

/// Uses sealed synthetic local records. No recipient confirmation or mailbox
/// delivery result is inferred from these navigation/mutation assertions.
final class PrivateEmailMemberUXUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["-ui-testing", "-ui-test-fixture", "private-email-member-ux",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    func testUnlinkOneServicePreservesOtherLoginAndForwardingAddress() throws {
        scrollTo("Linked services")
        tap("Linked services")
        XCTAssertTrue(app.staticTexts["Facebook"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Gmail"].exists)
        tap("Facebook")
        openUnlinkConfirmation()
        XCTAssertTrue(app.staticTexts["This removes the private email from this vault item. Forwarding and the service account stay unchanged."].waitForExistence(timeout: 5))
        capture("linked-service-unlink-confirmation")
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        } else {
            // Native iOS 26 popover confirmations omit the Cancel row and
            // decline by tapping outside the popover instead.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.9)).tap()
        }
        XCTAssertTrue(app.buttons["Open login"].exists)
        openUnlinkConfirmation()
        let confirm = try XCTUnwrap(app.buttons.matching(identifier: "Unlink")
            .allElementsBoundByIndex.last(where: { $0.isHittable }))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Gmail"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Facebook"].exists)
        tap("Gmail")
        tap("Open login")
        XCTAssertTrue(app.staticTexts["quality-user"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["original@example.invalid"].exists)
        capture("linked-service-other-login-preserved")
    }

    func testRecipientIsReadableInDetailAndHideConcealsIt() throws {
        scrollTo("Inbox details")
        tap("Inbox details")
        XCTAssertTrue(app.staticTexts["quality-recipient@example.invalid"].waitForExistence(timeout: 5))
        tap("Hide email")
        XCTAssertFalse(app.staticTexts["quality-recipient@example.invalid"].exists)
        XCTAssertTrue(app.buttons["Show email"].exists)
        tap("Show email")
        XCTAssertTrue(app.staticTexts["quality-recipient@example.invalid"].exists)
        capture("recipient-detail-revealed")
    }

    func testMemberTilesOpenDedicatedDestinations() throws {
        app.buttons["ui-test.member"].tap()
        scrollTo("Share Links")
        tap("Share Links")
        XCTAssertTrue(app.staticTexts["No links on this device"].waitForExistence(timeout: 5))
        capture("member-links-destination")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        scrollTo("Send to Browser")
        tap("Send to Browser")
        XCTAssertTrue(app.staticTexts["No browser attempts on this device"].waitForExistence(timeout: 5))
        capture("member-browser-destination")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        scrollTo("Family")
        tap("Family")
        XCTAssertTrue(app.navigationBars["Family"].waitForExistence(timeout: 5))
        capture("member-family-destination")
    }

    private func tap(_ label: String) {
        let element = app.buttons[label].firstMatch
        if element.waitForExistence(timeout: 5) { element.tap(); return }
        let text = app.staticTexts[label].firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5), "Missing control \(label)")
        text.tap()
    }

    private func openUnlinkConfirmation() {
        tap("Manage linked service")
        // The iOS 26 native SwiftUI Menu has no labelled descendants in
        // XCUITest. Its single action is addressed through the native cell;
        // the following confirmation assertion proves it is Unlink.
        let unlinkAction = app.collectionViews.cells.element(boundBy: 0)
        XCTAssertTrue(unlinkAction.waitForExistence(timeout: 5))
        unlinkAction.tap()
    }

    private func scrollTo(_ label: String) {
        for _ in 0..<6 {
            if app.buttons[label].firstMatch.isHittable || app.staticTexts[label].firstMatch.isHittable { return }
            app.swipeUp()
        }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
