import XCTest
@testable import Vaultify

/// Phase 3: the pure onboarding identity seed builder.
final class IdentitySeedTests: XCTestCase {

    func testSeedUsesDisplayNameAsTitle() {
        let item = IdentitySeed.make(displayName: "An", fallback: "Me")
        XCTAssertEqual(item.title, "An")
    }

    func testSeedFillsFullName() {
        let item = IdentitySeed.make(displayName: "An", fallback: "Me")
        let fullName = item.fields.first { $0.label == "Full Name" }
        XCTAssertEqual(fullName?.value, "An")
    }

    func testSeedMarkedDefault() {
        let item = IdentitySeed.make(displayName: "An", fallback: "Me")
        XCTAssertTrue(item.isDefaultIdentity)
    }

    func testSeedCategoryIsIdentity() {
        let item = IdentitySeed.make(displayName: "An", fallback: "Me")
        XCTAssertEqual(item.category, .identity)
    }

    func testSeedFallbackOnBlank() {
        let item = IdentitySeed.make(displayName: "   ", fallback: "Me")
        XCTAssertEqual(item.title, "Me")
        XCTAssertEqual(item.fields.first { $0.label == "Full Name" }?.value, "Me")
    }

    func testSeedTrimsWhitespace() {
        let item = IdentitySeed.make(displayName: "  An  ", fallback: "Me")
        XCTAssertEqual(item.title, "An")
    }
}
