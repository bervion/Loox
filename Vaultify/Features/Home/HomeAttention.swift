import Foundation

/// Why an item is in Home's "Needs Attention" list. Extends the rotation-based
/// `AttentionReason` with the two security signals that need context beyond the
/// item itself: a password seen in a known leak (from the last saved audit) and
/// a password shared with other items (from the live reuse scan).
///
/// One reason per item — the worst one. A leaked password that is also weak and
/// reused is one row saying "leaked": that is the thing to fix, and fixing it
/// (a new generated password) clears the other two anyway.
nonisolated enum HomeAttentionReason: Sendable, Equatable {
    case leaked
    case weak
    case reused
    case overdue
    case soon
    case stale

    /// Sort key: lower = more urgent, and the section's badge takes the tone of
    /// the lowest-ranked entry.
    var rank: Int {
        switch self {
        case .leaked: return 0
        case .weak: return 1
        case .reused: return 2
        case .overdue: return 3
        case .soon: return 4
        case .stale: return 5
        }
    }

    var tone: RotationTone {
        switch self {
        case .leaked, .weak, .overdue: return .destructive
        case .reused, .soon, .stale: return .warning
        }
    }
}

/// Pure assembly of the Home "Needs Attention" entries — kept out of the view so
/// the ranking is testable and the view only renders.
nonisolated enum HomeAttention {

    struct Entry: Identifiable, Equatable {
        let item: VaultItem
        let reason: HomeAttentionReason
        var id: String { item.id }
    }

    /// Ranked worst-first, capped at `limit`.
    ///
    /// - Parameters:
    ///   - items: the persona- and Space-scoped pool (live items only).
    ///   - reusedItemIDs: items sharing a password with another item (live scan).
    ///   - leakedItemIDs: items the last saved audit found in a known leak,
    ///     already filtered to the user's open decisions.
    ///   - leakedAsOf: when that audit completed. A password changed since was
    ///     never the one that was checked, so its leak verdict is dropped —
    ///     same staleness rule as the item detail banner.
    ///   - now: injection point for deterministic tests.
    static func entries(items: [VaultItem],
                        reusedItemIDs: Set<String>,
                        leakedItemIDs: Set<String>,
                        leakedAsOf: Date,
                        limit: Int = 4,
                        now: Date = .now) -> [Entry] {
        items.compactMap { item -> Entry? in
            reason(for: item, reusedItemIDs: reusedItemIDs,
                   leakedItemIDs: leakedItemIDs, leakedAsOf: leakedAsOf, now: now)
                .map { Entry(item: item, reason: $0) }
        }
        .sorted { $0.reason.rank < $1.reason.rank }
        .prefix(limit)
        .map { $0 }
    }

    private static func reason(for item: VaultItem,
                               reusedItemIDs: Set<String>,
                               leakedItemIDs: Set<String>,
                               leakedAsOf: Date,
                               now: Date) -> HomeAttentionReason? {
        let hasPassword = !(item.passwordField?.value.isEmpty ?? true)
        if hasPassword, leakedItemIDs.contains(item.id),
           (item.passwordChangedAt ?? item.createdAt) <= leakedAsOf {
            return .leaked
        }
        if item.hasWeakPassword { return .weak }
        if hasPassword, reusedItemIDs.contains(item.id) { return .reused }

        let status = RotationStatus.evaluate(
            rotateDays: item.rotateDays,
            passwordChangedAt: item.passwordChangedAt,
            createdAt: item.createdAt,
            now: now)
        switch status.state {
        case .overdue: return .overdue
        case .soon: return .soon
        case .stale: return .stale
        case .ok: return nil
        }
    }
}
