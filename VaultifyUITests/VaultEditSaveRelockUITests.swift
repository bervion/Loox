import XCTest

final class VaultEditSaveRelockUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-fixture", "vault-edit-save-relock",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()
    }

    func testEditSaveLockAndUnlockPreservesItem() throws {
        unlockWithPassword()

        let item = button("vault.item.ui-test-login.all")
        XCTAssertTrue(item.waitForExistence(timeout: 15))
        item.tap()

        let more = button("item.detail.more")
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()

        let edit = button("item.detail.edit")
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()

        let title = app.textFields["item.editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 32))
        title.typeText("Acme Production")
        button("item.editor.save").tap()

        XCTAssertEqual(element("item.detail.title").label, "Acme Production")
        button("nav.back").tap()

        let settings = button("home.settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()

        let lockNow = button("settings.lock-now")
        scrollUntilHittable(lockNow)
        lockNow.tap()

        unlockWithPassword()

        let persistedItem = button("vault.item.ui-test-login.all")
        XCTAssertTrue(persistedItem.waitForExistence(timeout: 10))
        persistedItem.tap()
        XCTAssertEqual(element("item.detail.title").label, "Acme Production")
    }

    private func unlockWithPassword() {
        let slider = button("lock.slide")
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        // XCTest's tap() sends a physical touch; it does not invoke SwiftUI's
        // accessibilityAction. Drag the production control while still locating it
        // through its VoiceOver-compatible button contract.
        let slideStart = slider.coordinate(
            withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5)
        )
        let slideEnd = slider.coordinate(
            withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)
        )
        slideStart.press(forDuration: 0.1, thenDragTo: slideEnd)

        let password = app.secureTextFields["lock.password"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        password.tap()
        password.typeText("vaultify-ui-test-password")
        button("lock.submit").tap()
        XCTAssertTrue(button("vault.item.ui-test-login.all").waitForExistence(timeout: 10))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
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
