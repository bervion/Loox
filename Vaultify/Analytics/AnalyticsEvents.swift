import Foundation

/// The event catalog — the ONLY place event names and parameter keys are spelled.
/// Call sites use these factories; free-form `AnalyticsEvent("...")` at a call site
/// is a review smell. Grouped by domain; add new domains as new MARK sections (or
/// split into per-domain files once a section outgrows this one).
///
/// Naming: past-tense snake_case facts (`item_created`), GA4 recommended names
/// where semantics match exactly (`tutorial_begin`, `screen_view`). Every factory
/// must be represented in `auditSamples` so `AnalyticsEventTests` can hold the
/// whole catalog to `AnalyticsPolicy`.
extension AnalyticsEvent {

    // MARK: Screens

    /// Manual GA4 `screen_view` (automatic UIKit reporting is disabled — it only
    /// sees hosting controllers under SwiftUI). `screen` is a fixed snake_case
    /// identifier from the call site, never a user-visible title.
    static func screenView(_ screen: String) -> AnalyticsEvent {
        AnalyticsEvent("screen_view", ["screen_name": .string(screen),
                                       "screen_class": .string(screen)])
    }

    // MARK: Onboarding & vault lifecycle

    static let tutorialBegin = AnalyticsEvent("tutorial_begin")
    static let tutorialComplete = AnalyticsEvent("tutorial_complete")

    /// In-app guided tours (distinct from the onboarding pair above, which
    /// covers vault setup). `flow` and `step` are fixed identifiers from the
    /// flow definition — never screen titles or anything the user typed.
    static func tutorialStepShown(flow: String, step: Int) -> AnalyticsEvent {
        AnalyticsEvent("tutorial_step_shown", ["flow": .string(flow), "step_index": .int(step)])
    }
    /// `outcome`: "completed" | "skipped".
    static func tutorialFlowEnded(flow: String, outcome: String) -> AnalyticsEvent {
        AnalyticsEvent("tutorial_flow_ended", ["flow": .string(flow), "outcome": .string(outcome)])
    }
    /// A fresh vault finished creation (master password set). The activation moment.
    static let vaultCreated = AnalyticsEvent("vault_created")
    /// An existing vault was restored during onboarding. `method`: "qr" | "recovery".
    static func vaultRestored(method: String) -> AnalyticsEvent {
        AnalyticsEvent("vault_restored", ["method": .string(method)])
    }

    // MARK: Unlock

    /// `method`: "biometric" | "password".
    static func vaultUnlocked(method: String) -> AnalyticsEvent {
        AnalyticsEvent("vault_unlocked", ["method": .string(method)])
    }
    static func vaultUnlockFailed(method: String) -> AnalyticsEvent {
        AnalyticsEvent("vault_unlock_failed", ["method": .string(method)])
    }

    // MARK: Items (type only — never names, values, or sites)

    static func itemCreated(_ type: ItemCategory) -> AnalyticsEvent {
        AnalyticsEvent("item_created", ["item_type": .string(type.rawValue)])
    }
    static func itemUpdated(_ type: ItemCategory) -> AnalyticsEvent {
        AnalyticsEvent("item_updated", ["item_type": .string(type.rawValue)])
    }
    static func itemDeleted(_ type: ItemCategory) -> AnalyticsEvent {
        AnalyticsEvent("item_deleted", ["item_type": .string(type.rawValue)])
    }
    static func itemViewed(_ type: ItemCategory) -> AnalyticsEvent {
        AnalyticsEvent("item_viewed", ["item_type": .string(type.rawValue)])
    }

    // MARK: Engagement

    /// Deliberately WITHOUT the GA4 `search` name — that one carries `search_term`,
    /// and a vault search term is user content we must never transmit.
    static let searchPerformed = AnalyticsEvent("search_performed")
    /// `mode`: "password" | "passphrase" | "pin" (generator tab identifiers).
    static func passwordGenerated(mode: String) -> AnalyticsEvent {
        AnalyticsEvent("password_generated", ["mode": .string(mode)])
    }
    /// Copy frequency is the core daily-use signal. Only the sensitivity class of
    /// the copied field travels — never which field, item, or value.
    static func copiedToClipboard(sensitive: Bool) -> AnalyticsEvent {
        AnalyticsEvent("copy_to_clipboard", ["sensitive": .bool(sensitive)])
    }

    // MARK: Watchtower

    /// `findingsBucket` via `AnalyticsBucket.count` — raw finding counts profile
    /// the vault; buckets answer the product question.
    static func watchtowerScanCompleted(findingsBucket: String) -> AnalyticsEvent {
        AnalyticsEvent("watchtower_scan_completed", ["findings_bucket": .string(findingsBucket)])
    }

    // MARK: Subscription funnel (our own product IDs are not user data)

    /// `source`: `LooxPaywallContext.rawValue` — which gate opened the paywall.
    static func paywallShown(source: String) -> AnalyticsEvent {
        AnalyticsEvent("paywall_shown", ["source": .string(source)])
    }
    static func purchaseStarted(productID: String) -> AnalyticsEvent {
        AnalyticsEvent("purchase_started", ["product_id": .string(productID)])
    }
    static func purchaseCompleted(productID: String) -> AnalyticsEvent {
        AnalyticsEvent("purchase_completed", ["product_id": .string(productID)])
    }
    /// `reason`: "verification" | "pending" | "error" — StoreKit categories, never
    /// raw error descriptions (they can embed account context).
    static func purchaseFailed(productID: String, reason: String) -> AnalyticsEvent {
        AnalyticsEvent("purchase_failed", ["product_id": .string(productID),
                                           "reason": .string(reason)])
    }
    static let purchaseRestored = AnalyticsEvent("purchase_restored")

    // MARK: Settings & data portability

    /// `language`: "system" | "en" | "vi" | "ja".
    static func languageChanged(_ language: String) -> AnalyticsEvent {
        AnalyticsEvent("language_changed", ["language": .string(language)])
    }
    static func icloudSyncToggled(enabled: Bool) -> AnalyticsEvent {
        AnalyticsEvent("icloud_sync_toggled", ["enabled": .bool(enabled)])
    }
    /// Only builtin theme identifiers travel; any custom theme reports "custom".
    static func themeChanged(_ theme: String) -> AnalyticsEvent {
        AnalyticsEvent("theme_changed", ["theme": .string(theme)])
    }
    static let analyticsEnabled = AnalyticsEvent("analytics_enabled")
    static let analyticsDisabled = AnalyticsEvent("analytics_disabled")
    static func vaultImported(countBucket: String) -> AnalyticsEvent {
        AnalyticsEvent("vault_imported", ["count_bucket": .string(countBucket)])
    }
    static let vaultExported = AnalyticsEvent("vault_exported")

    // MARK: Catalog audit

    /// One representative instance per factory above. `AnalyticsEventTests` runs
    /// `AnalyticsPolicy.issues(in:)` over this list — extend it with every new
    /// event, or the taxonomy silently drifts out of GA4's accepted shape.
    static var auditSamples: [AnalyticsEvent] {
        [
            .screenView("home"),
            .tutorialBegin, .tutorialComplete, .vaultCreated,
            .tutorialStepShown(flow: "first-run", step: 0),
            .tutorialFlowEnded(flow: "first-run", outcome: "completed"),
            .vaultRestored(method: "qr"),
            .vaultUnlocked(method: "biometric"), .vaultUnlockFailed(method: "password"),
            .itemCreated(.login), .itemUpdated(.note), .itemDeleted(.card), .itemViewed(.identity),
            .searchPerformed, .passwordGenerated(mode: "passphrase"),
            .copiedToClipboard(sensitive: true),
            .watchtowerScanCompleted(findingsBucket: AnalyticsBucket.count(7)),
            .paywallShown(source: "profile"),
            .purchaseStarted(productID: LooxProductID.maxAnnual),
            .purchaseCompleted(productID: LooxProductID.maxAnnual),
            .purchaseFailed(productID: LooxProductID.plusMonthly, reason: "error"),
            .purchaseRestored,
            .languageChanged("vi"), .icloudSyncToggled(enabled: true),
            .themeChanged("custom"), .analyticsEnabled, .analyticsDisabled,
            .vaultImported(countBucket: AnalyticsBucket.count(120)), .vaultExported,
        ]
    }
}
