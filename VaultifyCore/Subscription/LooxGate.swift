import Foundation

/// Pure over-quota checks behind the contextual paywalls (proposal §5.3).
/// These are UPSELL gates, not enforcement: they fire only on a concrete
/// create/approve action that the user's tier no longer covers, and they name
/// the cheapest tier that would cover it. The backend counter stays the
/// enforcement authority — when even Max wouldn't cover the action the client
/// deliberately returns `.allowed` and lets the server decide, so a client
/// gate can never strand a user with an offer that wouldn't help.
///
/// Gates never touch data: a blocked action simply doesn't start. Call sites
/// consult these only while purchases are enabled
/// (`LooxEntitlementStore.purchasesEnabled` — launch flag or beta environment).
nonisolated enum LooxGate {
    enum Allowance: Equatable, Sendable {
        case allowed
        /// The cheapest tier whose quota covers one more of the resource.
        case needsUpgrade(to: LooxTier)
    }

    /// Profiles (personas). `current` = existing personas.
    static func canCreatePersona(tier: LooxTier, current: Int) -> Allowance {
        allowanceForOneMore(tier: tier, current: current) { $0.personas }
    }

    /// Private Email. `retained` = active + paused aliases (§3.2).
    static func canCreateAlias(tier: LooxTier, retained: Int) -> Allowance {
        allowanceForOneMore(tier: tier, current: retained) { $0.retainedAliases }
    }

    /// Loox Link. `createdIn30d` = successful creates in the rolling window.
    static func canCreateLink(tier: LooxTier, createdIn30d: Int) -> Allowance {
        allowanceForOneMore(tier: tier, current: createdIn30d) { $0.linkCreates30d }
    }

    /// Quick View. `approvedIn30d` = successful approvals in the rolling window.
    static func canApproveQuickView(tier: LooxTier, approvedIn30d: Int) -> Allowance {
        allowanceForOneMore(tier: tier, current: approvedIn30d) { $0.quickViewApprovals30d }
    }

    /// Approval-Mode sharing. `activeRecipients` = distinct people with an
    /// active outgoing share; re-sharing with them is always `.allowed`
    /// (checked by the caller — same person never consumes a new seat).
    static func canAddOutgoingRecipient(tier: LooxTier, activeRecipients: Int) -> Allowance {
        allowanceForOneMore(tier: tier, current: activeRecipients) { $0.outgoingRecipients }
    }

    /// Full Watchtower (every finding, Fix Queue, history, reminders). The Free
    /// floor — Critical/High findings and their affected items — is not gated
    /// anywhere (§2.3).
    static func fullWatchtower(_ tier: LooxTier) -> Bool { tier.quotas.fullWatchtower }

    /// Full accent/theme set.
    static func fullThemes(_ tier: LooxTier) -> Bool { tier.quotas.fullThemes }

    // MARK: - Shared resolution

    private static func allowanceForOneMore(
        tier: LooxTier, current: Int, quota: (LooxQuotas) -> Int?
    ) -> Allowance {
        if permitsOneMore(tier: tier, current: current, quota: quota) { return .allowed }
        for candidate in LooxTier.allCases where candidate > tier {
            if permitsOneMore(tier: candidate, current: current, quota: quota) {
                return .needsUpgrade(to: candidate)
            }
        }
        // Over even the Max quota: no offer would help, so the client defers
        // to the backend rather than dead-ending the user.
        return .allowed
    }

    private static func permitsOneMore(
        tier: LooxTier, current: Int, quota: (LooxQuotas) -> Int?
    ) -> Bool {
        guard let cap = quota(tier.quotas) else { return true }
        return current < cap
    }
}
