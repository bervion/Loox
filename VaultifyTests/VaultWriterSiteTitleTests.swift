import XCTest
@testable import Vaultify

final class VaultWriterSiteTitleTests: XCTestCase {

    func testUrlInputsReduceToBareHost() {
        let cases: [(input: String, expected: String)] = [
            ("https://example.com", "example.com"),
            ("https://example.com/login?next=/home", "example.com"),
            ("http://www.example.com", "example.com"),
            ("https://app.example.com/settings", "app.example.com"),
            ("example.com/login", "example.com"),
            ("EXAMPLE.com", "example.com"),
            ("https://example.com:8443/admin", "example.com"),
            ("  https://example.com  ", "example.com"),
        ]
        for c in cases {
            XCTAssertEqual(VaultWriter.siteTitle(c.input), c.expected, "input: \(c.input)")
        }
    }

    func testFreeTextPassesThroughUntouched() {
        // Manually typed names must not be mangled or lowercased.
        XCTAssertEqual(VaultWriter.siteTitle("My Bank"), "My Bank")
        XCTAssertEqual(VaultWriter.siteTitle("MyBank"), "MyBank")
        XCTAssertEqual(VaultWriter.siteTitle("localhost"), "localhost")
        XCTAssertEqual(VaultWriter.siteTitle(""), "")
    }
}
