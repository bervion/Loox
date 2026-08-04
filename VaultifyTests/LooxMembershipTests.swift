import Foundation
import XCTest
@testable import Vaultify

/// The purchase surfaces link to Terms and Privacy because App Review checks
/// them (3.1.2) and because selling an auto-renewing subscription under terms
/// nobody can open is legal exposure. The app shipped `looxpassword.com/terms`
/// and `/privacy` for months and both were 404 — the URL *shape* is the thing
/// no build or review step catches, so it is pinned here.
final class LooxMembershipTests: XCTestCase {

    private let origin = "https://looxpassword.com"

    // MARK: URL shape

    func testDefaultLanguageResolvesToTheCanonicalPolicyPages() {
        let english = Locale(identifier: "en")
        XCTAssertEqual(LooxMembership.policyURL(.terms, locale: english).absoluteString,
                       "\(origin)/policies/terms")
        XCTAssertEqual(LooxMembership.policyURL(.privacy, locale: english).absoluteString,
                       "\(origin)/policies/privacy")
    }

    func testVietnameseResolvesToTheVietnameseTwins() {
        XCTAssertEqual(LooxMembership.policyURL(.terms, locale: Locale(identifier: "vi")).absoluteString,
                       "\(origin)/vi/policies/terms")
        XCTAssertEqual(LooxMembership.policyURL(.privacy, locale: Locale(identifier: "vi")).absoluteString,
                       "\(origin)/vi/policies/privacy")
        // Region variants are still Vietnamese.
        for identifier in ["vi_VN", "vi-VN"] {
            XCTAssertEqual(LooxMembership.policyURL(.terms, locale: Locale(identifier: identifier)).absoluteString,
                           "\(origin)/vi/policies/terms",
                           "\(identifier) must keep the vi prefix")
        }
    }

    func testLanguagesWithoutAPublishedPageFallBackToTheDefault() {
        // Japanese ships in the app but the site publishes no ja policies
        // (verified 404 on 2026-08-04). A missing translation must degrade to a
        // readable page, never to a dead link.
        for identifier in ["ja", "ja_JP", "fr", "zh-Hans", ""] {
            XCTAssertEqual(LooxMembership.policyURL(.privacy, locale: Locale(identifier: identifier)).absoluteString,
                           "\(origin)/policies/privacy",
                           "\(identifier) must fall back to the default page")
        }
    }

    func testNoLanguageEverProducesARetiredOrMalformedPath() {
        let languages = ["en", "vi", "ja", "fr", "de", "zh-Hant", "vi_VN", ""]
        for identifier in languages {
            for page in [LooxMembership.PolicyPage.terms, .privacy] {
                let resolved = LooxMembership.policyURL(page, locale: Locale(identifier: identifier)).absoluteString
                XCTAssertTrue(resolved.hasPrefix("\(origin)/"),
                              "\(identifier) resolved to \(resolved)")
                // The bare /terms and /privacy routes do not exist on the site.
                XCTAssertTrue(resolved.hasSuffix("/policies/\(page.rawValue)"),
                              "\(identifier) resolved to \(resolved)")
                XCTAssertFalse(resolved.dropFirst("https://".count).contains("//"),
                               "\(identifier) resolved to \(resolved)")
            }
        }
    }

    // MARK: In-app language

    func testTheShippedAccessorsFollowTheInAppLanguage() {
        let restore = appResourceLocale
        defer { appResourceLocale = restore }

        appResourceLocale = Locale(identifier: "vi")
        XCTAssertEqual(LooxMembership.termsURL.absoluteString, "\(origin)/vi/policies/terms")
        XCTAssertEqual(LooxMembership.privacyURL.absoluteString, "\(origin)/vi/policies/privacy")

        appResourceLocale = Locale(identifier: "en")
        XCTAssertEqual(LooxMembership.termsURL.absoluteString, "\(origin)/policies/terms")
        XCTAssertEqual(LooxMembership.privacyURL.absoluteString, "\(origin)/policies/privacy")

        // A device language the site does not publish still lands on a live page.
        appResourceLocale = Locale(identifier: "ja")
        XCTAssertEqual(LooxMembership.termsURL.absoluteString, "\(origin)/policies/terms")
    }

    // MARK: Commerce switches

    func testProductionPurchasesStayOffUntilTheLaunchGatesAreGreen() {
        // Deliberate tripwire. Flipping this constant means the whole §5.6 gate
        // list in phase-05-membership-launch.md is green — live policy pages
        // with counsel sign-off, submittable products, purchase and restore
        // proven on a signed TestFlight build, the attach E2E recorded, backend
        // modes observed, real-device matrix passed. Updating this test is the
        // moment to confirm that, not a formality.
        XCTAssertFalse(LooxMembership.launchEnabled)
    }

    func testBetaPreviewSwitchCanDarkenEveryCommerceSurface() {
        // On for this submission so App Review can evaluate the four attached
        // subscriptions. The value that matters is that the switch exists:
        // with it off, `LooxEntitlementStore` never resolves the environment
        // and no purchase surface can open.
        XCTAssertTrue(LooxMembership.betaPreviewEnabled)
    }
}
