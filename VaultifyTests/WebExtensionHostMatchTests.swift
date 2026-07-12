import XCTest
@testable import Vaultify

/// The extension popup must scope its login listing with a stricter host
/// matcher than OS AutoFill: no substring clause, so a lookalike (phishing)
/// host never surfaces a real login's title and username.
final class WebExtensionHostMatchTests: XCTestCase {

    func testLookalikeHostDoesNotMatch() {
        let item = login(url: "https://google.com")
        XCTAssertFalse(WebExtensionReader.hostMatches("evilgoogle.com", item: item))
        XCTAssertFalse(WebExtensionReader.hostMatches("google.com.evil.io", item: item))
        XCTAssertFalse(WebExtensionReader.hostMatches("oogle.com", item: item))
    }

    func testExactHostAndTrueSubdomainMatch() {
        let item = login(url: "https://google.com")
        XCTAssertTrue(WebExtensionReader.hostMatches("google.com", item: item))
        XCTAssertTrue(WebExtensionReader.hostMatches("mail.google.com", item: item))
    }

    func testStoredSubdomainStaysWithinItsSite() {
        let item = login(url: "https://accounts.google.com")
        XCTAssertTrue(WebExtensionReader.hostMatches("accounts.google.com", item: item))
        XCTAssertTrue(WebExtensionReader.hostMatches("google.com", item: item),
                      "the parent of a stored subdomain is the same site")
        XCTAssertFalse(WebExtensionReader.hostMatches("evilaccounts.google.com.evil.io", item: item))
    }

    func testAutoFillSubstringLooseningIsNotInherited() {
        // The OS AutoFill matcher accepts this pair via its substring clause
        // (fine in the QuickType context); the popup matcher must not.
        let item = login(url: "https://google.com")
        XCTAssertTrue(item.matchesAutoFill(serviceIdentifiers: ["evilgoogle.com"]))
        XCTAssertFalse(WebExtensionReader.hostMatches("evilgoogle.com", item: item))
    }

    func testEmptyAndCasedHosts() {
        let item = login(url: "https://Login.Example.com")
        XCTAssertFalse(WebExtensionReader.hostMatches("", item: item))
        XCTAssertFalse(WebExtensionReader.hostMatches("   ", item: item))
        XCTAssertTrue(WebExtensionReader.hostMatches("login.example.com", item: item))
        XCTAssertTrue(WebExtensionReader.hostMatches("example.com", item: item))
    }

    func testMultiWebsiteItemMatchesAnyOfItsHosts() {
        let item = VaultItem(category: .login, title: "Example", fields: [
            DynamicField(label: "Website", kind: .url, value: "https://example.com"),
            DynamicField(label: "Website", kind: .url, value: "https://example.org"),
        ])
        XCTAssertTrue(WebExtensionReader.hostMatches("example.org", item: item))
        XCTAssertTrue(WebExtensionReader.hostMatches("www.example.com", item: item))
        XCTAssertFalse(WebExtensionReader.hostMatches("example.net", item: item))
    }

    private func login(url: String) -> VaultItem {
        VaultItem(category: .login, title: "Example",
                  fields: [DynamicField(label: "Website", kind: .url, value: url)])
    }
}
