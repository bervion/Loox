import XCTest
@testable import Vaultify

/// Unit tests for `DeviceIconMapping.icon(forModel:)` — the Profile Devices list's
/// model-string → FontAwesome glyph lookup. Case-insensitive substring matching, most-specific
/// Mac variants checked before the generic "mac" fallback, and an iPhone default for anything
/// unrecognized (this app ships iPhone-only today).
final class DeviceIconMappingTests: XCTestCase {

    func testKnownAppleDeviceStrings() {
        XCTAssertEqual(DeviceIconMapping.icon(forModel: "iPhone"), DeviceIcons.iphone)
        XCTAssertEqual(DeviceIconMapping.icon(forModel: "iPad"), DeviceIcons.ipad)
        XCTAssertEqual(DeviceIconMapping.icon(forModel: "iPad Pro"), DeviceIcons.ipad)
        XCTAssertEqual(DeviceIconMapping.icon(forModel: "Apple Watch"), DeviceIcons.watch)
        XCTAssertEqual(DeviceIconMapping.icon(forModel: "Apple Vision Pro"), DeviceIcons.visionPro)
        XCTAssertEqual(DeviceIconMapping.icon(forModel: "HomePod mini"), DeviceIcons.speaker)
        XCTAssertEqual(DeviceIconMapping.icon(forModel: "iMac"), DeviceIcons.display)
    }

    func testMacVariantsCheckMostSpecificFirst() {
        // "MacBook Pro", "Mac mini", and "Mac Studio" all contain the substring "mac" — the
        // specific checks must win over the generic Mac fallback.
        XCTAssertEqual(DeviceIconMapping.icon(forModel: "MacBook Pro"), DeviceIcons.laptop)
        XCTAssertEqual(DeviceIconMapping.icon(forModel: "MacBook Air"), DeviceIcons.laptop)
        XCTAssertEqual(DeviceIconMapping.icon(forModel: "Mac mini"), DeviceIcons.desktopClassic)
        XCTAssertEqual(DeviceIconMapping.icon(forModel: "Mac Studio"), DeviceIcons.desktopClassic)
        // An unspecified Mac (e.g. `Host.current().localizedName` on a plain "Mac") falls back
        // to the laptop glyph as the most generic reasonable default.
        XCTAssertEqual(DeviceIconMapping.icon(forModel: "Mac"), DeviceIcons.laptop)
    }

    func testCaseInsensitive() {
        XCTAssertEqual(DeviceIconMapping.icon(forModel: "IPAD"), DeviceIcons.ipad)
        XCTAssertEqual(DeviceIconMapping.icon(forModel: "apple watch"), DeviceIcons.watch)
    }

    func testUnknownModelDefaultsToIPhone() {
        XCTAssertEqual(DeviceIconMapping.icon(forModel: ""), DeviceIcons.iphone)
        XCTAssertEqual(DeviceIconMapping.icon(forModel: "some future device"), DeviceIcons.iphone)
    }
}
