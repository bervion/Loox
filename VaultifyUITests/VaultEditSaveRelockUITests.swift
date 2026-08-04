import XCTest

final class VaultEditSaveRelockUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        // No `-ui-test-tutorials`: an isolated launch marks every guided tour
        // answered, so the first-run scrim cannot swallow this test's taps.
        // A test that wants to drive a tour adds that argument back.
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

        openEditorFromOverflowMenu()

        let title = app.textFields["item.editor.title"]
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

    /// Opens the detail screen's overflow menu and activates its Edit action.
    ///
    /// The action carries `item.detail.edit`, but a SwiftUI toolbar `Menu`
    /// renders its content into UIKit's `_UIContextMenuActionsOnlyView`, and on
    /// Xcode 27 / iOS 26 those collection-view cells expose no identifier, no
    /// label and no children to XCUITest — queries through `buttons`,
    /// `menuItems`, `cells` and a raw `descendants` lookup all report
    /// non-existent, and `XCUIElement.snapshot()` returns an empty element.
    /// Position is the only handle the platform leaves. Tapping the first
    /// action and then proving the editor opened keeps that honest: reorder the
    /// menu and this fails loudly instead of silently pressing Pin or Trash.
    private func openEditorFromOverflowMenu() {
        let more = button("item.detail.more")
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()

        let editAction = app.collectionViews.cells.element(boundBy: 0)
        XCTAssertTrue(editAction.waitForExistence(timeout: 5))
        editAction.tap()

        XCTAssertTrue(
            app.textFields["item.editor.title"].waitForExistence(timeout: 5),
            "The first overflow-menu action must be Edit")
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
