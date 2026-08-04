import Foundation

/// Launch gate for the commercial surfaces. While purchases are disabled,
/// every purchase entry point stays dark: the paywall, the membership screen's
/// upgrade/manage-plan section, and the contextual over-quota gate sheets.
/// It never hides the membership screen itself, its usage counts, or any
/// existing feature behavior.
///
/// `launchEnabled` is the REAL-USER switch: App Store builds show purchase
/// surfaces only when it is true. Beta environments — TestFlight, App Review,
/// Xcode/StoreKit-config runs — get the surfaces early through
/// `LooxEntitlementStore.purchasesEnabled`
/// (`AppTransaction.environment != .production`), which is the value every
/// surface consults; this file holds the launch decision and the policy pages
/// every purchase surface has to link to.
nonisolated enum LooxMembership {
    /// Production purchases. Stays `false` for the submission that first
    /// attaches the four subscriptions: Apple requires a first subscription to
    /// be submitted with an app version, but not to be sellable on day one.
    ///
    /// Flipping this is a gated decision, never a habit. The gate list lives in
    /// `plans/260804-1037-release-readiness-remediation/phase-05-membership-launch.md`
    /// §5.6 — live policy pages with counsel sign-off, submittable products in
    /// App Store Connect, purchase and restore proven end to end on a signed
    /// TestFlight build with the backend in the loop, the attach E2E recorded,
    /// backend modes observed, and the real-device matrix green.
    /// `LooxMembershipTests` fails when the value changes, so the flip cannot
    /// land without someone reading that list.
    static let launchEnabled = false

    /// Whether beta environments (TestFlight, App Review) may show the purchase
    /// surfaces before launch. Set to `false` to ship a submission with **no**
    /// commerce surface at all: the store never resolves `AppTransaction`, so
    /// even a sandbox receipt cannot open the paywall.
    ///
    /// It stays `true` for this submission — the reviewer must be able to reach
    /// the paywall to evaluate the four attached subscriptions — and exists so
    /// that darkening commerce is one edit rather than a code change.
    /// DEBUG builds are unaffected: they open purchase surfaces through the
    /// explicit dev toggle (`LooxEntitlementStore.debugPurchasesEnabled`), which
    /// is a developer's own choice on their own device.
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
