import SwiftUI

/// Contextual capability-state banner (proposal: contextual screens over
/// modal alerts; neutral styling for infrastructure states — red stays
/// reserved for destructive/security states). Renders nothing when available.
struct CapabilityBannerView: View {
    @Environment(AppEnvironment.self) private var env
    let availability: CapabilityAvailability
    /// Manifest-provided copy key — overrides the default body when it maps
    /// to a whitelisted localized string (a raw key is never rendered).
    var messageKey: String?
    /// Retry hook for the outage state ("Try Again" → re-probe).
    var onRetry: (() -> Void)?

    var body: some View {
        if let content {
            VStack(alignment: .leading, spacing: Space.s2) {
                Label { Text(content.title).vaultType(.subhead).themedForeground(.primary) }
                    icon: { PolarisIcon(content.icon, size: Metric.iconCompact) }
                if let custom = CapabilityMessageKey.localized(messageKey) {
                    Text(verbatim: custom)
                        .vaultType(.footnote)
                        .themedForeground(.secondary)
                } else {
                    Text(content.body)
                        .vaultType(.footnote)
                        .themedForeground(.secondary)
                }
                if content.showsRetry, let onRetry {
                    Button { onRetry() } label: {
                        Text("Try Again").vaultType(.footnote).themedForeground(.accentText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(rgb: env.theme.active.accentSoft),
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private struct Content {
        let icon: String
        let title: LocalizedStringKey
        let body: LocalizedStringKey
        var showsRetry = false
    }

    private var content: Content? {
        switch availability {
        case .available, .disabledByUser:
            return nil   // user-off is a Settings state, not a banner
        case .offline:
            return Content(icon: Icons.globe,
                           title: "No Internet Connection",
                           body: "Your saved private addresses are still available in Loox. Connect to the internet to create or change forwarding settings.")
        case .temporarilyUnavailable:
            return Content(icon: Icons.alert,
                           title: "Temporarily unavailable",
                           body: "We’re having trouble reaching the relay service. Your vault and saved passwords are not affected.",
                           showsRetry: true)
        case .maintenance:
            return Content(icon: Icons.settings,
                           title: "Under maintenance",
                           body: "Private Email is under maintenance. Creating or changing private addresses is temporarily paused. Your vault continues to work normally.")
        case .disabledByOperator:
            return Content(icon: Icons.hide,
                           title: "Currently unavailable",
                           body: "Private Email is currently unavailable. Loox has temporarily disabled this feature. Your vault and other features continue to work normally.")
        case .retired:
            return Content(icon: Icons.archive,
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
