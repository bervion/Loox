import XCTest
@testable import Vaultify

/// Unit tests for `DeviceModelNames.marketingName(forIdentifier:)` — the Profile Devices list's
/// raw hardware-identifier → Apple marketing-name lookup. Covers a spread of tabled identifiers
/// (iPhone/iPad/Watch) plus the mandatory fallback behavior: an untabled-but-recognizable
/// family prefix degrades to a generic family name, and a totally unrecognized identifier is
/// returned verbatim — never a crash, never an empty string.
final class DeviceModelNamesTests: XCTestCase {

    func testKnownIPhoneIdentifiers() {
        XCTAssertEqual(DeviceModelNames.marketingName(forIdentifier: "iPhone17,1"), "iPhone 16 Pro")
        XCTAssertEqual(DeviceModelNames.marketingName(forIdentifier: "iPhone17,2"), "iPhone 16 Pro Max")
        XCTAssertEqual(DeviceModelNames.marketingName(forIdentifier: "iPhone17,3"), "iPhone 16")
        XCTAssertEqual(DeviceModelNames.marketingName(forIdentifier: "iPhone17,4"), "iPhone 16 Plus")
        XCTAssertEqual(DeviceModelNames.marketingName(forIdentifier: "iPhone12,3"), "iPhone 11 Pro")
        XCTAssertEqual(DeviceModelNames.marketingName(forIdentifier: "iPhone18,4"), "iPhone Air")
    }

    func testKnownIPadAndWatchIdentifiers() {
        XCTAssertEqual(DeviceModelNames.marketingName(forIdentifier: "iPad13,1"), "iPad Air (4th generation)")
        XCTAssertEqual(DeviceModelNames.marketingName(forIdentifier: "iPad16,3"), "iPad Pro 11-inch (M4)")
        XCTAssertEqual(DeviceModelNames.marketingName(forIdentifier: "Watch7,1"), "Apple Watch Series 9")
        XCTAssertEqual(DeviceModelNames.marketingName(forIdentifier: "Watch6,18"), "Apple Watch Ultra")
    }

    /// An identifier from a family this table knows about, but a specific model newer than the
    /// table, still gets a sensible generic name derived from the prefix rather than falling
    /// through to the raw-string case.
    func testUnknownModelWithinKnownFamilyFallsBackToGenericFamilyName() {
        XCTAssertEqual(DeviceModelNames.marketingName(forIdentifier: "iPhone99,9"), "iPhone")
        XCTAssertEqual(DeviceModelNames.marketingName(forIdentifier: "iPad99,9"), "iPad")
        XCTAssertEqual(DeviceModelNames.marketingName(forIdentifier: "Watch99,9"), "Apple Watch")
        XCTAssertEqual(DeviceModelNames.marketingName(forIdentifier: "Mac99,9"), "Mac")
    }

    /// A totally unrecognized identifier (not even a known family prefix) is returned as-is —
    /// still informative, and still never empty.
    func testTotallyUnknownIdentifierReturnsRawString() {
        XCTAssertEqual(DeviceModelNames.marketingName(forIdentifier: "PearPhone9,9"), "PearPhone9,9")
    }

    func testNeverReturnsEmptyString() {
        XCTAssertFalse(DeviceModelNames.marketingName(forIdentifier: "").isEmpty)
        XCTAssertFalse(DeviceModelNames.marketingName(forIdentifier: "anything").isEmpty)
    }
}
