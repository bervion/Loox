import XCTest
@testable import Vaultify

/// Capability catalog + authentication opportunity rules: matching guards,
/// wording-relevant behavior (item WITH protection stays silent), and the
/// catalog-version fingerprint contract.
final class ServiceCapabilityCatalogTests: XCTestCase {

    private func login(id: String, url: String?, totp: String? = nil,
                       hasPasskey: Bool = false) -> VaultAuditItem {
        VaultAuditItem(id: id, category: .login, title: "Login",
                       usernames: ["user"], password: "kR9#mPz$vL2@qXw7",
                       totpSecret: totp, hasTOTP: totp != nil, hasPasskey: hasPasskey,
                       rawURLs: url.map { [$0] } ?? [],
                       createdAt: .now, updatedAt: .now, lastUsedAt: nil,
                       rotateDays: 0, passwordChangedAt: nil, isTrashed: false)
    }

    private func snapshot(_ items: [VaultAuditItem]) -> VaultAuditSnapshot {
        VaultAuditSnapshot(items: items, personaID: nil, capturedAt: .now)
    }

    // MARK: - Matching guards

    func testSuffixMatchNotSubstring() {
        XCTAssertNotNil(ServiceCapabilityCatalog.capability(urls: ["https://accounts.google.com/x"]))
        XCTAssertNil(ServiceCapabilityCatalog.capability(urls: ["https://notgoogle.com"]),
                     "substring must not match")
        XCTAssertNil(ServiceCapabilityCatalog.capability(urls: []))
    }

    func testCatalogExtendsLegacyTwoFactorList() {
        // playstation.com is only in the new catalog, not the legacy domain list.
        XCTAssertTrue(TwoFactorCatalog.supports2FA(urls: ["https://playstation.com"], title: ""))
    }

    // MARK: - Passkey opportunity rule

    func testPasskeyOpportunityOnlyWhenSiteSupportsAndVaultLacks() async throws {
        let items = [
            login(id: "github-no-pk", url: "https://github.com"),
            login(id: "github-with-pk", url: "https://github.com", hasPasskey: true),
            login(id: "unknown-site", url: "https://obscure-forum.test"),
            login(id: "no-passkey-support", url: "https://reddit.com"),
        ]
        let findings = try await PasskeyOpportunityRule()
            .evaluate(snapshot(items), context: AuditContext())
        XCTAssertEqual(findings.flatMap(\.affectedItemIDs), ["github-no-pk"])
        XCTAssertEqual(findings[0].severity, .low, "opportunity, never a deficiency")
        XCTAssertEqual(findings[0].remediation, .addPasskey)
    }

    func testFingerprintChangesWithCatalogVersion() {
        let now = AuditFingerprint.make(ruleID: "auth.passkey-available", version: 1,
                                        itemIDs: ["a"],
                                        marker: ServiceCapabilityCatalog.fingerprintMarker)
        let future = AuditFingerprint.make(ruleID: "auth.passkey-available", version: 1,
                                           itemIDs: ["a"], marker: "capability-catalog-v999")
        XCTAssertNotEqual(now, future,
                          "catalog data updates must re-surface findings")
    }

    // MARK: - Scoring interaction

    func testOneItemMissingBothIsOneOpportunity() async throws {
        // github.com supports both TOTP and passkeys → 2 findings, 1 item.
        let items = [login(id: "a", url: "https://github.com")]
        let coordinator = AuditCoordinator(rules: [TwoFactorRule(), PasskeyOpportunityRule()])
        let run = try await coordinator.run(snapshot: snapshot(items), context: AuditContext())
        XCTAssertEqual(run.findings.count, 2)

        let report = ScoringEngine.report(snapshot: snapshot(items), run: run)
        // 0 confirmed / 1 opportunity → floor: 140 × 0.75 = 105.
        XCTAssertEqual(report.earned[.authReadiness], 105)
    }
}
