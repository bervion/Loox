import Foundation

/// Where a projected shared item comes from (recipient side). Present ONLY on
/// items built by `SharedItemsProjection` — an owned item persisted in the
/// vault store never carries one. Shared-db zones are namespaced by the
/// sharing owner, so the pair (ownerName, zoneName) is the full address.
nonisolated struct SharedOrigin: Codable, Equatable, Hashable, Sendable {
    var zoneName: String
    var ownerName: String
    var grantId: String

    /// Stable projected item id — the `shared::` prefix can never collide
    /// with owned items (UUID ids) and parses back to the zone address.
    var itemID: String { "shared::\(ownerName)::\(zoneName)" }
}
