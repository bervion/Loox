import Foundation

/// Launch gate for the commercial surfaces. While purchases are disabled,
/// every purchase entry point stays dark: the paywall, the membership screen's
/// upgrade/manage-plan section, and the contextual over-quota gate sheets.
/// It never hides the membership screen itself, its usage counts, or any
/// existing feature behavior.
///
/// `launchEnabled` is the REAL-USER switch: App Store builds show purchase
/// surfaces only when it is true. Flip it only when the proposal §12 launch
/// gates are green (and per the backend proposal's rollout order). Beta
/// environments — TestFlight, App Review, Xcode/StoreKit-config runs — get the
/// surfaces early through `LooxEntitlementStore.purchasesEnabled`
/// (`AppTransaction.environment != .production`), which is the value every
/// surface consults; this file only holds the launch decision.
nonisolated enum LooxMembership {
    static let launchEnabled = false

    /// Policy links the paywall must expose (§5.2). Both pages are a §12 launch
    /// gate — they must resolve before `purchasesEnabled` ever flips.
    static let termsURL = URL(string: "https://looxpassword.com/terms")!
    static let privacyURL = URL(string: "https://looxpassword.com/privacy")!
}
