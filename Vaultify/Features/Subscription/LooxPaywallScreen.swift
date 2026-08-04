import SwiftUI
import StoreKit

/// Where the paywall was invoked from (proposal §5.3). The context picks the
/// one-line headline only — behavior is identical everywhere, so App Review
/// always sees the same deterministic surface. `Identifiable` so gate call
/// sites can present it with `.sheet(item:)`.
enum LooxPaywallContext: String, Identifiable {
    case profile
    case personaLimit
    case aliasLimit
    case linkQuota
    case quickViewQuota
    case recipientLimit
    case watchtower
    case themes

    var id: String { rawValue }

    var headline: LocalizedStringResource {
        let base: LocalizedStringResource = switch self {
        case .profile: "Do more with Loox"
        case .personaLimit: "You've used every profile in your plan"
        case .aliasLimit: "You've used every email alias in your plan"
        case .linkQuota: "Share link limit reached for these 30 days"
        case .quickViewQuota: "Send to Browser limit reached for these 30 days"
        case .recipientLimit: "Your plan's sharing seats are all in use"
        case .watchtower: "Unlock the full Watchtower workflow"
        case .themes: "Unlock every accent and theme"
        }
        return base.inAppLocalized
    }
}

/// The purchase surface (proposal §5): custom iCloud+-style acquisition layout
/// (owner decision 260716 — plain background, gray plan cards, Year/Month
/// segment, accent CTA pinned at the bottom, glass Restore) driven by live
/// `Product`s; prices, periods and trial eligibility are never hardcoded. An
/// existing subscriber never sees the acquisition pitch (§5.3); they get the
/// current plan summary with Change plan and Manage subscription instead.
///
/// Dark until purchases are enabled (`LooxEntitlementStore.purchasesEnabled`:
/// the launch flag, or a beta environment — TestFlight/App Review) — no entry
/// point renders it for App Store users before the §12 gates pass.
struct LooxPaywallScreen: View {
    @Environment(AppEnvironment.self) private var env
    var context: LooxPaywallContext = .profile

    var body: some View {
        Group {
            if env.entitlements.tier > .free {
                LooxCurrentPlanView()
                    .background(Color(rgb: env.theme.active.groupedBackground).ignoresSafeArea())
            } else {
                LooxAcquisitionPaywallView(context: context)
                    .onAppear { AnalyticsEngine.shared.log(.paywallShown(source: context.rawValue)) }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { SheetDismissButton("Close") }
        }
    }
}

/// Subscriber view: current plan, when the paid period ends, and the two
/// management actions. Plan changes and cancellation are Apple's flows —
/// upgrade/downgrade timing is Apple's decision, so no proration promises here.
struct LooxCurrentPlanView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var periodEnd: Date?
    @State private var showManageSheet = false
    @State private var showChangePlan = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s6) {
                ProfileGroupCard {
                    HStack(spacing: Space.s3) {
                        ProfileRowTile(style: .brandMark)
                        Text("Your plan").vaultType(.body).themedForeground()
                        Spacer(minLength: Space.s2)
                        LooxTierLabel(tier: env.entitlements.tier, badgeHeight: 15)
                            .vaultType(.subhead).themedForeground(.secondary)
                    }
                    .padding(.horizontal, Space.s4)
                    .frame(minHeight: Metric.rowHeight)
                    if let periodEnd {
                        ProfileRowDivider()
                        HStack {
                            Text("Current period ends \(periodEnd.formatted(date: .abbreviated, time: .omitted))")
                                .vaultType(.subhead).themedForeground(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, Space.s4)
                        .frame(minHeight: Metric.rowHeight)
                    }
                }
                ProfileGroupCard {
                    Button { showChangePlan = true } label: {
                        manageRow(title: "Change plan")
                    }
                    .buttonStyle(.plain)
                    ProfileRowDivider()
                    manageSubscriptionRow
                }
            }
            .padding(Space.gutter)
        }
        .task { await loadPeriodEnd() }
        .sheet(isPresented: $showChangePlan) {
            // Plain store view — StoreKit marks the current plan and runs the
            // upgrade/downgrade flow; no acquisition marketing for subscribers.
            //
            // This is a purchase screen of its own, so it carries the same
            // Terms and Privacy links as the acquisition paywall (3.1.2):
            // `.policies` renders StoreKit's own pair of buttons and the two
            // destinations say where they go. Both URLs follow the in-app
            // language.
            SubscriptionStoreView(productIDs: LooxProductID.all)
                .subscriptionStoreControlStyle(.prominentPicker)
                .storeButton(.visible, for: .restorePurchases, .policies)
                .subscriptionStorePolicyDestination(url: LooxMembership.termsURL,
                                                    for: .termsOfService)
                .subscriptionStorePolicyDestination(url: LooxMembership.privacyURL,
                                                    for: .privacyPolicy)
        }
    }

    private func manageRow(title: LocalizedStringResource) -> some View {
        HStack(spacing: Space.s3) {
            Text(title).vaultType(.body).themedForeground()
            Spacer(minLength: Space.s2)
            VaultIcon(Icons.chevronRight, size: 14).themedForeground(.tertiary)
        }
        .padding(.horizontal, Space.s4)
        .frame(minHeight: Metric.rowHeight)
        .contentShape(.rect)
    }

    /// Apple's manage-subscription surface: a sheet on iOS; macOS has no sheet
    /// API, so the App Store subscriptions page opens instead.
    @ViewBuilder private var manageSubscriptionRow: some View {
        #if os(iOS)
        Button { showManageSheet = true } label: {
            manageRow(title: "Manage subscription")
        }
        .buttonStyle(.plain)
        .manageSubscriptionsSheet(isPresented: $showManageSheet)
        #else
        Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
            manageRow(title: "Manage subscription")
        }
        .buttonStyle(.plain)
        #endif
    }

    /// The end of the current paid period from the verified entitlement —
    /// factual whether or not auto-renew is on (renew vs expire is Apple's
    /// sheet's job to explain).
    private func loadPeriodEnd() async {
        var latest: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil,
                  LooxProductID.tier(for: transaction.productID) != nil else { continue }
            if let expiry = transaction.expirationDate, expiry > (latest ?? .distantPast) {
                latest = expiry
            }
        }
        periodEnd = latest
    }
}
