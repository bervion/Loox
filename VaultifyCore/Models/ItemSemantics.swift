import Foundation

// MARK: - Stable identifiers

/// Stable, lossless item-type identifier — a lowercase namespaced string such
/// as `credential.login` or `developer.ssh-key`.
///
/// Unlike `ItemCategory` (a closed enum whose unknown values used to fail the
/// whole decode), an ID this build does not recognize round-trips verbatim:
/// presentation degrades, identity never does. IDs are append-only and frozen
/// once shipped.
nonisolated struct ItemKindID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }

    init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// Stable, lossless field-role identifier — `credential.password`,
/// `ssh.private-key`, `api.token`. The role, never the editable label and
/// never the presentation `FieldKind`, is what grants a field behavior.
nonisolated struct FieldRoleID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }

    init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

// MARK: - Policy dimensions (independent axes, never inferred from each other)

/// How disclosure-sensitive a value is. Drives masking, search indexing,
/// clipboard policy, and share eligibility floors.
nonisolated enum Sensitivity: String, Codable, Sendable, Comparable {
    case `public`
    case `private`
    case secret
    case keyMaterial

    private var rank: Int {
        switch self {
        case .public: 0
        case .private: 1
        case .secret: 2
        case .keyMaterial: 3
        }
    }
    static func < (lhs: Sensitivity, rhs: Sensitivity) -> Bool { lhs.rank < rhs.rank }
    /// The stricter of two policies — imported/stored policy can only ever
    /// TIGHTEN the registry minimum, never relax it.
    static func stricter(_ a: Sensitivity, _ b: Sensitivity) -> Sensitivity { a < b ? b : a }
}

/// What a user must do before an ACTION (reveal, copy, export) is allowed.
/// This is UI authorization policy — distinct from `CryptoProtection`, which
/// says which KEY the bytes are sealed under.
nonisolated enum ActionAuthorization: String, Codable, Sendable, Comparable {
    case none
    /// Device-owner re-authentication (Face ID / passcode), action-bound.
    case reauthenticate
    /// Requires the Level-2 code flow in addition to re-auth.
    case level2

    private var rank: Int {
        switch self {
        case .none: 0
        case .reauthenticate: 1
        case .level2: 2
        }
    }
    static func < (lhs: ActionAuthorization, rhs: ActionAuthorization) -> Bool { lhs.rank < rhs.rank }
    static func stricter(_ a: ActionAuthorization, _ b: ActionAuthorization) -> ActionAuthorization { a < b ? b : a }
}

/// Which key hierarchy seals the value at rest.
nonisolated enum CryptoProtection: String, Codable, Sendable {
    /// Sealed with the vault key (the default for every vault value).
    case vaultKey
    /// Additionally wrapped under the Level-2 key/envelope (`guard2`).
    case level2Key
}

/// Field-level lifecycle metadata: rotation and expiry live on the FIELD they
/// describe, not overloaded onto item-level password columns.
nonisolated struct FieldLifecycle: Codable, Equatable, Sendable {
    var changedAt: Date?
    var expiresAt: Date?
    var rotateDays: Int?

    init(changedAt: Date? = nil, expiresAt: Date? = nil, rotateDays: Int? = nil) {
        self.changedAt = changedAt
        self.expiresAt = expiresAt
        self.rotateDays = rotateDays
    }
}

// MARK: - Typed links

/// A typed relationship to another vault item — a Git account linking its PAT
/// item, an SSH auth key, a recovery item — instead of duplicating a secret
/// into both places. Links are references only: deleting the target never
/// cascades; the link renders as broken and offers relink.
nonisolated struct ItemLink: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// Stable link identity (survives edits; rows keep identity).
    var id: String
    /// What the target IS to this item — `link.auth-key`, `link.signing-key`,
    /// `link.api-secret`, `link.recovery`, `link.server`. Lossless raw string.
    var roleID: String
    /// The target item's id in the same vault.
    var targetItemId: String

    init(id: String = UUID().uuidString, roleID: String, targetItemId: String) {
        self.id = id
        self.roleID = roleID
        self.targetItemId = targetItemId
    }
}

// MARK: - Aggregates

/// Optional, additive semantic identity of an item, sealed with the rest of
/// the payload. Legacy items have none and keep working through category
/// inference; new items write it at creation.
nonisolated struct ItemSemantics: Codable, Equatable, Sendable {
    /// The wire generation THIS build reads and writes. Bump ONLY for an
    /// incompatible addition (a new required key, a changed meaning of an
    /// existing one). A decoded value greater than `supported` marks the item
    /// as unsupported: generic concealed read-only recovery, original
    /// ciphertext preserved, never typed re-encode.
    static let supported = 1

    var schemaVersion: Int
    var kindID: ItemKindID?
    /// Creation provenance: which template version stamped this item. Never
    /// triggers silent mutation.
    var templateVersion: Int?
    var links: [ItemLink]?

    init(schemaVersion: Int = ItemSemantics.supported,
         kindID: ItemKindID? = nil,
         templateVersion: Int? = nil,
         links: [ItemLink]? = nil) {
        self.schemaVersion = schemaVersion
        self.kindID = kindID
        self.templateVersion = templateVersion
        self.links = links
    }

    var isSupportedSchema: Bool { schemaVersion <= Self.supported }
}

/// Optional, additive semantics of a single field. Presentation (`FieldKind`),
/// semantics (`roleID`), sensitivity, action authorization, crypto protection,
/// and lifecycle are INDEPENDENT dimensions — none is inferred from another.
///
/// Stored policy is a one-way ratchet: the registry's minimum for a known
/// role always applies; these values can only tighten it.
nonisolated struct FieldSemantics: Codable, Equatable, Sendable {
    var roleID: FieldRoleID?
    /// Which template section the field belongs to (registry section id).
    var sectionID: String?
    var sensitivity: Sensitivity?
    var actionAuthorization: ActionAuthorization?
    var cryptoProtection: CryptoProtection?
    var lifecycle: FieldLifecycle?

    init(roleID: FieldRoleID? = nil,
         sectionID: String? = nil,
         sensitivity: Sensitivity? = nil,
         actionAuthorization: ActionAuthorization? = nil,
         cryptoProtection: CryptoProtection? = nil,
         lifecycle: FieldLifecycle? = nil) {
        self.roleID = roleID
        self.sectionID = sectionID
        self.sensitivity = sensitivity
        self.actionAuthorization = actionAuthorization
        self.cryptoProtection = cryptoProtection
        self.lifecycle = lifecycle
    }

    /// Lenient decode: a policy enum value this build does not know decodes as
    /// nil (the registry minimum then governs — stored policy can never relax
    /// it, so dropping an unknown STRICTER value still fails closed at the
    /// resolver, which zeroes external capability for unknown roles). The raw
    /// role and section identifiers themselves are lossless strings.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        roleID = try c.decodeIfPresent(FieldRoleID.self, forKey: .roleID)
        sectionID = try c.decodeIfPresent(String.self, forKey: .sectionID)
        sensitivity = try? c.decodeIfPresent(Sensitivity.self, forKey: .sensitivity)
        actionAuthorization = try? c.decodeIfPresent(ActionAuthorization.self, forKey: .actionAuthorization)
        cryptoProtection = try? c.decodeIfPresent(CryptoProtection.self, forKey: .cryptoProtection)
        lifecycle = try c.decodeIfPresent(FieldLifecycle.self, forKey: .lifecycle)
    }
}
