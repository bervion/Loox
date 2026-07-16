import Foundation

/// Where a projected shared item comes from (recipient side). Present ONLY on
/// items built by `SharedItemsProjection` — an owned item persisted in the
/// vault store never carries one. Shared-db zones are namespaced by the
/// sharing owner, so the pair (ownerName, zoneName) is the full address.
nonisolated struct SharedOrigin: Codable, Equatable, Hashable, Sendable {
    var zoneName: String
    var ownerName: String
    var grantId: String
    /// False when a v2 single-device grant does not include THIS device —
    /// the projection then carries a Tier-0 placeholder (generic state, no
    /// metadata, no values; INV-10). Defaults true for v1 grants and for
    /// snapshots persisted before this field existed.
    var deviceAuthorized: Bool

    init(zoneName: String, ownerName: String, grantId: String,
         deviceAuthorized: Bool = true) {
        self.zoneName = zoneName
        self.ownerName = ownerName
        self.grantId = grantId
        self.deviceAuthorized = deviceAuthorized
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        zoneName = try c.decode(String.self, forKey: .zoneName)
        ownerName = try c.decode(String.self, forKey: .ownerName)
        grantId = try c.decode(String.self, forKey: .grantId)
        deviceAuthorized = try c.decodeIfPresent(Bool.self, forKey: .deviceAuthorized) ?? true
    }

    /// Stable projected item id — the `shared::` prefix can never collide
    /// with owned items (UUID ids). Includes `grantId` so distinct grants
    /// sharing the SAME zone (Family per-grant transport — more than one
    /// item can now be granted into one zone) each get a distinct id; a
    /// single-grant zone still resolves to one stable id per grant.
    var itemID: String { "shared::\(ownerName)::\(zoneName)::\(grantId)" }
}
