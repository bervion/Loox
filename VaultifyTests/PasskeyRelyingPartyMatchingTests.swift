import XCTest
@testable import Vaultify

final class PasskeyRelyingPartyMatchingTests: XCTestCase {
    func testRelyingPartyMatchingIsConservative() {
        let item = login(url: "https://login.Example.com/account")

        XCTAssertTrue(item.matchesRelyingParty("example.com"))
        XCTAssertTrue(item.matchesRelyingParty("LOGIN.example.com"))
        XCTAssertFalse(item.matchesRelyingParty("notexample.com"))
        XCTAssertFalse(item.matchesRelyingParty("ample.com"))
        XCTAssertFalse(item.matchesRelyingParty(""))
    }

    func testExactHostAndMalformedURLCases() {
        XCTAssertTrue(login(url: "example.com").matchesRelyingParty("example.com"))
        XCTAssertFalse(login(url: "notexample.com").matchesRelyingParty("example.com"))
        XCTAssertFalse(login(url: "").matchesRelyingParty("example.com"))
    }

    func testPunycodeHostMatchesLowercasedRelyingParty() {
        let item = login(url: "https://xn--bcher-kva.example")

        XCTAssertTrue(item.matchesRelyingParty("xn--bcher-kva.example"))
        XCTAssertFalse(item.matchesRelyingParty("bcher-kva.example"))
    }

    private func login(url: String) -> VaultItem {
        VaultItem(category: .login, title: "Example",
                  fields: [DynamicField(label: "Website", kind: .url, value: url)])
    }
}
