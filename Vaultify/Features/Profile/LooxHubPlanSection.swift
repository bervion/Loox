import SwiftUI

/// The hub's plan card (the §5.3 Profile "Gói Loox" discovery point), in three
/// states:
/// - Subscriber: "Your plan" + the PAID tier, then "Manage plan".
/// - Complimentary: "Your plan" Loox+ with "Free until <date>", then the Max
///   upgrade. The in-app grant is not a subscription, so there is nothing to
///   manage and no member seal (see `LooxComplimentaryGrant`).
/// - Free: the Max upgrade alone.
/// Every row opens `LooxPaywallScreen`, which itself branches on entitlement.
struct LooxHubPlanSection: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showPaywall = false

    private var entitlements: LooxEntitlementStore { env.entitlements }

    var body: some View {
        ProfileGroupCard {
            if entitlements.isSubscriber {
                planRow(tier: entitlements.paidTier, freeUntil: nil)
                ProfileRowDivider()
                actionRow("Manage plan", showsTile: false)
            } else if let endsAt = entitlements.complimentaryEndsAt {
                planRow(tier: LooxComplimentaryGrant.tier, freeUntil: endsAt)
                ProfileRowDivider()
                actionRow("Upgrade to Loox Max", showsTile: false)
            } else {
                actionRow("Upgrade to Loox Max", showsTile: true)
            }
        }
        .sheet(isPresented: $showPaywall) {
            NavigationStack { LooxPaywallScreen(context: .profile) }
        }
    }

    /// "Your plan" + tier name. The complimentary end date sits UNDER the
    /// label, not beside the tier, so the longest localized date (VI) wraps in
    /// its own column instead of squeezing the tier name.
    private func planRow(tier: LooxTier, freeUntil: Date?) -> some View {
        HStack(spacing: Space.s3) {
            ProfileRowTile(style: .brandMark)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Your plan").vaultType(.body).themedForeground()
                if let freeUntil {
                    Text("Free until \(LooxTrialCopy.endDate(freeUntil))")
                        .vaultType(.footnote)
                        .themedForeground(.secondaryBody)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Space.s2)
            Text(verbatim: tier.displayName).vaultType(.subhead).themedForeground(.secondaryBody)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
        .frame(minHeight: Metric.rowHeight)
        .accessibilityElement(children: .combine)
    }

    /// One tappable row into the paywall. The brand tile leads the card only
    /// when this row is the card's first (Free state).
    private func actionRow(_ title: LocalizedStringResource, showsTile: Bool) -> some View {
        Button { showPaywall = true } label: {
            HStack(spacing: Space.s3) {
                if showsTile { ProfileRowTile(style: .brandMark) }
                Text(title.inAppLocalized).vaultType(.body).themedForeground()
                Spacer(minLength: Space.s2)
                VaultIcon(Icons.chevronRight, size: 14).themedForeground(.tertiary)
            }
            .padding(.horizontal, Space.s4)
            .frame(minHeight: Metric.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
