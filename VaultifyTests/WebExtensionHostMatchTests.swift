import XCTest
@testable import Vaultify

/// Every fill surface — the Safari popup, the OS AutoFill list, QuickType, and
/// shared credentials — scopes hosts through the same `HostMatch` rule: exact
/// or label-boundary parent/child, never a substring. A lookalike (phishing)
/// host must not surface a real login on ANY of them.
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

    func testOSAutoFillRejectsLookalikeHostsToo() {
        // The OS AutoFill matcher once accepted this pair via a substring
        // clause; a lookalike page then listed the real login under "For this
        // app". Both surfaces now share the strict rule.
        let item = login(url: "https://google.com")
        XCTAssertFalse(item.matchesAutoFill(serviceIdentifiers: ["evilgoogle.com"]))
        XCTAssertFalse(item.matchesAutoFill(serviceIdentifiers: ["google.com.evil.io"]))
        XCTAssertFalse(WebExtensionReader.hostMatches("evilgoogle.com", item: item))
        XCTAssertTrue(item.matchesAutoFill(serviceIdentifiers: ["accounts.google.com"]))
    }

    // MARK: - HostMatch vectors (the shared rule itself)

    func testTrailingDotAndCaseNormalize() {
        XCTAssertTrue(HostMatch.related("Google.com.", "google.com"))
        XCTAssertTrue(HostMatch.related("mail.google.com", "GOOGLE.COM."))
    }

    func testIPLiteralsRequireExactEquality() {
        XCTAssertTrue(HostMatch.related("192.168.1.10", "192.168.1.10"))
        // No label hierarchy on an address: a "subdomain of an IP" is a spoof.
        XCTAssertFalse(HostMatch.related("evil.192.168.1.10", "192.168.1.10"))
        XCTAssertFalse(HostMatch.related("192.168.1.10", "168.1.10"))
        XCTAssertTrue(HostMatch.related("::1", "::1"))
        XCTAssertFalse(HostMatch.related("fe80::1", "::1"))
    }

    func testSiblingSubdomainsStillShareTheParentSite() {
        // a.example.com vs b.example.com are not parent/child of each other,
        // but both relate to example.com — the rule is per stored host.
        XCTAssertFalse(HostMatch.related("a.example.com", "b.example.com"))
        XCTAssertTrue(HostMatch.related("a.example.com", "example.com"))
        XCTAssertTrue(HostMatch.related("b.example.com", "example.com"))
    }

    func testPunycodeHostsCompareInASCIIForm() {
        // URL.host yields punycode, so both sides arrive ASCII; lookalike
        // unicode confusables become distinct xn-- strings and never match.
        XCTAssertTrue(HostMatch.related("xn--80ak6aa92e.com", "xn--80ak6aa92e.com"))
        XCTAssertFalse(HostMatch.related("xn--80ak6aa92e.com", "apple.com"))
    }

    func testPublicSuffixOnlyStoredHostIsADocumentedLimitation() {
        // No public-suffix list ships in the matcher: a user who stores a bare
        // registrable suffix as their website opts into matching every site
        // under it. Documented, deliberate — not silently "fixed" here.
        XCTAssertTrue(HostMatch.related("evil.co.uk", "co.uk"))
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
