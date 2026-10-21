import Foundation

/// Complimentary Loox+ (owner decision 261021): every device gets Loox+ quotas
/// free for 750 days from the first launch of the version that ships it, so a
/// new user has long enough to learn the app. Granted IN-APP: no StoreKit, no
/// Apple trial, no card. Device-local and never sent to the backend. After it
/// ends the user falls back to Free quotas unless they subscribe; tier changes
/// never touch vault data.
///
/// Days are fixed 86_400-second spans (same rule as `RotationStatus`), so the end
/// instant does not move with time zone or DST. A start in the future is clamped
/// by `LooxComplimentaryGrantStore`, never here.
nonisolated struct LooxComplimentaryGrant: Equatable, Sendable {
    static let tier: LooxTier = .plus
    static let durationDays = 750                       // pinned by tests
    static let duration: TimeInterval = TimeInterval(durationDays) * 86_400
    /// A stored start more than this far ahead of `now` is clamped to `now`.
    static let futureStartTolerance: TimeInterval = 86_400

    let start: Date
    var endsAt: Date { start.addingTimeInterval(Self.duration) }
    func isActive(at now: Date) -> Bool { now < endsAt }

    static func effectiveTier(store: LooxTier, grant: Self?, now: Date) -> LooxTier {
        guard let grant, grant.isActive(at: now) else { return store }
        return Swift.max(store, tier)
    }
}
