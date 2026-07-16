import Foundation

/// The frozen subscription state contract (proposal §8.1): what Loox does for
/// each Apple/business billing state. Kept as a pure mapping so the contract
/// is executable and pinned by tests; UI and services consult it instead of
/// re-deriving billing policy ad hoc.
///
/// Two invariants sit above every row: entitlement state never deletes or
/// modifies vault data, and service health is never rendered as a paywall.
nonisolated enum LooxSubscriptionState {
    /// Apple/business states the client can observe (via StoreKit status and,
    /// later, the backend projection).
    enum AppleState: CaseIterable, Sendable {
        case active
        /// Auto-renew turned off but the paid period hasn't ended.
        case autoRenewOffNotExpired
        /// Upgrade already verified (e.g. Plus → Max).
        case upgraded
        /// Downgrade scheduled; Apple decides the effective date.
        case pendingDowngrade
        case billingGracePeriod
        /// Billing retry beyond grace, or grace exhausted.
        case billingRetryBeyondGrace
        case expired
        case refundedOrRevoked
        /// Entitlement momentarily undeterminable (e.g. a read failed).
        case undetermined
    }

    /// What the app renders/permits.
    enum Behavior: Equatable, Sendable {
        /// Full access for the CURRENT tier (for `upgraded`, the new tier).
        case fullPaidAccess
        /// Block NEW premium actions; existing service state begins its safety
        /// wind-down. Never a data deletion.
        case blockNewPremiumActions
        /// Render Free on-device; service safety wind-down applies (§8.3).
        case freeTier
        /// Keep the last VERIFIED unexpired entitlement; retry/reconcile.
        /// Never delete, never downgrade on a mere read/network failure.
        case keepLastVerified
    }

    static func behavior(for state: AppleState) -> Behavior {
        switch state {
        case .active, .autoRenewOffNotExpired, .upgraded, .pendingDowngrade,
             .billingGracePeriod:
            return .fullPaidAccess
        case .billingRetryBeyondGrace:
            return .blockNewPremiumActions
        case .expired:
            return .freeTier
        case .refundedOrRevoked:
            // Premium actions stop immediately; existing service state may be
            // held briefly (≤72h) to protect the user — that hold is service
            // policy on top of this behavior, not a different behavior.
            return .blockNewPremiumActions
        case .undetermined:
            return .keepLastVerified
        }
    }
}
