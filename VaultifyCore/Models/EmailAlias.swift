import Foundation

/// Whether an alias is a stable per-persona address or a unique per-website one.
nonisolated enum AliasTier: String, Codable, Sendable, CaseIterable {
    case persona
    case perSite
}

/// Lifecycle of an alias. `active`/`paused` require the relay backend (gated by
/// `RelayFeature`); only draft/reserved/disabled are reachable pre-relay.
nonisolated enum AliasStatus: String, Codable, Sendable, CaseIterable {
    case draft      // planned, no address reserved
    case reserved   // local-part chosen, not yet live
    case active     // live forwarding (relay only)
    case paused     // temporarily not forwarding (relay only)
    case disabled   // retired
}

/// An email alias decoded in memory while the vault is unlocked. Identity-bearing
/// fields (owner persona, local-part, bindings, forwarding target) are sealed at
/// rest (`EmailAliasSecret`); only sort/sync metadata is plaintext — mirrors the
/// persona/folder "secrets sealed" contract.
nonisolated struct EmailAlias: Identifiable, Equatable, Sendable {
    var id: String
    var personaId: String
    var tier: AliasTier
    /// The address left-hand side. Per-site parts are random (anti-correlation),
    /// never derived from the site or persona.
    var localPart: String
    var boundItemId: String?
    var boundDomain: String?
    /// User label ("Clients", "GitHub Work") — reusable addresses especially.
    var label: String?
    var status: AliasStatus
    /// Explicit forwarding-inbox override. nil → the persona's default inbox
    /// resolves at activation time (see `resolvedDestination`).
    var forwardingInboxID: String?
    /// The real inbox this alias forwards to — the last destination actually
    /// set on the backend via rotateDestination (display + idempotent retry).
    var forwardingTarget: String?
    var disabledAt: Date?
    /// True once the backend has minted this alias (createAlias returned ok).
    /// Makes activation resumable: if rotateDestination fails after the mint, a
    /// retry skips createAlias (which would collide and orphan the first mint).
    /// Also means disable/delete must reach the backend even while still reserved.
    var backendMinted: Bool
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString,
         personaId: String,
         tier: AliasTier,
         localPart: String,
         boundItemId: String? = nil,
         boundDomain: String? = nil,
         label: String? = nil,
         status: AliasStatus = .draft,
         forwardingInboxID: String? = nil,
         forwardingTarget: String? = nil,
         disabledAt: Date? = nil,
         backendMinted: Bool = false,
         sortIndex: Int = 0,
         createdAt: Date = .now,
         updatedAt: Date = .now) {
        self.id = id
        self.personaId = personaId
        self.tier = tier
        self.localPart = localPart
        self.boundItemId = boundItemId
        self.boundDomain = boundDomain
        self.label = label
        self.status = status
        self.forwardingInboxID = forwardingInboxID
        self.forwardingTarget = forwardingTarget
        self.disabledAt = disabledAt
        self.backendMinted = backendMinted
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var secret: EmailAliasSecret {
        EmailAliasSecret(personaId: personaId, tier: tier, localPart: localPart,
                         boundItemId: boundItemId, boundDomain: boundDomain,
                         label: label, status: status,
                         forwardingInboxID: forwardingInboxID,
                         forwardingTarget: forwardingTarget,
                         disabledAt: disabledAt, backendMinted: backendMinted)
    }
}

/// The encrypted-at-rest payload of an alias. Custom `Decodable` so older blobs
/// missing a key decode to its default — a non-optional property WITH a default
/// is still not decode-optional under synthesized Codable (it throws
/// `keyNotFound`); `decodeIfPresent` is what makes the sealed schema growable.
nonisolated struct EmailAliasSecret: Codable, Sendable {
    var personaId: String
    var tier: AliasTier
    var localPart: String
    var boundItemId: String?
    var boundDomain: String?
    var label: String?
    var status: AliasStatus
    var forwardingInboxID: String?
    var forwardingTarget: String?
    var disabledAt: Date?
    var backendMinted: Bool

    init(personaId: String, tier: AliasTier, localPart: String,
         boundItemId: String? = nil, boundDomain: String? = nil,
         label: String? = nil, status: AliasStatus = .draft,
         forwardingInboxID: String? = nil, forwardingTarget: String? = nil,
         disabledAt: Date? = nil, backendMinted: Bool = false) {
        self.personaId = personaId
        self.tier = tier
        self.localPart = localPart
        self.boundItemId = boundItemId
        self.boundDomain = boundDomain
        self.label = label
        self.status = status
        self.forwardingInboxID = forwardingInboxID
        self.forwardingTarget = forwardingTarget
        self.disabledAt = disabledAt
        self.backendMinted = backendMinted
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        personaId = try c.decode(String.self, forKey: .personaId)
        localPart = try c.decode(String.self, forKey: .localPart)
        tier = try c.decodeIfPresent(AliasTier.self, forKey: .tier) ?? .perSite
        status = try c.decodeIfPresent(AliasStatus.self, forKey: .status) ?? .draft
        boundItemId = try c.decodeIfPresent(String.self, forKey: .boundItemId)
        boundDomain = try c.decodeIfPresent(String.self, forKey: .boundDomain)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        forwardingInboxID = try c.decodeIfPresent(String.self, forKey: .forwardingInboxID)
        forwardingTarget = try c.decodeIfPresent(String.self, forKey: .forwardingTarget)
        disabledAt = try c.decodeIfPresent(Date.self, forKey: .disabledAt)
        backendMinted = try c.decodeIfPresent(Bool.self, forKey: .backendMinted) ?? false
    }
}
