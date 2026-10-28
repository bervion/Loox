import Foundation
import os
import StoreKit

/// Diagnostic logger for beta purchase-access resolution. Booleans and
/// environment names only — never receipts or transaction payloads.
private let subscriptionLog = Logger(subsystem: "com.bervion.vaultify", category: "subscription")

/// Client-side source of truth for the user's Loox tier, from exactly two
/// inputs: verified StoreKit 2 transactions (`storeTier`) and the device-local
/// complimentary Loox+ floor (`LooxComplimentaryGrant`). Nothing else
/// (CloudKit flags, UserDefaults, UI state) may decide tier, and `storeTier`
/// alone answers "is this user paying" (`paidTier` / `isSubscriber`). The
/// grant never reaches the backend: attach and payload stay StoreKit-only.
///
/// Lifecycle (proposal §7.5): prime from `Transaction.currentEntitlements` at
/// launch, then follow `Transaction.updates` for the whole process lifetime so
/// purchases, renewals, upgrades, refunds and Ask-to-Buy resolutions land
/// without a restart. Only `.verified` results count; a transaction is finished
/// strictly AFTER the local entitlement is recomputed.
///
/// Entitlement state must never touch vault data — this store only ever
/// changes what the UI offers, never what the vault contains.
@MainActor @Observable final class LooxEntitlementStore {
    @ObservationIgnored private let defaults: UserDefaults

    /// Tier granted by verified App Store transactions. Free when none.
    /// `Transaction.currentEntitlements` is local device state (it already
    /// reflects grace periods and does not require the network), so recomputing
    /// from it — including down to Free after a real expiry — is always safe.
    private(set) var storeTier: LooxTier = .free

    /// The tier the user PAYS for: the DEBUG override, otherwise `storeTier`.
    /// Drives "Your plan", the member seal and paywall routing.
    var paidTier: LooxTier {
        #if DEBUG
        if let debugTierOverride { return debugTierOverride }
        #endif
        return storeTier
    }

    /// A verified StoreKit plan (the Apple Max trial included). Complimentary
    /// Loox+ is not a subscription: Restore, "Manage plan" and the seal key
    /// off this, never off `tier`.
    var isSubscriber: Bool { paidTier > .free }

    /// The effective tier the app renders and gates on: the DEBUG override,
    /// otherwise the higher of `storeTier` and the active complimentary grant.
    var tier: LooxTier {
        #if DEBUG
        if let debugTierOverride { return debugTierOverride }
        #endif
        return complimentaryActive ? Swift.max(storeTier, LooxComplimentaryGrant.tier) : storeTier
    }

    /// The grant's end date, only while the grant is what gives the user
    /// Loox+ ("Free until" copy, the Loox+ billing note, analytics).
    var complimentaryEndsAt: Date? {
        guard complimentaryActive, !isSubscriber, tier == LooxComplimentaryGrant.tier else { return nil }
        return complimentaryGrant?.endsAt
    }

    /// The last resolved grant (kept across a locked-Keychain resolve).
    private(set) var complimentaryGrant: LooxComplimentaryGrant?
    /// `complimentaryGrant.isActive` at the last resolve. Cached so getters
    /// never read `Date.now`; `resolveComplimentary` refreshes it on launch
    /// and every foreground.
    private(set) var complimentaryActive = false
    /// nil = never touch the Keychain (previews, hosted tests).
    @ObservationIgnored private let complimentaryStore: LooxComplimentaryGrantStore?

    /// Whether purchase surfaces render (paywall, plan section, gate sheets).
    /// Commerce is live (owner 261021), so this is `launchEnabled`. The beta
    /// path (TestFlight, App Review) only matters if launch is ever switched
    /// back off; `LooxMembership.betaPreviewEnabled` darkens it too.
    var purchasesEnabled: Bool {
        LooxMembership.launchEnabled || (LooxMembership.betaPreviewEnabled && betaPurchaseAccess)
    }

    /// `AppTransaction.environment != .production` — the supported signal for
    /// TestFlight/App Review (`.sandbox`). Resolved once at start on RELEASE
    /// builds, and only while `launchEnabled` is off and
    /// `LooxMembership.betaPreviewEnabled` is on (store-distributed installs
    /// answer from the store record; anything without store context throws
    /// and stays false — dark is the safe default).
    private(set) var betaPurchaseAccess = false

    #if DEBUG
    /// Dev/simulator override so tier-dependent UI is testable without App
    /// Store Connect products. `nil` follows StoreKit. Debug menu only.
    var debugTierOverride: LooxTier? {
        didSet {
            if let debugTierOverride {
                defaults.set(debugTierOverride.rawValue, forKey: Self.debugOverrideKey)
            } else {
                defaults.removeObject(forKey: Self.debugOverrideKey)
            }
        }
    }
    private static let debugOverrideKey = "debug.looxTierOverride"
    #endif

    /// Fired after each VERIFIED transaction lands (purchase, renewal,
    /// restore) — the entitlement coordinator hangs its attach trigger here.
    @ObservationIgnored var onVerifiedTransactionUpdate: (() -> Void)?

    /// Fired when an analytics input changes: `storeTier`, `complimentaryActive`,
    /// and once after the first StoreKit refresh (so a subscriber is never
    /// reported as free from the pre-refresh launch value).
    @ObservationIgnored var onTierInputsChanged: (() -> Void)?
    @ObservationIgnored private var didFirstRefresh = false

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard,
         complimentaryStore: LooxComplimentaryGrantStore? = .keychain) {
        self.defaults = defaults
        self.complimentaryStore = complimentaryStore
        #if DEBUG
        if defaults.object(forKey: Self.debugOverrideKey) != nil {
            debugTierOverride = LooxTier(rawValue: defaults.integer(forKey: Self.debugOverrideKey))
        }
        #endif
    }

    /// Prime the tier and keep following transaction updates. Idempotent;
    /// called once from the composition root at launch.
    func start() {
        // Synchronous and first, so the first frame already shows Loox+.
        resolveComplimentary()
        guard updatesTask == nil else { return }
        #if !DEBUG
        // Live commerce, or the preview switch off: the environment is never
        // probed (no AppTransaction request, nothing to log).
        if !LooxMembership.launchEnabled, LooxMembership.betaPreviewEnabled {
            Task { [weak self] in await self?.resolveBetaPurchaseAccess() }
        }
        #endif
        updatesTask = Task { [weak self] in
            await self?.refresh()
            for await update in Transaction.updates {
                guard let self else { return }
                await self.refresh()
                if case .verified(let transaction) = update {
                    await transaction.finish()
                    self.onVerifiedTransactionUpdate?()
                }
            }
        }
    }

    /// On-demand recompute for flows that just changed entitlements themselves
    /// (the paywall's `product.purchase()` result, Restore Purchases) — the
    /// caller finishes its transaction AFTER this returns, keeping the
    /// finish-after-grant order.
    func refreshNow() async {
        await refresh()
    }

    /// Re-read the grant (launch, every foreground). A nil resolve (locked
    /// device: the Keychain read throws) keeps the cached grant and only
    /// re-checks its expiry, so day 750 passing while locked still lands.
    func resolveComplimentary(now: Date = .now) {
        guard let complimentaryStore else { return }
        if let grant = complimentaryStore.resolve(now: now), grant != complimentaryGrant {
            complimentaryGrant = grant
        }
        setComplimentaryActive(complimentaryGrant?.isActive(at: now) ?? false)
    }

    private func setComplimentaryActive(_ active: Bool) {
        guard active != complimentaryActive else { return }
        complimentaryActive = active
        onTierInputsChanged?()
    }

    private func setStoreTier(_ tier: LooxTier) {
        guard tier != storeTier else { return }
        storeTier = tier
        onTierInputsChanged?()
    }

    #if DEBUG
    /// Settings → Debug: rewrite the REAL grant item, then re-resolve. nil
    /// deletes it and clears the cache WITHOUT re-resolving, so the absent
    /// state is visible until the next foreground mints a fresh start.
    func debugSetComplimentaryStart(_ start: Date?) {
        complimentaryStore?.debugOverwrite(start: start)
        guard start != nil else {
            complimentaryGrant = nil
            return setComplimentaryActive(false)
        }
        resolveComplimentary()
    }
    #endif

    #if !DEBUG
    /// TestFlight/App Review detection, layered — any ONE signal opens beta
    /// purchase surfaces; none marks production. Only consulted while
    /// `LooxMembership.launchEnabled` is off:
    /// 1. The receipt URL NAME, synchronous and offline-safe: sandbox
    ///    (TestFlight) installs point at "sandboxReceipt" even when the
    ///    legacy receipt FILE is absent — the original fileExists pre-check
    ///    went dark exactly there (observed on-device 260717).
    /// 2. `AppTransaction.shared` environment, retried briefly: the previous
    ///    one-shot attempt could fail on a launch-time hiccup (network,
    ///    App Store session) and leave every surface dark until the next
    ///    cold launch, with nothing logged to say why.
    private func resolveBetaPurchaseAccess() async {
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
            subscriptionLog.log("beta access ON: sandbox receipt URL")
            betaPurchaseAccess = true
            return
        }
        for attempt in 1...3 {
            do {
                let result = try await AppTransaction.shared
                guard case .verified(let appTransaction) = result else {
                    subscriptionLog.error("beta access OFF: app transaction unverified")
                    return
                }
                let beta = appTransaction.environment != .production
                subscriptionLog.log("beta access \(beta ? "ON" : "OFF", privacy: .public): environment \(appTransaction.environment.rawValue, privacy: .public)")
                betaPurchaseAccess = beta
                return
            } catch {
                subscriptionLog.error("beta access attempt \(attempt, privacy: .public)/3 failed: \(String(describing: error), privacy: .public)")
                if attempt < 3 { try? await Task.sleep(for: .seconds(attempt == 1 ? 5 : 20)) }
            }
        }
    }
    #endif

    /// Fold ONE just-verified transaction into the tier immediately. The
    /// paywall holds the verified purchase result in hand — deriving from it
    /// never races `Transaction.currentEntitlements` freshness, which lags in
    /// sandbox right after a purchase and left a successful buy rendering as
    /// Free (observed on-device 260717). Only ever upgrades; downgrades stay
    /// the entitlement stream's job.
    func applyVerified(_ transaction: StoreKit.Transaction) {
        guard transaction.revocationDate == nil else { return }
        let tier = LooxProductID.resolveTier(from: [transaction.productID])
        if tier > storeTier {
            subscriptionLog.log("tier from in-hand transaction: \(String(describing: tier), privacy: .public)")
            setStoreTier(tier)
            lastInHandApplyAt = .now
        }
    }

    /// Re-read StoreKit when the app comes back to the foreground. A launch
    /// read can come back without a live subscription (the process may start
    /// before the user opens it), and nothing else would correct it until a
    /// transaction update arrives: a Max subscriber then rendered as the
    /// complimentary Loox+ on every relaunch (owner report 261028). No-op until
    /// `start()` ran, so isolated tests never touch StoreKit.
    func refreshOnForeground() {
        guard updatesTask != nil else { return }
        Task { await refresh() }
    }

    /// Recompute the tier from two verified sources (highest wins,
    /// `LooxProductID.resolveTier`): `Transaction.currentEntitlements`, and
    /// the subscription group's renewal status, which reports the group's
    /// latest transaction (the Max one after an upgrade) with its live state.
    /// Unverified results and revoked transactions never grant anything.
    private func refresh() async {
        var productIDs: [String] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil else { continue }
            productIDs.append(transaction.productID)
        }
        let entitlementCount = productIDs.count
        productIDs += await Self.groupStatusProductIDs()
        let resolved = LooxProductID.resolveTier(from: productIDs)
        subscriptionLog.log("refresh: \(entitlementCount, privacy: .public) entitlements, \(productIDs.count - entitlementCount, privacy: .public) group status → \(String(describing: resolved), privacy: .public)")
        // A just-purchased transaction can trail `currentEntitlements` for a
        // beat (sandbox especially) — an empty read must not stomp the tier
        // `applyVerified` just granted from the in-hand verified result. Real
        // expiry/refund downgrades still land: those reads carry the OTHER
        // still-live entitlements, and a fully-expired account converges on
        // the next launch/foreground refresh once the purchase session ended.
        let before = storeTier
        if resolved >= storeTier || applyGuardExpired {
            setStoreTier(resolved)
        }
        // `setStoreTier` already reported a change; the first refresh reports
        // regardless, replacing the pre-refresh launch value.
        if !didFirstRefresh {
            didFirstRefresh = true
            if storeTier == before { onTierInputsChanged?() }
        }
    }

    /// Product IDs of the Loox Membership group whose renewal status still
    /// grants access. Empty when the status call fails (offline with no cache),
    /// leaving `currentEntitlements` as the only source, as before.
    private static func groupStatusProductIDs() async -> [String] {
        guard let statuses = try? await Product.SubscriptionInfo.status(for: LooxProductID.subscriptionGroupID)
        else { return [] }
        return statuses.compactMap { status in
            guard statusGrantsAccess(status.state),
                  case .verified(let transaction) = status.transaction,
                  transaction.revocationDate == nil else { return nil }
            return transaction.productID
        }
    }

    /// Subscribed and billing grace keep access; billing retry without grace,
    /// expired and revoked do not (Apple's renewal-state semantics).
    nonisolated static func statusGrantsAccess(_ state: Product.SubscriptionInfo.RenewalState) -> Bool {
        state == .subscribed || state == .inGracePeriod
    }

    /// True once no in-hand grant is recent enough to protect (60s window).
    private var applyGuardExpired: Bool {
        guard let appliedAt = lastInHandApplyAt else { return true }
        return Date.now.timeIntervalSince(appliedAt) > 60
    }
    @ObservationIgnored private var lastInHandApplyAt: Date?
}
