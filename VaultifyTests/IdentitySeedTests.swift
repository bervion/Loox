import XCTest
@testable import Vaultify

/// The pure onboarding identity seed builder.
final class IdentitySeedTests: XCTestCase {

    private func seed(_ name: String, email: String = "", fallback: String = "Me",
                      note: String = "", tag: String = "") -> VaultItem {
        IdentitySeed.make(displayName: name, email: email, fallback: fallback, note: note, tag: tag)
    }

    func testSeedUsesDisplayNameAsTitle() {
        XCTAssertEqual(seed("An").title, "An")
    }

    func testSeedFillsFullName() {
        XCTAssertEqual(seed("An").fields.first { $0.label == "Full Name" }?.value, "An")
    }

    func testSeedMarkedDefault() {
        XCTAssertTrue(seed("An").isDefaultIdentity)
    }

    func testSeedCategoryIsIdentity() {
        XCTAssertEqual(seed("An").category, .identity)
    }

    func testSeedFallbackOnBlank() {
        let item = seed("   ")
        XCTAssertEqual(item.title, "Me")
        XCTAssertEqual(item.fields.first { $0.label == "Full Name" }?.value, "Me")
    }

    func testSeedTrimsWhitespace() {
        XCTAssertEqual(seed("  An  ").title, "An")
    }

    // MARK: Starter-kit additions (email / note / tag)

    func testSeedFillsEmailWhenProvided() {
        XCTAssertEqual(seed("An", email: "an@example.com").fields.first { $0.label == "Email" }?.value,
                       "an@example.com")
    }

    func testSeedLeavesEmailBlankWhenEmpty() {
        XCTAssertEqual(seed("An").fields.first { $0.label == "Email" }?.value, "")
    }

    func testSeedAppendsNoteWhenProvided() {
        XCTAssertEqual(seed("An", note: "Welcome!").fields.first { $0.label == "Note" }?.value, "Welcome!")
    }

    func testSeedOmitsNoteWhenEmpty() {
        XCTAssertNil(seed("An").fields.first { $0.label == "Note" })
    }

    func testSeedAppliesTag() {
        XCTAssertEqual(seed("An", tag: "Starter Kit").tags, ["Starter Kit"])
    }

    func testSeedNoTagWhenEmpty() {
        XCTAssertTrue(seed("An").tags.isEmpty)
    }
}
