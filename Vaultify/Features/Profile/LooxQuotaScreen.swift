import SwiftUI

/// Plan-limits detail (pushed from the hub's "Plan limits" row — the iCloud+
/// storage-detail idiom): one row per quota with live usage, the frozen
/// denominator from `LooxQuotas`, and a thin consumption bar. Display-only —
/// enforcement stays with the gates and, later, the backend counter.
struct LooxQuotaScreen: View {
    @Environment(AppEnvironment.self) private var env

    private var tier: LooxTier { env.entitlements.tier }
    private var quotas: LooxQuotas { tier.quotas }

    private static let rolling30d: TimeInterval = 30 * 24 * 3600

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s2) {
                ProfileGroupCard {
                    quotaRow(icon: Icons.mail, tint: SettingsBadgeTint.teal,
                             title: "Private Email", used: retainedAliasCount,
                             cap: quotas.retainedAliases)
                    ProfileRowDivider()
                    quotaRow(icon: Icons.share, tint: SettingsBadgeTint.green,
                             title: "Share Links", used: linkCreates30d,
                             cap: quotas.linkCreates30d)
                    ProfileRowDivider()
                    quotaRow(icon: Icons.scanCode, tint: SettingsBadgeTint.indigo,
                             title: "Send to Browser", used: quickViewCompletions30d,
                             cap: quotas.quickViewApprovals30d)
                    ProfileRowDivider()
                    quotaRow(icon: Icons.organization, tint: SettingsBadgeTint.orange,
                             title: "Sharing", used: outgoingRecipientCount,
                             cap: quotas.outgoingRecipients)
                    ProfileRowDivider()
                    quotaRow(icon: Icons.person, tint: SettingsBadgeTint.blue,
                             title: "Profiles", used: env.repository.personas.count,
                             cap: quotas.personas)
                }
                Text("Share Links and Send to Browser count the last 30 days.")
                    .vaultType(.footnote)
                    .themedForeground(.secondary)
                    .padding(.horizontal, Space.s2)
                    .padding(.top, Space.s1)
            }
            .padding(Space.gutter)
        }
        .background(Color(rgb: env.theme.active.groupedBackground).ignoresSafeArea())
        .navigationTitle("Plan limits")
        .platformNavigationBarTitleDisplayMode(.inline)
    }

    /// One quota row: badge + title + trailing "x/y" (or unlimited), with the
    /// consumption bar underneath. `cap == nil` means no product cap (Max
    /// profiles) — no bar, since there is nothing to fill.
    private func quotaRow(icon: String, tint: Color, title: LocalizedStringResource,
                          used: Int, cap: Int?) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s3) {
                SettingsIconBadge(icon: icon, tint: tint)
                Text(title).vaultType(.body).themedForeground()
                Spacer(minLength: Space.s2)
                Text(verbatim: cap.map { "\(used)/\($0)" } ?? appString("Unlimited"))
                    .vaultType(.subhead)
                    .themedForeground(.secondary)
                    .monospacedDigit()
            }
            if let cap, cap > 0 {
                LooxQuotaBar(fraction: Double(used) / Double(cap))
                    // Align the bar with the text column, past the badge.
                    .padding(.leading, 29 + Space.s3)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    // MARK: Live usage counts (same device-local sources as the hub grid)

    private var retainedAliasCount: Int {
        env.repository.aliases.filter { $0.status == .active || $0.status == .paused }.count
    }

    private var linkCreates30d: Int {
        let cutoff = Date.now.addingTimeInterval(-Self.rolling30d)
        return env.looxLinks.records.records.filter { $0.createdAt >= cutoff }.count
    }

    private var quickViewCompletions30d: Int {
        let cutoff = Date.now.addingTimeInterval(-Self.rolling30d)
        return env.quickViewHistory.rows.filter { $0.result == .completed && $0.timestamp >= cutoff }.count
    }

    private var outgoingRecipientCount: Int {
        Set(env.sharingStore.shares.filter { $0.status == .active }.map(\.recipientLabel)).count
    }
}
