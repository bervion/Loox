#if DEBUG
import SwiftUI

/// Settings → Debug rows for the complimentary Loox+ grant: a read-only status
/// row plus a menu that rewrites the grant start. These write the REAL Keychain
/// item on purpose, so QA can check that the start survives a reinstall.
/// Dev-only, so every string is verbatim (no catalog entries).
struct LooxComplimentaryDebugMenu: View {
    @Environment(AppEnvironment.self) private var env

    private static let day: TimeInterval = 86_400

    var body: some View {
        Group {
            LabeledContent {
                Text(verbatim: statusText)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
            } label: {
                Label { Text(verbatim: "Complimentary Loox+") } icon: {
                    SettingsIconBadge(systemName: "gift.fill", tint: SettingsBadgeTint.gray)
                }
            }
            Menu {
                action("Start now", start: .now)
                action("10 days left", start: Date.now.addingTimeInterval(-740 * Self.day))
                action("Expired", start: Date.now.addingTimeInterval(-751 * Self.day))
                // A start ahead of `now` should come back clamped to `now`.
                action("Future start", start: Date.now.addingTimeInterval(30 * Self.day))
                Button(role: .destructive) {
                    env.entitlements.debugSetComplimentaryStart(nil)
                } label: { Text(verbatim: "Delete item") }
            } label: {
                Label { Text(verbatim: "Set Complimentary Start") } icon: {
                    SettingsIconBadge(systemName: "calendar", tint: SettingsBadgeTint.gray)
                }
            }
            Text(verbatim: "Tier Override wins; set it to StoreKit to see the grant.")
                .vaultType(.footnote)
                .themedForeground(.secondary)
        }
    }

    private func action(_ title: String, start: Date) -> some View {
        Button { env.entitlements.debugSetComplimentaryStart(start) } label: { Text(verbatim: title) }
    }

    /// "Active" / "Expired" / "None", then the start and end instants.
    private var statusText: String {
        guard let grant = env.entitlements.complimentaryGrant else { return "None" }
        let state = grant.isActive(at: .now) ? "Active" : "Expired"
        let style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        return "\(state)\n\(grant.start.formatted(style))\n\(grant.endsAt.formatted(style))"
    }
}
#endif
