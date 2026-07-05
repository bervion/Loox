import XCTest
@testable import Vaultify

/// The quick-link registry persists in the Keychain across app updates — a
/// record written before `oneTime` existed must still decode (as false)
/// instead of dropping the whole registry (and with it the revoke tokens).
final class LooxLinkRecordCodecTests: XCTestCase {

    func testLegacyRecordWithoutOneTimeDecodesAsFalse() throws {
        let legacy = Data("""
        [{"shareId":"abc","revokeToken":"tok","itemId":"item-1",
          "createdAt":768000000,"expiresAt":768086400}]
        """.utf8)
        let records = try JSONDecoder().decode([LooxLinkRecord].self, from: legacy)
        XCTAssertEqual(records.count, 1)
        XCTAssertFalse(records[0].oneTime)
    }

    func testOneTimeRoundTrips() throws {
        let record = LooxLinkRecord(shareId: "abc", revokeToken: "tok", itemId: "item-1",
                                    createdAt: .now, expiresAt: .now.addingTimeInterval(300),
                                    oneTime: true)
        let data = try JSONEncoder().encode([record])
        let decoded = try JSONDecoder().decode([LooxLinkRecord].self, from: data)
        XCTAssertEqual(decoded[0].oneTime, true)
    }

    func testShareURLCarriesFragmentOnlyOneTimeHint() throws {
        let url = try XCTUnwrap(LooxLinkConfig.shareURL(shareId: "id123", fragmentKey: "KEY",
                                                        oneTime: true))
        XCTAssertTrue(url.absoluteString.hasSuffix("/s/id123#k=KEY&o=1"))
        // The hint must live in the fragment — never in the query/path the
        // server sees.
        XCTAssertNil(URLComponents(url: url, resolvingAgainstBaseURL: false)?.query)
        let plain = try XCTUnwrap(LooxLinkConfig.shareURL(shareId: "id123", fragmentKey: "KEY"))
        XCTAssertTrue(plain.absoluteString.hasSuffix("/s/id123#k=KEY"))
    }
}
