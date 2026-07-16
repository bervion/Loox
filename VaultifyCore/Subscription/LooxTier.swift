import Foundation

/// The user's Loox subscription tier. Ordered: a higher tier is a superset of a
/// lower one, so entitlement resolution can simply take the maximum across the
/// user's verified transactions.
///
/// Display names are brand nouns ("Loox", "Loox+", "Loox Max") — identical in
/// every locale, rendered verbatim. Product IDs never derive from them
/// (see `LooxProductID`).
nonisolated enum LooxTier: Int, Comparable, CaseIterable, Codable, Sendable {
    case free = 0
    case plus = 1
    case max = 2

    static func < (lhs: LooxTier, rhs: LooxTier) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Brand noun shown as the membership screen's large title. Locale-invariant.
    var displayName: String {
        switch self {
        case .free: return "Loox"
        case .plus: return "Loox+"
        case .max: return "Loox Max"
        }
    }

    /// The frozen V1 commercial contract for this tier (proposal §3.1). UI reads
    /// denominators from here — never hardcode a quota number in a view. These are
    /// display/gate values only; the backend counter is the enforcement authority
    /// once the entitlement service exists.
    var quotas: LooxQuotas {
        switch self {
        case .free:
            return LooxQuotas(personas: 1, retainedAliases: 1,
                              linkCreates30d: 3, quickViewApprovals30d: 3,
                              outgoingRecipients: 0,
                              fullWatchtower: false, fullThemes: false)
        case .plus:
            return LooxQuotas(personas: 3, retainedAliases: 10,
                              linkCreates30d: 30, quickViewApprovals30d: 30,
                              outgoingRecipients: 1,
                              fullWatchtower: true, fullThemes: true)
        case .max:
            // Personas carry no product cap on Max (nil = uncapped in product
            // terms; abuse controls are a separate, independent gate).
            return LooxQuotas(personas: nil, retainedAliases: 200,
                              linkCreates30d: 300, quickViewApprovals30d: 300,
                              outgoingRecipients: 10,
                              fullWatchtower: true, fullThemes: true)
        }
    }
}

/// Per-tier limits for the connected services and paid surfaces. `nil` means
/// "no product cap". Rolling quotas (`…30d`) count SUCCESSFUL operations in a
/// 30-day rolling window — failed attempts never consume a slot, and revoking
/// or early-expiring a created resource never refunds one.
nonisolated struct LooxQuotas: Equatable, Sendable {
    /// Profiles (personas) the user may have. `nil` on Max — no product cap.
    let personas: Int?
    /// Private Email aliases retained (active or paused). Permanent deletion
    /// frees the slot; the address itself is burned forever.
    let retainedAliases: Int
    /// Loox Links successfully created in a rolling 30-day window.
    let linkCreates30d: Int
    /// Quick View uploads successfully approved in a rolling 30-day window.
    let quickViewApprovals30d: Int
    /// Distinct ACTIVE outgoing Approval-Mode recipients. Sharing more items
    /// with the same person never consumes another seat. Receiving is always free.
    let outgoingRecipients: Int
    /// Full Watchtower: every finding severity, Fix Queue, history/diff,
    /// periodic reminders. Free always keeps Critical/High findings and the
    /// affected items — that safety floor is not a quota.
    let fullWatchtower: Bool
    /// Full accent/theme set (Free keeps a basic subset).
    let fullThemes: Bool
}

/// The permanent App Store product identifiers (proposal §4.2) and their tier
/// mapping. IDs are an allowlist — an unknown ID maps to no tier, never a guess.
nonisolated enum LooxProductID {
    /// "Loox Membership" subscription group in App Store Connect (created
    /// 260716). The paywall renders by explicit product-ID list (Max-first
    /// ordering), so this is recorded for the alternative
    /// `SubscriptionStoreView(groupID:)` init and server-side API scoping.
    static let subscriptionGroupID = "22241495"

    static let maxAnnual = "com.bervion.vaultify.subscription.max.annual"
    static let maxMonthly = "com.bervion.vaultify.subscription.max.monthly"
    static let plusAnnual = "com.bervion.vaultify.subscription.plus.annual"
    static let plusMonthly = "com.bervion.vaultify.subscription.plus.monthly"

    /// Paywall display order: Max before Plus (Max Annual is the protagonist).
    static let all: [String] = [maxAnnual, maxMonthly, plusAnnual, plusMonthly]

    static func tier(for productID: String) -> LooxTier? {
        switch productID {
        case maxAnnual, maxMonthly: return .max
        case plusAnnual, plusMonthly: return .plus
        default: return nil
        }
    }

    /// Highest tier granted by a set of (already verified) product IDs.
    /// Unknown IDs are ignored; no IDs means Free.
    static func resolveTier(from productIDs: some Sequence<String>) -> LooxTier {
        productIDs.compactMap(tier(for:)).max() ?? .free
    }
}
