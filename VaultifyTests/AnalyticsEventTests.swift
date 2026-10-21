import XCTest
@testable import Vaultify

/// The GA4 taxonomy gate: every catalog event must clear `AnalyticsPolicy`
/// (GA4 silently DISCARDS violations server-side, so a bad name would look like
/// "feature unused" in reports, not like an error). `auditSamples` is the
/// contract — a new catalog factory without a sample here isn't covered.
final class AnalyticsEventTests: XCTestCase {

    func testCatalogObeysGA4Limits() {
        let samples = AnalyticsEvent.auditSamples
        XCTAssertGreaterThan(samples.count, 20, "catalog audit list looks truncated")
        for event in samples {
            let issues = AnalyticsPolicy.issues(in: event)
            XCTAssertTrue(issues.isEmpty,
                          "\(event.name): \(issues.joined(separator: "; "))")
        }
    }

    func testCatalogNamesAreUniquePerShape() {
        // Same event name must always carry the same parameter keys — GA4
        // registers parameters per event, and a drifting shape splits reports.
        var shapes: [String: Set<String>] = [:]
        for event in AnalyticsEvent.auditSamples {
            let keys = Set(event.parameters.keys)
            if let existing = shapes[event.name] {
                XCTAssertEqual(existing, keys, "event '\(event.name)' logged with two parameter shapes")
            } else {
                shapes[event.name] = keys
            }
        }
    }

    func testPolicyCatchesViolations() {
        XCTAssertFalse(AnalyticsPolicy.issues(in: AnalyticsEvent("CamelCase")).isEmpty)
        XCTAssertFalse(AnalyticsPolicy.issues(in: AnalyticsEvent("has space")).isEmpty)
        XCTAssertFalse(AnalyticsPolicy.issues(in: AnalyticsEvent("firebase_reserved")).isEmpty)
        XCTAssertFalse(AnalyticsPolicy.issues(in:
            AnalyticsEvent(String(repeating: "a", count: 41))).isEmpty)
        XCTAssertFalse(AnalyticsPolicy.issues(in:
            AnalyticsEvent("ok", ["Bad Key": .string("x")])).isEmpty)
        XCTAssertFalse(AnalyticsPolicy.issues(in:
            AnalyticsEvent("ok", ["k": .string(String(repeating: "v", count: 101))])).isEmpty)
        XCTAssertTrue(AnalyticsPolicy.issues(in:
            AnalyticsEvent("ok_event_2", ["k": .int(1), "b": .bool(true)])).isEmpty)
    }

    func testCountBuckets() {
        XCTAssertEqual(AnalyticsBucket.count(0), "0")
        XCTAssertEqual(AnalyticsBucket.count(-3), "0")
        XCTAssertEqual(AnalyticsBucket.count(1), "1_5")
        XCTAssertEqual(AnalyticsBucket.count(5), "1_5")
        XCTAssertEqual(AnalyticsBucket.count(6), "6_20")
        XCTAssertEqual(AnalyticsBucket.count(20), "6_20")
        XCTAssertEqual(AnalyticsBucket.count(21), "21_50")
        XCTAssertEqual(AnalyticsBucket.count(50), "21_50")
        XCTAssertEqual(AnalyticsBucket.count(51), "over_50")
    }

    func testUserPropertyNamesWithinGA4Limits() {
        for property in [AnalyticsUserProperty.subscriptionTier, .complimentaryPlus, .appLanguage, .icloudSync] {
            XCTAssertTrue(AnalyticsPolicy.isValidIdentifier(
                property.rawValue, limit: AnalyticsPolicy.userPropertyNameLimit),
                "user property '\(property.rawValue)' breaks GA4 naming limits")
        }
    }
}
