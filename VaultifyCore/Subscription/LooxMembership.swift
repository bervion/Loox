import Foundation

/// Launch gate for the commercial surfaces: the paywall, the membership
/// screen's upgrade/manage-plan section, and the contextual over-quota gate
/// sheets. It never hides the membership screen itself, its usage counts, or
/// any existing feature behavior.
///
/// Commerce is LIVE (owner decision 2026-10-21). The effective tier every surface
/// reads also includes the device-local complimentary Loox+ grant
/// (`LooxComplimentaryGrant`), so a new install starts on Loox+ quotas while
/// all four subscriptions stay purchasable. Surfaces consult
/// `LooxEntitlementStore.purchasesEnabled`; this file holds the launch
/// decision and the policy pages every purchase surface has to link to.
nonisolated enum LooxMembership {
    /// Production purchases. Flipped on by owner decision 2026-10-21. Remaining
    /// §5.6 items are tracked in
    /// `plans/260804-1037-release-readiness-remediation/phase-05-membership-launch.md`.
    /// Turning it back off is a gated decision too: `LooxMembershipTests`
    /// fails when the value changes, so neither direction lands unread.
    static let launchEnabled = true

    /// Whether beta environments (TestFlight, App Review) may show the purchase
    /// surfaces while `launchEnabled` is off. With launch live it changes
    /// nothing; it is kept so that darkening commerce again stays one edit.
    /// `false` means the store never resolves `AppTransaction`, so even a
    /// sandbox receipt cannot open the paywall.
    static let betaPreviewEnabled = true

    /// The two policy pages every purchase surface must link to (App Store
    /// Review Guideline 3.1.2).
    enum PolicyPage: String {
        case terms
        case privacy
    }

    /// Origin of the marketing site that serves the policy pages.
    static let policyOrigin = "https://looxpassword.com"

    /// Path prefix per language for the locales the site actually publishes.
    /// The site runs `localePrefix: 'as-needed'`, so the default language (en)
    /// has no prefix and every other published language has one. A language
    /// with no published translation resolves to the default page rather than
    /// to a 404 — ja is in the app but not on the site (verified 2026-08-04).
    private static let policyPathPrefixes: [String: String] = ["vi": "/vi"]

    /// Canonical policy URL for a language. Always `<origin>[/<lang>]/policies/<page>`
    /// — the bare `/terms` and `/privacy` paths this used to point at are not
    /// routes on the site.
    static func policyURL(_ page: PolicyPage, locale: Locale = appResourceLocale) -> URL {
        let language = locale.language.languageCode?.identifier.lowercased() ?? ""
        let prefix = policyPathPrefixes[language] ?? ""
        // Every component is a compile-time constant from the table above, so
        // this string is always a valid URL.
        return URL(string: "\(policyOrigin)\(prefix)/policies/\(page.rawValue)")!
    }

    /// Terms of Use in the in-app language. Both pages are a launch gate — they
    /// must resolve before `purchasesEnabled` ever flips.
    static var termsURL: URL { policyURL(.terms) }

    /// Privacy Policy in the in-app language.
    static var privacyURL: URL { policyURL(.privacy) }
}
