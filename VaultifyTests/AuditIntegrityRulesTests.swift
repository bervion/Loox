import XCTest
@testable import Vaultify

/// Integrity and hygiene rules: duplicates, conflicts, incomplete items,
/// invalid OTP, URL sanity, staleness. Positive, negative, and edge cases.
final class AuditIntegrityRulesTests: XCTestCase {

    private func login(id: String, title: String = "Site", username: String? = "user",
                       password: String? = "kR9#mPz$vL2@qXw7", url: String? = "https://example.org",
                       totp: String? = nil, created: Date = .now, changed: Date? = nil,
                       rotateDays: Int = 0, trashed: Bool = false) -> VaultItem {
        var fields: [DynamicField] = []
        if let username { fields.append(DynamicField(label: "Username", kind: .username, value: username)) }
        if let password { fields.append(DynamicField(label: "Password", kind: .password, value: password)) }
        if let url { fields.append(DynamicField(label: "Website", kind: .url, value: url)) }
        if let totp { fields.append(DynamicField(label: "One-time Code", kind: .totp, value: totp)) }
        return VaultItem(id: id, category: .login, title: title, fields: fields,
                         rotateDays: rotateDays, passwordChangedAt: changed,
                         createdAt: created, trashedAt: trashed ? .now : nil)
    }

    private func run(_ rule: any AuditRule, _ items: [VaultItem],
                     now: Date = .now) async throws -> [AuditFinding] {
        try await rule.evaluate(VaultAuditSnapshot.make(items: items),
                                context: AuditContext(now: now))
    }

    // MARK: - Exact duplicates

    func testExactDuplicatesGroupAndCleanVaultIsSilent() async throws {
        let dupes = [
            login(id: "a", title: "GitHub", url: "https://github.com"),
            login(id: "b", title: "github ", url: "https://www.github.com"),
            login(id: "c", title: "Reddit", url: "https://reddit.com"),
        ]
        let findings = try await run(ExactDuplicateRule(), dupes)
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings[0].affectedItemIDs, ["a", "b"])

        let clean = [login(id: "a", url: "https://a.test"),
                     login(id: "b", url: "https://b.test")]
        let cleanFindings = try await run(ExactDuplicateRule(), clean)
        XCTAssertTrue(cleanFindings.isEmpty)
    }

    // MARK: - Conflicting duplicates

    func testConflictNeedsSameHostSameUserDifferentPassword() async throws {
        let items = [
            login(id: "a", username: "chinh", password: "password-A1x!", url: "https://github.com"),
            login(id: "b", username: "Chinh", password: "password-B2y!", url: "https://github.com"),
            // Different username on the same host: NOT a conflict.
            login(id: "c", username: "other", password: "password-C3z!", url: "https://github.com"),
        ]
        let findings = try await run(ConflictingLoginRule(), items)
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings[0].affectedItemIDs, ["a", "b"])
        XCTAssertEqual(findings[0].severity, .high)
    }

    func testSamePasswordSameUserIsNotAConflict() async throws {
        let items = [
            login(id: "a", username: "chinh", password: "same-pass-1x!", url: "https://site.test"),
            login(id: "b", username: "chinh", password: "same-pass-1x!", url: "https://site.test"),
        ]
        let findings = try await run(ConflictingLoginRule(), items)
        XCTAssertTrue(findings.isEmpty)
    }

    // MARK: - Incomplete / missing metadata

    func testLoginWithNoCredentialAtAllIsIncomplete() async throws {
        let items = [login(id: "a", password: nil),
                     login(id: "b", password: nil, totp: "JBSWY3DPEHPK3PXP")]
        let findings = try await run(IncompleteItemRule(), items)
        XCTAssertEqual(findings.flatMap(\.affectedItemIDs), ["a"])
    }

    func testMissingURLAndUsernameAreInfoFindings() async throws {
        let items = [login(id: "a", url: nil),
                     login(id: "b", username: nil),
                     login(id: "c")]
        let findings = try await run(MissingMetadataRule(), items)
        XCTAssertEqual(Set(findings.flatMap(\.affectedItemIDs)), ["a", "b"])
        XCTAssertTrue(findings.allSatisfy { $0.severity == .info })
    }

    // MARK: - Invalid TOTP

    func testInvalidTOTPSecretIsFlagged() async throws {
        let items = [
            login(id: "a", totp: "JBSWY3DPEHPK3PXP"),      // valid base32
            login(id: "b", totp: "not-base32-!!!"),
        ]
        let findings = try await run(InvalidTOTPRule(), items)
        XCTAssertEqual(findings.flatMap(\.affectedItemIDs), ["b"])
    }

    // MARK: - URL hygiene

    func testURLHygieneClassifications() async throws {
        let cases: [(String, String, String?)] = [
            ("http", "http://site.test", "url.insecure-http"),
            ("puny", "https://xn--pple-43d.com", "url.punycode"),
            ("ip", "https://192.168.1.10/login", "url.ip-login"),
            ("ok", "https://github.com", nil),
        ]
        for (id, url, expected) in cases {
            let findings = try await run(URLHygieneRule(), [login(id: id, url: url)])
            if let expected {
                XCTAssertEqual(findings.map(\.ruleID), [expected], url)
            } else {
                XCTAssertTrue(findings.isEmpty, url)
            }
        }
    }

    func testOneFindingPerProblemKindEvenWithManyURLs() async throws {
        var item = login(id: "a", url: "http://one.test")
        item.fields.append(DynamicField(label: "Website", kind: .url, value: "http://two.test"))
        let findings = try await run(URLHygieneRule(), [item])
        XCTAssertEqual(findings.map(\.ruleID), ["url.insecure-http"])
    }

    // MARK: - Stale

    func testStaleIsInfoOnlyAndRespectsRotationCadence() async throws {
        let fiveYearsAgo = Calendar.current.date(byAdding: .year, value: -5, to: .now)!
        let items = [
            login(id: "old", created: fiveYearsAgo),
            login(id: "cadenced", created: fiveYearsAgo, rotateDays: 90),   // RotationStatus owns this
            login(id: "fresh"),
            login(id: "reviewed", created: fiveYearsAgo, changed: .now),
        ]
        let findings = try await run(StaleCredentialRule(), items)
        XCTAssertEqual(findings.flatMap(\.affectedItemIDs), ["old"])
        XCTAssertEqual(findings[0].severity, .info)
    }
}
