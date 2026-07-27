import SwiftUI

/// Contextual capability-state banner (proposal: contextual screens over modal
/// alerts). A thin CONTENT MAPPER over `VaultInfoBanner` — it owns the copy and
/// the severity mapping, never the anatomy. Renders nothing when available.
///
/// Severity rule: infrastructure states the user cannot act on stay neutral
/// (`.info` for offline / operator-disabled / retired), a degraded service that
/// is expected back reads `.warning` (outage, maintenance), and a feature the
/// user switched off reads `.error` — it is a blocked state with a remedy the
/// user owns, not a neutral notice. That last case overrides the earlier
/// "red is reserved for infrastructure" rule.
struct CapabilityBannerView: View {
    let availability: CapabilityAvailability
    /// Manifest-provided copy key — overrides the default body when it maps
    /// to a whitelisted localized string (a raw key is never rendered).
    var messageKey: String?
    /// Settings hook for the user-disabled state ("Open Settings").
    /// Declared BEFORE `onRetry` on purpose: an unlabeled trailing closure binds
    /// to the LAST function-typed parameter, and existing callers pass retry
    /// that way.
    var onOpenSettings: (() -> Void)?
    /// Retry hook for the outage state ("Try again" → re-probe).
    var onRetry: (() -> Void)?

    var body: some View {
        if let content {
            if let custom = CapabilityMessageKey.localized(messageKey) {
                VaultInfoBanner(content.variant, icon: content.icon,
                                title: content.title,
                                verbatimText: custom,
                                actionLabel: actionLabel(for: content),
                                action: handler(for: content))
            } else {
                VaultInfoBanner(content.variant, icon: content.icon,
                                title: content.title,
                                text: content.body,
                                actionLabel: actionLabel(for: content),
                                action: handler(for: content))
            }
        }
    }

    private struct Content {
        let variant: VaultInfoBanner.Variant
        let icon: String
        let title: LocalizedStringKey
        let body: LocalizedStringKey
        var action: ActionKind = .none
    }

    private enum ActionKind {
        case none, retry, openSettings
    }

    /// The action only renders when the owning screen supplied the hook.
    private func actionLabel(for content: Content) -> LocalizedStringKey? {
        switch content.action {
        case .none: return nil
        case .retry: return onRetry == nil ? nil : "Try again"
        case .openSettings: return onOpenSettings == nil ? nil : "Open Settings"
        }
    }

    private func handler(for content: Content) -> (() -> Void)? {
        switch content.action {
        case .none: return nil
        case .retry: return onRetry
        case .openSettings: return onOpenSettings
        }
    }

    private var content: Content? {
        switch availability {
        case .available:
            return nil
        case .disabledByUser:
            // The create affordances hide in this state — without this banner a
            // subscriber arriving from the membership grid ("Off in Settings")
            // would find an unexplained, stripped-down screen.
            return Content(variant: .error,
                           icon: Icons.settings,
                           title: "Turned off in Settings",
                           body: "Saved records stay visible. Turn this feature back on in Settings to use it again.",
                           action: .openSettings)
        case .offline:
            return Content(variant: .info,
                           icon: Icons.globe,
                           title: "No Internet Connection",
                           body: "Your saved private addresses are still available in Loox. Connect to the internet to create or change forwarding settings.")
        case .temporarilyUnavailable:
            return Content(variant: .warning,
                           icon: Icons.alert,
                           title: "Temporarily unavailable",
                           body: "We’re having trouble reaching the relay service. Your vault and saved passwords are not affected.",
                           action: .retry)
        case .maintenance:
            return Content(variant: .warning,
                           icon: Icons.settings,
                           title: "Under maintenance",
                           body: "Private Email is under maintenance. Creating or changing private addresses is temporarily paused. Your vault continues to work normally.")
        case .disabledByOperator:
            return Content(variant: .info,
                           icon: Icons.hide,
                           title: "Currently unavailable",
                           body: "Private Email is currently unavailable. Loox has temporarily disabled this feature. Your vault and other features continue to work normally.")
        case .retired:
            return Content(variant: .info,
                           icon: Icons.archive,
                           title: "No longer available",
                           body: "Private Email is no longer offered by Loox. Your saved alias records remain visible so you can identify accounts that used them.")
        case .unknown:
            return nil
        }
    }
}

/// Whitelisted manifest `message_key`s → localized copy (BE handoff §7.5).
/// Unknown keys return nil so the banner falls back to per-state defaults —
/// a raw key string is never shown to the user.
nonisolated enum CapabilityMessageKey {
    static func localized(_ key: String?) -> String? {
        switch key {
        case "private_email_maintenance":
            return appString("Private Email is under maintenance. Creating or changing private addresses is temporarily paused. Your vault continues to work normally.")
        case "private_email_disabled":
            return appString("Private Email is currently unavailable. Loox has temporarily disabled this feature. Your vault and other features continue to work normally.")
        case "private_email_retired":
            return appString("Private Email is no longer offered by Loox. Your saved alias records remain visible so you can identify accounts that used them.")
        case "private_email_shutdown_notice":
            return appString("Private Email will stop forwarding soon. Review accounts using these addresses.")
        case "share_link_maintenance":
            return appString("Creating and managing links is temporarily paused. Your vault continues to work normally.")
        case "share_link_disabled":
            return appString("Share Links are temporarily unavailable. Your vault is not affected.")
        case "share_link_retired":
            return appString("Share Links are no longer offered. Your saved vault items are unchanged.")
        default:
            return nil
        }
    }
}

/// Short status text for Settings rows ("Available / Maintenance / …").
nonisolated enum CapabilityStatusText {
    static func label(_ availability: CapabilityAvailability) -> String {
        switch availability {
        case .available: return appString("Available")
        case .offline: return appString("Offline")
        case .maintenance: return appString("Maintenance")
        case .temporarilyUnavailable: return appString("Temporarily unavailable")
        case .disabledByOperator: return appString("Unavailable")
        case .disabledByUser: return appString("Off")
        case .retired: return appString("No longer available")
        case .unknown: return appString("Unknown")
        }
    }
}
