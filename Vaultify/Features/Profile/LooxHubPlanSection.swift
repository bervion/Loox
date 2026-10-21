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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showPaywall = false

    private var entitlements: LooxEntitlementStore { env.entitlements }

    /// Accessibility text sizes stack the plan row, so its labels start at the
    /// card edge like the action row below; the divider follows them there.
    private var divider: some View {
        ProfileRowDivider(leadingInset: dynamicTypeSize.isAccessibilitySize ? Space.s4 : nil)
    }

    var body: some View {
        ProfileGroupCard {
            if entitlements.isSubscriber {
                planRow(tier: entitlements.paidTier, freeUntil: nil)
                divider
                actionRow("Manage plan", showsTile: false)
            } else if let endsAt = entitlements.complimentaryEndsAt {
                planRow(tier: LooxComplimentaryGrant.tier, freeUntil: endsAt)
                divider
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
    /// its own column instead of squeezing the tier name. At accessibility
    /// sizes the middle column would be a few words wide, so the tile and tier
    /// share the top line and the labels take the full card width below
    /// (owner 261021).
    private func planRow(tier: LooxTier, freeUntil: Date?) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Space.s2) {
                    HStack(spacing: Space.s3) {
                        ProfileRowTile(style: .brandMark)
                        Spacer(minLength: Space.s2)
                        tierName(tier)
                    }
                    planLabels(freeUntil: freeUntil)
                }
            } else {
                HStack(spacing: Space.s3) {
                    ProfileRowTile(style: .brandMark)
                    planLabels(freeUntil: freeUntil)
                    Spacer(minLength: Space.s2)
                    tierName(tier)
                }
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
        .frame(minHeight: Metric.rowHeight)
        .accessibilityElement(children: .combine)
    }

    private func planLabels(freeUntil: Date?) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text("Your plan").vaultType(.body).themedForeground()
            if let freeUntil {
                Text("Free until \(LooxTrialCopy.endDate(freeUntil))")
                    .vaultType(.footnote)
                    .themedForeground(.secondaryBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tierName(_ tier: LooxTier) -> some View {
        Text(verbatim: tier.displayName).vaultType(.subhead).themedForeground(.secondaryBody)
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
