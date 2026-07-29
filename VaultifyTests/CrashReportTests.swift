import XCTest
@testable import Vaultify

/// The crash-payload gate. Crashlytics validates nothing and redacts nothing:
/// whatever a call site hands it is uploaded and shown in the dashboard, so the
/// catalog has to be provably free of anything derived from vault contents.
/// `auditSamples` is the contract — a new catalog factory without a sample here
/// isn't covered.
final class CrashReportTests: XCTestCase {

    func testCatalogObeysCrashKeyPolicy() {
        let samples = CrashReportKey.auditSamples
        XCTAssertGreaterThan(samples.count, 3, "catalog audit list looks truncated")
        XCTAssertLessThanOrEqual(samples.count, CrashReportPolicy.keyCountLimit,
                                 "more keys than Crashlytics keeps per report")
        for key in samples {
            let issues = CrashReportPolicy.issues(in: key)
            XCTAssertTrue(issues.isEmpty, "\(key.name): \(issues.joined(separator: "; "))")
        }
    }

    func testCatalogKeyNamesAreUnique() {
        // A repeated name means one factory silently overwrites another's value
        // in the report, and the dashboard shows the wrong state for a crash.
        var seen: Set<String> = []
        for key in CrashReportKey.auditSamples {
            XCTAssertTrue(seen.insert(key.name).inserted, "duplicate crash key '\(key.name)'")
        }
    }

    func testUnsafeValuesAreRejected() {
        // Each of these is a real leak shape: a container path, a login site, an
        // email address, an item name, a raw error description.
        for leak in ["/Users/someone/Library/Group Containers/vault.store",
                     "https://bank.example.com/login",
                     "person@example.com",
                     "Work Email",
                     "The operation couldn’t be completed."] {
            XCTAssertFalse(CrashReportPolicy.isSafeValueToken(leak),
                           "'\(leak)' passed as a crash-key value")
            XCTAssertFalse(CrashReportPolicy.issues(in: CrashReportKey("k", .string(leak))).isEmpty)
        }
        XCTAssertFalse(CrashReportPolicy.isSafeValueToken(""))
        XCTAssertFalse(CrashReportPolicy.isSafeValueToken(
            String(repeating: "a", count: CrashReportPolicy.stringValueLimit + 1)))
        XCTAssertTrue(CrashReportPolicy.isSafeValueToken("item_detail"))
        XCTAssertTrue(CrashReportPolicy.isSafeValueToken("1.43.2"))
    }

    func testPolicyCatchesBadKeyNames() {
        XCTAssertFalse(CrashReportPolicy.issues(in: CrashReportKey("CamelCase", .int(1))).isEmpty)
        XCTAssertFalse(CrashReportPolicy.issues(in: CrashReportKey("has space", .int(1))).isEmpty)
        XCTAssertFalse(CrashReportPolicy.issues(in: CrashReportKey(
            String(repeating: "a", count: CrashReportPolicy.keyNameLimit + 1), .int(1))).isEmpty)
        XCTAssertTrue(CrashReportPolicy.issues(in: CrashReportKey("ok_key_2", .bool(true))).isEmpty)
    }

    func testFaultCatalogIsCategorised() {
        let faults = CrashReportFault.allCases
        XCTAssertGreaterThan(faults.count, 1, "fault catalog looks truncated")
        for fault in faults {
            let issues = CrashReportPolicy.issues(in: fault)
            XCTAssertTrue(issues.isEmpty, "\(fault.identifier): \(issues.joined(separator: "; "))")
        }
    }

    func testFaultGroupingIdentitiesAreStableAndUnique() {
        // Crashlytics groups non-fatals by domain + code, so a reused code
        // merges two unrelated failures into one dashboard row.
        var codes: Set<Int> = []
        var identifiers: Set<String> = []
        for fault in CrashReportFault.allCases {
            XCTAssertTrue(codes.insert(fault.rawValue).inserted,
                          "duplicate grouping code \(fault.rawValue)")
            XCTAssertTrue(identifiers.insert(fault.identifier).inserted,
                          "duplicate fault identifier '\(fault.identifier)'")
        }
    }

    func testFaultErrorCarriesNothingBeyondItsIdentifier() {
        // The whole point of the categorising layer: `record(error:)` uploads
        // userInfo verbatim, so nothing from a caught error may reach it.
        for fault in CrashReportFault.allCases {
            let error = fault.error
            XCTAssertEqual(error.domain, CrashReportFault.domain)
            XCTAssertEqual(error.code, fault.rawValue)
            XCTAssertEqual(error.userInfo.count, 1)
            XCTAssertEqual(error.userInfo[NSLocalizedDescriptionKey] as? String, fault.identifier)
        }
    }
}
