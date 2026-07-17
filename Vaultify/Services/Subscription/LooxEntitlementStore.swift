import Foundation
import os
import StoreKit

/// Diagnostic logger for beta purchase-access resolution. Booleans and
/// environment names only — never receipts or transaction payloads.
private let subscriptionLog = Logger(subsystem: "com.bervion.vaultify", category: "subscription")

/// Client-side source of truth for the user's Loox tier: verified StoreKit 2
/// transactions, projected into an observable value the UI and gates read.
/// Nothing else (CloudKit flags, UserDefaults, UI state) may decide tier.
///
/// Lifecycle (proposal §7.5): prime from `Transaction.currentEntitlements` at
/// launch, then follow `Transaction.updates` for the whole process lifetime so
/// purchases, renewals, upgrades, refunds and Ask-to-Buy resolutions land
/// without a restart. Only `.verified` results count; a transaction is finished
/// strictly AFTER the local entitlement is recomputed. The backend hand-off
/// (`appAccountToken` + entitlement API, proposal §7.3–7.4) is a later,
/// out-of-repo phase — when it exists, the durable enqueue happens between
/// those two steps.
///
/// Entitlement state must never touch vault data — this store only ever
/// changes what the UI offers, never what the vault contains.
@MainActor @Observable final class LooxEntitlementStore {
    /// Tier granted by verified App Store transactions. Free when none.
    /// `Transaction.currentEntitlements` is local device state (it already
    /// reflects grace periods and does not require the network), so recomputing
    /// from it — including down to Free after a real expiry — is always safe.
    private(set) var storeTier: LooxTier = .free

    /// The effective tier the app renders and gates on.
    var tier: LooxTier {
        #if DEBUG
        if let debugTierOverride { return debugTierOverride }
        #endif
        return storeTier
    }

    /// Whether purchase surfaces render (paywall, plan section, gate sheets).
    /// True once the real launch flag flips — and early in beta environments
    /// (TestFlight, App Review) so sandbox purchases are testable end-to-end
    /// before launch. App Store builds stay dark until
    /// `LooxMembership.launchEnabled`. DEBUG builds use the explicit dev
    /// toggle instead (see `debugPurchasesEnabled`).
    var purchasesEnabled: Bool {
        #if DEBUG
        return LooxMembership.launchEnabled || debugPurchasesEnabled
        #else
        return LooxMembership.launchEnabled || betaPurchaseAccess
        #endif
    }

    /// `AppTransaction.environment != .production` — the supported signal for
    /// TestFlight/App Review (`.sandbox`). Resolved once at start on RELEASE
    /// builds straight from `AppTransaction.shared` (store-distributed
    /// installs answer from the store record; anything without store context
    /// throws and stays false — dark is the safe default).
    private(set) var betaPurchaseAccess = false

    #if DEBUG
    /// DEBUG builds never consult AppTransaction — a dev install without a
    /// receipt could trigger an App Store sign-in prompt at launch. Purchase
    /// surfaces open via this explicit toggle (Settings → Debug) instead,
    /// e.g. for paywall preview under the Vaultify-StoreKit scheme. Default
    /// OFF so daily dev behavior stays byte-identical.
    var debugPurchasesEnabled: Bool = false {
        didSet { UserDefaults.standard.set(debugPurchasesEnabled, forKey: Self.debugPurchasesKey) }
    }
    private static let debugPurchasesKey = "debug.looxPurchasesEnabled"
    #endif

    #if DEBUG
    /// Dev/simulator override so tier-dependent UI is testable without App
    /// Store Connect products. `nil` follows StoreKit. Debug menu only.
    var debugTierOverride: LooxTier? {
        didSet {
            if let debugTierOverride {
                UserDefaults.standard.set(debugTierOverride.rawValue, forKey: Self.debugOverrideKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.debugOverrideKey)
            }
        }
    }
    private static let debugOverrideKey = "debug.looxTierOverride"
    #endif

    /// Fired after each VERIFIED transaction lands (purchase, renewal,
    /// restore) — the entitlement coordinator hangs its attach trigger here.
    @ObservationIgnored var onVerifiedTransactionUpdate: (() -> Void)?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init() {
        #if DEBUG
        if UserDefaults.standard.object(forKey: Self.debugOverrideKey) != nil {
            debugTierOverride = LooxTier(rawValue: UserDefaults.standard.integer(forKey: Self.debugOverrideKey))
        }
        debugPurchasesEnabled = UserDefaults.standard.bool(forKey: Self.debugPurchasesKey)
        #endif
    }

    /// Prime the tier and keep following transaction updates. Idempotent;
    /// called once from the composition root at launch.
    func start() {
        guard updatesTask == nil else { return }
        #if !DEBUG
        Task { [weak self] in await self?.resolveBetaPurchaseAccess() }
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

    #if !DEBUG
    /// TestFlight/App Review detection, layered — any ONE signal opens beta
    /// purchase surfaces; none marks production, so App Store installs stay
    /// dark until `LooxMembership.launchEnabled`:
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
            storeTier = tier
            lastInHandApplyAt = .now
        }
    }

    /// Recompute the tier from the verified current entitlements (highest wins,
    /// `LooxProductID.resolveTier`). Unverified results and revoked
    /// transactions never grant anything.
    private func refresh() async {
        var productIDs: [String] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil else { continue }
            productIDs.append(transaction.productID)
        }
        let resolved = LooxProductID.resolveTier(from: productIDs)
        subscriptionLog.log("refresh: \(productIDs.count, privacy: .public) entitlements → \(String(describing: resolved), privacy: .public)")
        // A just-purchased transaction can trail `currentEntitlements` for a
        // beat (sandbox especially) — an empty read must not stomp the tier
        // `applyVerified` just granted from the in-hand verified result. Real
        // expiry/refund downgrades still land: those reads carry the OTHER
        // still-live entitlements, and a fully-expired account converges on
        // the next launch/foreground refresh once the purchase session ended.
        if resolved >= storeTier || applyGuardExpired {
            storeTier = resolved
        }
    }

    /// True once no in-hand grant is recent enough to protect (60s window).
    private var applyGuardExpired: Bool {
        guard let appliedAt = lastInHandApplyAt else { return true }
        return Date.now.timeIntervalSince(appliedAt) > 60
    }
    @ObservationIgnored private var lastInHandApplyAt: Date?
}
