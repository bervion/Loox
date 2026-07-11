import XCTest
@testable import Vaultify

/// FieldKind wire-compat: adding a kind in a future version must never break an
/// older build decoding a synced/imported vault.
final class FieldKindDecodingTests: XCTestCase {

    func testKnownKindsRoundTrip() throws {
        for kind in FieldKind.allCases {
            let data = try JSONEncoder().encode(kind)
            let decoded = try JSONDecoder().decode(FieldKind.self, from: data)
            XCTAssertEqual(decoded, kind)
        }
    }

    func testUnknownKindFallsBackToText() throws {
        // A kind from a NEWER app version: the whole item must survive with the
        // field degraded to plain text, not fail decoding.
        let data = Data(#""hologram""#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(FieldKind.self, from: data), .text)
    }

    func testPhoneKindDecodes() throws {
        let data = Data(#""phone""#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(FieldKind.self, from: data), .phone)
    }
}
