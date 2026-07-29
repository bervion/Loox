import Foundation

/// The crash-key catalog — the ONLY place key names and their allowed values are
/// spelled. Call sites use these factories; a free-form
/// `CrashReportKey("...", .string(someRuntimeString))` at a call site is how a
/// vault name reaches a crash report, and is a review stop.
///
/// Every factory must be represented in `auditSamples` so `CrashReportTests` can
/// hold the whole catalog to `CrashReportPolicy`.
extension CrashReportKey {

    /// The screen on top when the process died. Fixed snake_case identifier from
    /// `.analyticsScreen(_:)`, never a localized title.
    static func activeScreen(_ screen: String) -> CrashReportKey {
        CrashReportKey("active_screen", .string(screen))
    }

    /// "onboarding" | "locked" | "unlocked". The first question any crash report
    /// has to answer: a crash on the lock screen and a crash inside an unlocked
    /// vault are different bugs, and only one of them can involve item data.
    static func vaultLockState(_ state: String) -> CrashReportKey {
        CrashReportKey("vault_lock_state", .string(state))
    }

    /// "system" | "en" | "vi" | "ja". Kept live by `SettingsStore`'s setter, so
    /// a report from a session that switched language names the language the
    /// crash actually happened in.
    static func appLanguage(_ code: String) -> CrashReportKey {
        CrashReportKey("app_language", .string(code))
    }

    /// Vault-item sync consent. A CloudKit merge is a plausible crash site, and
    /// the reports split cleanly only if this travels. Kept live by
    /// `SettingsStore`'s setter — a launch-time snapshot would name the wrong
    /// half of the split for anyone who flipped the switch mid-session.
    static func iCloudSync(enabled: Bool) -> CrashReportKey {
        CrashReportKey("icloud_sync", .bool(enabled))
    }

    /// One representative instance per factory above. `CrashReportTests` runs
    /// `CrashReportPolicy.issues(in:)` over this list — extend it with every new
    /// key, or an unvalidated value shape reaches the dashboard.
    static var auditSamples: [CrashReportKey] {
        [
            .activeScreen("item_detail"),
            .vaultLockState("locked"),
            .appLanguage("vi"),
            .iCloudSync(enabled: true),
        ]
    }
}

/// The non-fatal catalog. `Crashlytics.record(error:)` transmits an `NSError`
/// verbatim — domain, code, AND `userInfo` — so a caught CloudKit, URL, or
/// StoreKit error would carry share URLs, account context, and file paths into
/// the dashboard with it. Call sites therefore report a CATEGORY, never the
/// error they caught, and the uploaded `NSError` is built here from fixed
/// literals (the same rule `AnalyticsEvent.purchaseFailed` follows).
nonisolated enum CrashReportFault: Int, CaseIterable, Sendable {
    /// A tapped invite link could not be resolved (malformed, expired, or the
    /// CloudKit lookup failed).
    case inviteLinkResolveFailed = 1
    /// The share was resolved and the user confirmed, but accepting it failed.
    case inviteLinkAcceptFailed = 2

    /// Crashlytics groups non-fatals by domain + code, so `rawValue` is a stable
    /// identity: renumbering an existing case merges it into another group's
    /// history. Append new cases, never renumber.
    static let domain = "com.bervion.vaultify.fault"

    var identifier: String {
        switch self {
        case .inviteLinkResolveFailed: return "invite_link_resolve_failed"
        case .inviteLinkAcceptFailed: return "invite_link_accept_failed"
        }
    }

    /// The exact shape that leaves the device for this category.
    var error: NSError {
        NSError(domain: Self.domain, code: rawValue,
                userInfo: [NSLocalizedDescriptionKey: identifier])
    }
}
