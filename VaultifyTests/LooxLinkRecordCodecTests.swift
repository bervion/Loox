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

    func testLegacyRecordWithoutShortFieldsDecodesAsNil() throws {
        let legacy = Data("""
        [{"shareId":"abc","revokeToken":"tok","itemId":"item-1",
          "createdAt":768000000,"expiresAt":768086400,"oneTime":true}]
        """.utf8)
        let records = try JSONDecoder().decode([LooxLinkRecord].self, from: legacy)
        XCTAssertNil(records[0].shortURLWithoutFragment)
        XCTAssertNil(records[0].shortDomainID)
    }

    func testShortMetadataRoundTripsWithoutFragment() throws {
        let record = LooxLinkRecord(shareId: "abc", revokeToken: "tok", itemId: "item-1",
                                    createdAt: .now, expiresAt: .now.addingTimeInterval(300),
                                    shortURLWithoutFragment: "https://loox.pw/aB7kQ",
                                    shortDomainID: "short-pw")
        let data = try JSONEncoder().encode([record])
        // The persisted bytes must never contain a fragment marker — the
        // working link (fragment = content key) is transient by design.
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("#"))
        let decoded = try JSONDecoder().decode([LooxLinkRecord].self, from: data)
        XCTAssertEqual(decoded[0].shortURLWithoutFragment, "https://loox.pw/aB7kQ")
        XCTAssertEqual(decoded[0].shortDomainID, "short-pw")
    }

    func testComposedShortURLReattachesWholeFragment() throws {
        let canonical = try XCTUnwrap(LooxLinkConfig.shareURL(shareId: "id123", fragmentKey: "KEY",
                                                              oneTime: true))
        let base = try XCTUnwrap(URL(string: "https://loox.pw/aB7kQ"))
        let full = try XCTUnwrap(LooxLinkConfig.composedShortURL(base: base, canonicalURL: canonical))
        // The whole fragment survives — the one-time hint included, not just
        // the key — and nothing of it appears outside the fragment.
        XCTAssertEqual(full.absoluteString, "https://loox.pw/aB7kQ#k=KEY&o=1")
    }

    func testComposedShortURLRefusesFragmentlessCanonical() {
        let base = URL(string: "https://loox.pw/aB7kQ")!
        let canonical = URL(string: "https://s.looxpassword.com/s/id123")!
        XCTAssertNil(LooxLinkConfig.composedShortURL(base: base, canonicalURL: canonical))
    }

    func testCreateResponseDecodesWithAndWithoutShortenToken() throws {
        let without = Data(#"{"share_id":"a","revoke_token":"r","expires_at":1}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(LooxLinkCreateResponse.self, from: without).shortenToken)
        let with = Data(#"{"share_id":"a","revoke_token":"r","expires_at":1,"shorten_token":"s"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(LooxLinkCreateResponse.self, from: with).shortenToken, "s")
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
