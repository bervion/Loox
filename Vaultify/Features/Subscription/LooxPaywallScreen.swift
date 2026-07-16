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
        case .quickViewQuota: "Open on Computer limit reached for these 30 days"
        case .recipientLimit: "Your plan's sharing seats are all in use"
        case .watchtower: "Unlock the full Watchtower workflow"
        case .themes: "Unlock every accent and theme"
        }
        return base.inAppLocalized
    }
}

/// The purchase surface (proposal §5): Loox merchandising on top, the native
/// StoreKit subscription store below. Prices, periods and trial eligibility
/// all come from live `Product`s — nothing monetary is hardcoded. An existing
/// subscriber never sees the acquisition pitch (§5.3); they get the current
/// plan summary with Change plan and Manage subscription instead.
///
/// Dark until `LooxMembership.purchasesEnabled` — no entry point renders it
/// before the §12 launch gates pass.
struct LooxPaywallScreen: View {
    @Environment(AppEnvironment.self) private var env
    var context: LooxPaywallContext = .profile

    var body: some View {
        Group {
            if env.entitlements.tier > .free {
                LooxCurrentPlanView()
            } else {
                acquisition
            }
        }
        .background(Color(rgb: env.theme.active.groupedBackground).ignoresSafeArea())
    }

    // MARK: Acquisition (Free → paid)

    private var acquisition: some View {
        // Product order puts Max first (§5.1 — Max Annual is the protagonist);
        // StoreKit renders the plan/period choice, purchase, redemption and
        // localized disclosures natively.
        SubscriptionStoreView(productIDs: LooxProductID.all) {
            LooxPaywallMarketingHeader(context: context)
        }
        .subscriptionStoreControlStyle(.prominentPicker)
        .storeButton(.visible, for: .restorePurchases)
        .subscriptionStorePolicyDestination(url: LooxMembership.termsURL, for: .termsOfService)
        .subscriptionStorePolicyDestination(url: LooxMembership.privacyURL, for: .privacyPolicy)
        .onInAppPurchaseCompletion { _, result in
            // The entitlement itself lands through LooxEntitlementStore's
            // Transaction.updates listener (single grant path) — this is
            // feedback only. Pending (Ask to Buy) and cancel/failure stay in
            // StoreKit's own UI; a failure must never imply vault risk (§5.4).
            if case .success(.success(let verification)) = result,
               case .verified = verification {
                Haptics.success()
            }
        }
    }
}

/// Merchandising above the store controls: brand mark, context headline, and
/// the three concrete Max benefits (§5.1). Below them, a factual per-month
/// comparison line that renders only when live prices prove it (§4.3).
private struct LooxPaywallMarketingHeader: View {
    @Environment(AppEnvironment.self) private var env
    let context: LooxPaywallContext
    @State private var comparison: LooxPriceMath.AnnualVersusMonthly = .notComparable

    var body: some View {
        VStack(spacing: Space.s4) {
            Image("BrandSymbol")
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
                .padding(.top, Space.s4)
            Text(context.headline)
                .vaultType(.screenTitle)
                .themedForeground()
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: Space.s3) {
                benefit(Icons.mail, "Up to 200 private email aliases")
                benefit(Icons.organization, "Secure sharing with up to 10 people")
                benefit(Icons.watchtower, "Full Watchtower protection and fixes")
            }
            .padding(.vertical, Space.s2)
            if comparison != .notComparable {
                Text(comparison == .cheaperPerMonth
                     ? "Per month, Loox Max yearly costs less than Loox+ monthly"
                     : "Per month, Loox Max yearly costs about the same as Loox+ monthly")
                    .vaultType(.footnote)
                    .themedForeground(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, Space.gutter)
        .task { await loadComparison() }
    }

    private func benefit(_ icon: String, _ text: LocalizedStringResource) -> some View {
        HStack(spacing: Space.s3) {
            PolarisIcon(icon, size: Metric.iconInline)
                .themedForeground(.accentText)
            Text(text)
                .vaultType(.callout)
                .themedForeground()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A product-load failure is a store state, not an error surface — the
    /// comparison line simply stays hidden and StoreKit's own view retries.
    private func loadComparison() async {
        guard let products = try? await Product.products(
            for: [LooxProductID.maxAnnual, LooxProductID.plusMonthly]) else { return }
        guard let annual = products.first(where: { $0.id == LooxProductID.maxAnnual }),
              let monthly = products.first(where: { $0.id == LooxProductID.plusMonthly }) else { return }
        comparison = LooxPriceMath.compare(maxAnnual: annual.price, plusMonthly: monthly.price)
    }
}

/// Subscriber view: current plan, when the paid period ends, and the two
/// management actions. Plan changes and cancellation are Apple's flows —
/// upgrade/downgrade timing is Apple's decision, so no proration promises here.
private struct LooxCurrentPlanView: View {
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
                        Text(verbatim: env.entitlements.tier.displayName)
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
            SubscriptionStoreView(productIDs: LooxProductID.all)
                .subscriptionStoreControlStyle(.prominentPicker)
                .storeButton(.visible, for: .restorePurchases)
        }
    }

    private func manageRow(title: LocalizedStringResource) -> some View {
        HStack(spacing: Space.s3) {
            Text(title).vaultType(.body).themedForeground()
            Spacer(minLength: Space.s2)
            PolarisIcon(Icons.chevronRight, size: 14).themedForeground(.tertiary)
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
