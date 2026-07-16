import Foundation
import StoreKit

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

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init() {
        #if DEBUG
        if UserDefaults.standard.object(forKey: Self.debugOverrideKey) != nil {
            debugTierOverride = LooxTier(rawValue: UserDefaults.standard.integer(forKey: Self.debugOverrideKey))
        }
        #endif
    }

    /// Prime the tier and keep following transaction updates. Idempotent;
    /// called once from the composition root at launch.
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            await self?.refresh()
            for await update in Transaction.updates {
                guard let self else { return }
                await self.refresh()
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
            }
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
        storeTier = LooxProductID.resolveTier(from: productIDs)
    }
}
