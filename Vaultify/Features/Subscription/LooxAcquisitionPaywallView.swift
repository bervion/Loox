import SwiftUI
import StoreKit

/// Custom acquisition paywall in the iCloud+ upgrade-sheet idiom (owner
/// decision 260716): plain background, big brand mark, Year/Month segment,
/// gray plan cards with the selected one accent-ringed, an accent CTA pinned
/// to the bottom, and a liquid-glass Restore button. Purchases run through
/// StoreKit 2 `product.purchase()` directly; every price, period and trial
/// figure comes from the live `Product`s (§2.8 — nothing monetary hardcoded),
/// and the §5.2 disclosures render as text below the cards.
///
/// Max Annual is the protagonist (§5.1): Max card first and preselected,
/// Yearly preselected, one filled primary action.
struct LooxAcquisitionPaywallView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let context: LooxPaywallContext

    private enum LoadState { case loading, ready, failed }

    @State private var loadState: LoadState = .loading
    @State private var products: [String: Product] = [:]
    @State private var trialDays: Int?
    @State private var trialEligible = false
    @State private var selectedTier: LooxTier = .max
    @State private var yearly = true
    @State private var purchasing = false
    @State private var restoring = false
    @State private var purchasePending = false
    @State private var flowMessage: String?
    @State private var comparison: LooxPriceMath.AnnualVersusMonthly = .notComparable

    /// Wide iCloud+-style screen margins (owner request) — deliberately larger
    /// than `Space.gutter`; card interiors keep their own fixed padding.
    private static let margin = Space.s6

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s5) {
                header
                switch loadState {
                case .loading:
                    ProgressView()
                        .padding(.vertical, Space.s8)
                case .failed:
                    failedState
                case .ready:
                    planPicker
                }
            }
            .padding(.horizontal, Self.margin)
            .padding(.bottom, Space.s6)
        }
        .background(Color(rgb: env.theme.active.background).ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            if loadState == .ready { bottomBar }
        }
        .task { await load() }
        .alert(Text("Waiting for approval"), isPresented: $purchasePending) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Ask to Buy request sent. You can finish once it's approved.")
        }
        .alert(Text(verbatim: flowMessage ?? ""), isPresented: flowBinding) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: Header (big brand mark + headline + benefits)

    private var header: some View {
        VStack(spacing: Space.s4) {
            Image("BrandSymbol")
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
                .padding(.top, Space.s5)
            Text(context.headline)
                .vaultType(.screenTitle)
                .themedForeground()
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: Space.s3) {
                benefit(Icons.mail, "Up to 200 private email aliases")
                benefit(Icons.organization, "Secure sharing with up to 10 people")
                benefit(Icons.watchtower, "Full Watchtower protection and fixes")
            }
            .padding(.top, Space.s2)
        }
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Plans (segment + cards + disclosures)

    private var planPicker: some View {
        VStack(spacing: Space.s4) {
            Picker("", selection: $yearly) {
                Text("Yearly").tag(true)
                Text("Monthly").tag(false)
            }
            .pickerStyle(.segmented)
            .onChange(of: yearly) { _, _ in Haptics.selection() }

            VStack(spacing: Space.s3) {
                planCard(.max)
                planCard(.plus)
            }

            if comparison != .notComparable {
                Text(comparison == .cheaperPerMonth
                     ? "Per month, Loox Max yearly costs less than Loox+ monthly"
                     : "Per month, Loox Max yearly costs about the same as Loox+ monthly")
                    .vaultType(.footnote)
                    .themedForeground(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let product = product(for: selectedTier) {
                Text(verbatim: disclosureText(product))
                    .vaultType(.footnote)
                    .themedForeground(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, Space.s1)
            }
        }
    }

    private func planCard(_ tier: LooxTier) -> some View {
        let product = product(for: tier)
        let selected = selectedTier == tier
        return Button {
            guard selectedTier != tier else { return }
            selectedTier = tier
            Haptics.selection()
        } label: {
            HStack(alignment: .center, spacing: Space.s4) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(verbatim: tier.displayName)
                        .vaultType(.headline)
                        .themedForeground()
                    Text(tier == .max
                         ? "Full security workflow, sharing and services"
                         : "Personal security, maintained")
                        .vaultType(.footnote)
                        .themedForeground(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if tier == .max, yearly, trialEligible, let trialDays {
                        Text("\(trialDays) days free")
                            .vaultType(.caption)
                            .themedForeground(.accentText)
                            .padding(.horizontal, Space.s2)
                            .padding(.vertical, 3)
                            .background(Color(rgb: env.theme.active.accentSoft), in: Capsule())
                    }
                }
                Spacer(minLength: Space.s2)
                VStack(alignment: .trailing, spacing: 2) {
                    if let product {
                        // Total charged price stays the prominent figure; the
                        // per-month equivalent is secondary (§5.2).
                        Text(verbatim: product.displayPrice)
                            .vaultType(.headline)
                            .themedForeground()
                        if yearly {
                            Text("about \(perMonthDisplay(product)) a month")
                                .vaultType(.caption)
                                .themedForeground(.secondary)
                        }
                    }
                }
            }
            .padding(Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(selected ? Color(rgb: env.theme.active.accentSoft) : VaultColors.fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(selected ? Color(rgb: env.theme.active.accent) : .clear,
                                  lineWidth: 1.5)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var failedState: some View {
        VStack(spacing: Space.s3) {
            Text("Couldn't load plans. Check your connection and try again.")
                .vaultType(.subhead)
                .themedForeground(.secondary)
                .multilineTextAlignment(.center)
            Button { Task { await load() } } label: {
                Text("Try Again")
                    .vaultType(.body)
                    .themedForeground(.accentText)
                    .frame(minHeight: Metric.hitMin)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Space.s6)
    }

    // MARK: Bottom bar (CTA + glass Restore + policy links)

    private var bottomBar: some View {
        VStack(spacing: Space.s3) {
            Button { Task { await purchase() } } label: {
                Group {
                    if purchasing {
                        ProgressView()
                    } else {
                        Text(verbatim: ctaTitle)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.themedProminent)
            .disabled(purchasing || restoring || product(for: selectedTier) == nil)

            LooxGlassButton(title: "Restore Purchases", busy: restoring) {
                Task { await restore() }
            }
            .disabled(purchasing)

            HStack(spacing: Space.s6) {
                Link("Terms of Use", destination: LooxMembership.termsURL)
                Link("Privacy Policy", destination: LooxMembership.privacyURL)
            }
            .vaultType(.footnote)
            .tint(Color(rgb: env.theme.active.accentText))
        }
        .padding(.horizontal, Self.margin)
        .padding(.top, Space.s3)
        .padding(.bottom, Space.s2)
        .background(Color(rgb: env.theme.active.background).ignoresSafeArea())
    }

    private var ctaTitle: String {
        if isTrialSelection, let trialDays {
            return appString("Try free for \(trialDays) days")
        }
        return appString("Subscribe to \(selectedTier.displayName)")
    }

    private var isTrialSelection: Bool { selectedTier == .max && yearly && trialEligible }

    // MARK: Data

    private func product(for tier: LooxTier) -> Product? {
        switch (tier, yearly) {
        case (.max, true): return products[LooxProductID.maxAnnual]
        case (.max, false): return products[LooxProductID.maxMonthly]
        case (.plus, true): return products[LooxProductID.plusAnnual]
        case (.plus, false): return products[LooxProductID.plusMonthly]
        default: return nil
        }
    }

    private func perMonthDisplay(_ product: Product) -> String {
        LooxPriceMath.perMonth(annual: product.price).formatted(product.priceFormatStyle)
    }

    private func disclosureText(_ product: Product) -> String {
        if isTrialSelection, let trialDays {
            return appString("First \(trialDays) days free, then \(product.displayPrice) each year. Auto-renews until canceled. Cancel anytime in Settings.")
        }
        return yearly
            ? appString("Auto-renews at \(product.displayPrice) each year until canceled. Cancel anytime in Settings.")
            : appString("Auto-renews at \(product.displayPrice) each month until canceled. Cancel anytime in Settings.")
    }

    /// A product-load failure is a store state, not an error surface (§2.8):
    /// retryable, never fake prices, never implying vault risk.
    private func load() async {
        loadState = .loading
        do {
            let loaded = try await Product.products(for: LooxProductID.all)
            guard !loaded.isEmpty else {
                loadState = .failed
                return
            }
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            if let annual = products[LooxProductID.maxAnnual] {
                if let offer = annual.subscription?.introductoryOffer, offer.paymentMode == .freeTrial {
                    trialDays = Self.days(of: offer.period)
                    trialEligible = await annual.subscription?.isEligibleForIntroOffer ?? false
                }
                if let plusMonthly = products[LooxProductID.plusMonthly] {
                    comparison = LooxPriceMath.compare(maxAnnual: annual.price,
                                                       plusMonthly: plusMonthly.price)
                }
            }
            loadState = .ready
        } catch {
            loadState = .failed
        }
    }

    private static func days(of period: Product.SubscriptionPeriod) -> Int {
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        @unknown default: return period.value
        }
    }

    // MARK: Purchase / Restore

    private func purchase() async {
        guard let product = product(for: selectedTier), !purchasing else { return }
        purchasing = true
        defer { purchasing = false }
        do {
            // The backend integration phase adds
            // `purchase(options: [.appAccountToken(...)])` here (BE proposal B3).
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    flowMessage = appString("The purchase didn't go through. You have not been charged.")
                    return
                }
                await env.entitlements.refreshNow()
                await transaction.finish()
                Haptics.success()
                dismiss()
            case .pending:
                purchasePending = true
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            flowMessage = appString("The purchase didn't go through. You have not been charged.")
        }
    }

    private func restore() async {
        guard !restoring else { return }
        restoring = true
        defer { restoring = false }
        do {
            try await AppStore.sync()
        } catch {
            flowMessage = appString("Restore didn't finish. Try again.")
            return
        }
        await env.entitlements.refreshNow()
        if env.entitlements.tier > .free {
            Haptics.success()
            dismiss()
        } else {
            flowMessage = appString("Nothing to restore on this Apple Account.")
        }
    }

    private var flowBinding: Binding<Bool> {
        Binding(get: { flowMessage != nil }, set: { if !$0 { flowMessage = nil } })
    }
}

/// Liquid-glass secondary button (iOS 26 `.glass`), mirroring the
/// `VaultScreenHeader` availability/Reduce-Transparency ladder: material
/// capsule below iOS 26 or under Reduce Transparency's solid fallback.
private struct LooxGlassButton: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let title: LocalizedStringResource
    var busy = false
    let action: () -> Void

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26, macOS 26, *), !reduceTransparency {
            Button(action: action) { label }
                .buttonStyle(.glass)
                .disabled(busy)
        } else {
            fallback
        }
        #else
        fallback
        #endif
    }

    private var label: some View {
        Group {
            if busy {
                ProgressView()
            } else {
                Text(title).vaultType(.body).themedForeground()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s1)
    }

    private var fallback: some View {
        Button(action: action) {
            label
                .padding(.vertical, Space.s2)
                .frame(minHeight: Metric.hitMin)
                .background(fallbackFill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private var fallbackFill: AnyShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color(rgb: env.theme.active.surfaceFloatingSolid))
            : AnyShapeStyle(.regularMaterial)
    }
}
