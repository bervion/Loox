import Foundation

/// Launch gate for the commercial surfaces. While `purchasesEnabled` is false,
/// every purchase entry point stays dark: the paywall, the membership screen's
/// upgrade/manage-plan section, and the contextual over-quota gate sheets.
///
/// It never hides the membership screen itself, its usage counts, or any
/// existing feature behavior — with the flag off the app behaves exactly as if
/// subscriptions didn't exist (everyone is effectively on the current
/// everything-included experience).
///
/// Flip to `true` only when the proposal §12 launch gates are green: the four
/// App Store Connect products exist with EN+VI metadata, the intro offer and
/// Billing Grace Period are configured, and the paywall QA matrix passed.
nonisolated enum LooxMembership {
    static let purchasesEnabled = false

    /// Policy links the paywall must expose (§5.2). Both pages are a §12 launch
    /// gate — they must resolve before `purchasesEnabled` ever flips.
    static let termsURL = URL(string: "https://looxpassword.com/terms")!
    static let privacyURL = URL(string: "https://looxpassword.com/privacy")!
}
