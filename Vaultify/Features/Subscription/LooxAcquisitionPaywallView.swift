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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
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
    @State private var showLanding = false

    /// iCloud+-sheet screen margins (matched to the reference at 20pt);
    /// card interiors keep their own fixed padding.
    private static let margin = Space.s5

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
        // Prices are storefront-bound: before the first sandbox sign-in the
        // device answers from the DEFAULT storefront (USD), then the purchase
        // sheet attaches the sandbox account's real one (VND). Repricing on
        // storefront change keeps the paywall and the payment sheet telling
        // the same number — and covers real users switching regions too.
        .task {
            for await _ in Storefront.updates {
                await load()
            }
        }
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
            // One-shot brand reveal, same animation as the Security empty
            // state (owner request 260716) — the component collapses under
            // Reduce Motion; the headline right below carries the information.
            LooxSwirlAnimationView(mode: .reveal)
                .frame(width: 96, height: 96)
                .padding(.top, Space.s5)
                .accessibilityHidden(true)
            Text(context.headline)
                .vaultType(.screenTitle)
                .themedForeground()
                .multilineTextAlignment(.center)
            // The three benefits follow the SELECTED plan (quota-driven), so
            // switching cards immediately shows what Loox+ vs Max differ in.
            VStack(alignment: .leading, spacing: Space.s3) {
                benefit(Icons.mail, appString("Up to \(selectedQuotas.retainedAliases) private email aliases"))
                benefit(Icons.organization, sharingBenefit)
                benefit(Icons.watchtower, appString("Full Watchtower protection and fixes"))
            }
            .padding(.top, Space.s2)
            .animation(.default, value: selectedTier)

            Button { showLanding = true } label: {
                HStack(spacing: Space.s2) {
                    PolarisIcon(Icons.info, size: 15)
                    Text("Learn more about \(selectedTier.displayName)")
                        .vaultType(.subhead)
                }
                .foregroundStyle(LooxPlanTint.link(selectedTier))
                .frame(minHeight: Metric.hitMin)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .navigationDestination(isPresented: $showLanding) {
            LooxPlanLandingScreen(tier: selectedTier)
        }
    }

    private var selectedQuotas: LooxQuotas { selectedTier.quotas }

    private var sharingBenefit: String {
        let seats = selectedQuotas.outgoingRecipients
        return seats == 1
            ? appString("Share with one trusted person")
            : appString("Secure sharing with up to \(seats) people")
    }

    private func benefit(_ icon: String, _ text: String) -> some View {
        HStack(spacing: Space.s3) {
            // Round badge on the SELECTED plan's identity fill with an
            // on-tint glyph — the whole surface re-tints when the plan
            // changes (blue for Loox+, teal→green for Max).
            ZStack {
                Circle().fill(LooxPlanTint.fill(selectedTier))
                PolarisIcon(icon, size: 16)
                    .foregroundStyle(LooxPlanTint.onFill(selectedTier))
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
            Text(verbatim: text)
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

            // In scrollable content by design: Apple only requires these links
            // be reachable from the purchase screen (3.1.2), not pinned —
            // the iCloud+ sheet itself scrolls them with the disclosure.
            HStack(spacing: Space.s6) {
                Link("Terms of Use", destination: LooxMembership.termsURL)
                Link("Privacy Policy", destination: LooxMembership.privacyURL)
            }
            .vaultType(.footnote)
            .tint(LooxPlanTint.link(selectedTier))
            .frame(maxWidth: .infinity)
            .padding(.top, Space.s2)
        }
    }

    /// One plan card in the iCloud+ storage-card idiom: light gray in BOTH
    /// states; selection shows only the thick pinned-blue ring plus the
    /// blue check badge on the title row.
    private func planCard(_ tier: LooxTier) -> some View {
        let product = product(for: tier)
        let selected = selectedTier == tier
        return Button {
            guard selectedTier != tier else { return }
            selectedTier = tier
            Haptics.selection()
        } label: {
            HStack(alignment: .top, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    LooxTierLabel(tier: tier, badgeHeight: 18)
                        .vaultType(.headline)
                        .themedForeground()
                    if let product {
                        // Total charged price stays the prominent figure; the
                        // per-month equivalent is a secondary caption (§5.2).
                        Text(yearly ? "\(product.displayPrice) a year"
                                    : "\(product.displayPrice) a month")
                            .vaultType(.body)
                            .themedForeground()
                        if yearly {
                            Text("about \(perMonthDisplay(product)) a month")
                                .vaultType(.caption)
                                .themedForeground(.secondary)
                        }
                    }
                    Text(tier == .max
                         ? "Full security workflow, sharing and services"
                         : "Personal security, maintained")
                        .vaultType(.footnote)
                        .themedForeground(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if tier == .max, yearly, trialEligible, let trialDays {
                        trialPill(days: trialDays)
                    }
                }
                Spacer(minLength: Space.s2)
                if selected {
                    ZStack {
                        Circle().fill(LooxPlanTint.fill(tier))
                        // On-tint badge glyph — the documented fixed-tile
                        // exemption class (each identity fill clears the 3:1
                        // floor for its on-tint color by construction).
                        PolarisIcon(Icons.check, size: 13)
                            .foregroundStyle(LooxPlanTint.onFill(tier))
                    }
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                }
            }
            .padding(Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(Self.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(selected ? LooxPlanTint.fill(tier) : AnyShapeStyle(.clear),
                                  lineWidth: 2)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// Fixed light-gray card fill mirroring the iCloud+ storage cards
    /// (systemGray6-class light / elevated dark) — a documented fixed-tile
    /// pair like `ProfileRowTile.systemGrayTile`: the themed `controlBackground`
    /// read too dark against this screen's plain background (owner 260716).
    private static let cardFill = VaultColors.dynamic(light: 0xF2F2F7, dark: 0x1C1C1E)

    /// Trial pill on Max-identity liquid glass (the pill only exists on the
    /// Max card) — solid identity fill below iOS 26 or under Reduce
    /// Transparency; the on-tint label follows the identity convention.
    @ViewBuilder private func trialPill(days: Int) -> some View {
        let label = Text("\(days) days free")
            .vaultType(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(LooxMaxTint.onTint)
            .padding(.horizontal, Space.s3)
            .padding(.vertical, 4)
        #if compiler(>=6.2)
        if #available(iOS 26, macOS 26, *), !reduceTransparency {
            label.glassEffect(.regular.tint(LooxMaxTint.pillTint), in: Capsule())
        } else {
            label.background(LooxMaxTint.pillTint, in: Capsule())
        }
        #else
        label.background(LooxMaxTint.pillTint, in: Capsule())
        #endif
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
            Button { Task { await purchase() } } label: { ctaLabel }
                .buttonStyle(LooxPlanProminentButtonStyle(tier: selectedTier))
                .disabled(purchasing || restoring || product(for: selectedTier) == nil)
                .accessibilityLabel(Text(verbatim: ctaTitle))

            LooxGlassButton(title: "Restore Purchases", busy: restoring) {
                Task { await restore() }
            }
            .disabled(purchasing)
        }
        .padding(.horizontal, Self.margin)
        .padding(.top, Space.s3)
        .padding(.bottom, Space.s2)
        .background(Color(rgb: env.theme.active.background).ignoresSafeArea())
    }

    /// CTA content: the Max selection renders the brand-plus-badge lockup
    /// ("Subscribe to Loox [MAX]"); everything else stays plain text.
    @ViewBuilder private var ctaLabel: some View {
        if purchasing {
            ProgressView().tint(LooxPlanTint.onFill(selectedTier))
        } else if isTrialSelection, let trialDays {
            Text("Try free for \(trialDays) days")
        } else if selectedTier == .max {
            // Sentence-tight lockup: word gap only, compact glow-free badge —
            // the floating chip read disconnected from the label.
            HStack(spacing: 6) {
                Text("Subscribe to")
                LooxTierLabel(tier: .max, badgeHeight: 19, compactBadge: true)
            }
        } else {
            Text(verbatim: appString("Subscribe to \(selectedTier.displayName)"))
        }
    }

    /// Plain-text mirror of the CTA for assistive tech.
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
        AnalyticsEngine.shared.log(.purchaseStarted(productID: product.id))
        do {
            // The appAccountToken IS the pseudonymous billing identity the
            // backend keys everything on (contract §1) — set from the very
            // first purchase, always.
            let result = try await product.purchase(
                options: [.appAccountToken(LooxSubscriptionAccountToken.loadOrCreate())])
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    AnalyticsEngine.shared.log(.purchaseFailed(productID: product.id, reason: "verification"))
                    flowMessage = appString("The purchase didn't go through. You have not been charged.")
                    return
                }
                AnalyticsEngine.shared.log(.purchaseCompleted(productID: product.id))
                // The verified transaction in hand IS the entitlement — grant
                // the tier from it directly; `currentEntitlements` can trail
                // a fresh purchase (sandbox especially).
                env.entitlements.applyVerified(transaction)
                await env.entitlements.refreshNow()
                await transaction.finish()
                // Attach trigger (1): purchase success → backend learns the
                // subscription (dormant plumbing). Fire-and-forget — a slow
                // or waking backend must never hold the paid-and-confirmed
                // moment hostage (it blocked the success haptic + dismiss
                // for up to a minute on-device).
                Task { await env.entitlementCoordinator.attachNow() }
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
            AnalyticsEngine.shared.log(.purchaseFailed(productID: product.id, reason: "error"))
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
            // Attach trigger (2): restore on this device — the coordinator
            // adopts the appAccountToken from the verified transaction, so
            // every install converges on the purchase's identity.
            // Fire-and-forget, same rule as the purchase path.
            Task { await env.entitlementCoordinator.attachNow() }
            AnalyticsEngine.shared.log(.purchaseRestored)
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

/// The paywall's pinned Design-System blue — this commerce surface reads
/// iCloud-blue for EVERY user accent (owner decision 260716), so it must not
/// follow the live theme accent (a mono/graphite accent would render the CTA
/// black). Derived from the DS blue preset, deepened minimally by
/// `ensureContrast` so a WHITE label clears the 3:1 control floor — the same
/// non-destructive guard the theme itself applies to accents ("Loox may
/// adjust the selected color slightly to keep text and controls readable").
enum LooxPaywallBlue {
    static let lightHex = RGBMath.ensureContrast(AccentPreset.blue.lightRGB, on: 0xFFFFFF, floor: 3.0)
    static let darkHex = RGBMath.ensureContrast(AccentPreset.blue.darkRGB, on: 0xFFFFFF, floor: 3.0)
    static var color: Color { VaultColors.dynamic(light: lightHex, dark: darkHex) }
}

/// Full-width capsule CTA on the SELECTED plan's identity fill (pinned blue
/// for Loox+, the teal→green Max gradient for Max) with the matching on-tint
/// label — the documented fixed-tile exemption class.
private struct LooxPlanProminentButtonStyle: ButtonStyle {
    let tier: LooxTier
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .vaultType(.body)
            .fontWeight(.semibold)
            .foregroundStyle(LooxPlanTint.onFill(tier))
            .frame(maxWidth: .infinity)
            .frame(minHeight: Metric.controlLarge)
            .background(LooxPlanTint.fill(tier), in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.5)
            .scaleEffect(configuration.isPressed ? Motion.pressScale : 1)
            .contentShape(Capsule())
    }
}

/// Liquid-glass secondary button. Deliberately NOT `.buttonStyle(.glass)`:
/// that style adds its own insets around the label, so it can never match the
/// CTA's height exactly. Instead the label uses the SAME frame recipe as
/// `LooxBlueProminentButtonStyle` (maxWidth + `Metric.controlLarge`) and the
/// glass is applied as a background via `.glassEffect(_:in:)` — the primitive
/// `VaultScreenHeader` already uses — so the two bottom buttons are equal by
/// construction. Material capsule below iOS 26; solid under Reduce Transparency.
private struct LooxGlassButton: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let title: LocalizedStringResource
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) { core }
            .buttonStyle(LooxPressFeedbackStyle())
            .disabled(busy)
    }

    @ViewBuilder private var core: some View {
        #if compiler(>=6.2)
        if #available(iOS 26, macOS 26, *), !reduceTransparency {
            label.glassEffect(.regular, in: Capsule())
        } else {
            label.background(fallbackFill, in: Capsule())
        }
        #else
        label.background(fallbackFill, in: Capsule())
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
        // Identical box math to the blue CTA (frame → shape background, no
        // extra padding) so the bottom pair reads as one equal-height stack.
        .frame(maxWidth: .infinity)
        .frame(minHeight: Metric.controlLarge)
        .contentShape(Capsule())
    }

    private var fallbackFill: AnyShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color(rgb: env.theme.active.surfaceFloatingSolid))
            : AnyShapeStyle(.regularMaterial)
    }
}

/// Press feedback only (opacity + scale) — all sizing/chrome lives on the
/// label so custom-shaped buttons keep exact control of their bounds.
private struct LooxPressFeedbackStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? Motion.pressScale : 1)
    }
}
