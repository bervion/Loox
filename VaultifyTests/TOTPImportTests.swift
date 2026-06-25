import XCTest
@testable import Vaultify

/// `TOTPImport.draftLogin(from:)` parsing for the otpauth:// 2FA setup deep link.
final class TOTPImportTests: XCTestCase {

    func testStandardOTPAuthWithIssuer() throws {
        let url = URL(string: "otpauth://totp/GitHub:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub")!
        let item = try XCTUnwrap(TOTPImport.draftLogin(from: url))
        XCTAssertEqual(item.category, .login)
        XCTAssertEqual(item.title, "GitHub")
        XCTAssertEqual(item.usernameField?.value, "alice@example.com")
        XCTAssertEqual(item.totpField?.value, url.absoluteString)
    }

    func testLabelOnlyUsesAccountAsTitle() throws {
        let url = URL(string: "otpauth://totp/alice@example.com?secret=JBSWY3DPEHPK3PXP")!
        let item = try XCTUnwrap(TOTPImport.draftLogin(from: url))
        XCTAssertEqual(item.title, "alice@example.com")
        XCTAssertEqual(item.usernameField?.value, "alice@example.com")
    }

    func testIssuerQueryWinsOverLabelPrefix() throws {
        let url = URL(string: "otpauth://totp/Old:bob?secret=JBSWY3DPEHPK3PXP&issuer=NewCorp")!
        let item = try XCTUnwrap(TOTPImport.draftLogin(from: url))
        XCTAssertEqual(item.title, "NewCorp")
        XCTAssertEqual(item.usernameField?.value, "bob")
    }

    func testNonOTPAuthURLReturnsNil() {
        XCTAssertNil(TOTPImport.draftLogin(from: URL(string: "https://example.com")!))
    }

    func testMissingSecretReturnsNil() {
        XCTAssertNil(TOTPImport.draftLogin(from: URL(string: "otpauth://totp/NoSecret")!))
    }
}
