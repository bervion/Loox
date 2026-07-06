import Foundation

/// How a persona is used. Drives the default icon and, later, suggestion policy.
nonisolated enum PersonaKind: String, Codable, Sendable, CaseIterable {
    case personal, professional, pseudonymous, anonymous, custom
}

/// How strictly a persona is kept apart from the others. Defined and stored in
/// P1; CONSUMED in P2, where `strictAnonymous` becomes a hard exclusion (never a
/// down-rank) so an anonymous persona can never surface another persona's email,
/// profile, or items in suggestions/search.
nonisolated enum PersonaIsolationPolicy: String, Codable, Sendable, CaseIterable {
    case standard, isolated, strictAnonymous
}

/// A persona ("identity") decoded in memory while the vault is unlocked. One
/// human owns several personas; each scopes its own primary Space, profile, and
/// (later) email aliases and isolation. Identity-bearing fields are sealed at
/// rest (`PersonaSecret`); the default flag, sort order, and timestamps are
/// non-secret convergence/presentation metadata kept plaintext on
/// `PersonaRecord`, mirroring `Folder`/`FolderRecord`.
nonisolated struct Persona: Identifiable, Equatable, Sendable {
    var id: String
    var displayName: String
    var kind: PersonaKind
    var isolationPolicy: PersonaIsolationPolicy
    /// Soft link to the identity `ItemRecord` (the one carrying `isDefaultIdentity`)
    /// that holds this persona's profile fields. Optional — a persona can exist
    /// before its profile item does.
    var primaryProfileItemID: String?
    /// Single pointer to this persona's primary Space (folder id). The authoritative
    /// "primary Space" source — no per-folder `isPrimary` flag exists (a single
    /// pointer can't fork into two primaries under sync conflict).
    var primarySpaceID: String?
    /// Synced convergence flag — exactly one persona is the default. Plaintext
    /// column so sync reconciles it without unsealing (mirrors `isDefaultIdentity`).
    var isDefault: Bool
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date

    /// Fixed id for the auto-seeded Personal persona so two devices' first-run
    /// seeds collide on ONE CloudKit record id (last-writer-wins merges them)
    /// instead of producing duplicates that would need a merge pass.
    static let bootstrapPersonalID = "persona-default-personal"

    init(id: String = UUID().uuidString,
         displayName: String,
         kind: PersonaKind,
         isolationPolicy: PersonaIsolationPolicy = .standard,
         primaryProfileItemID: String? = nil,
         primarySpaceID: String? = nil,
         isDefault: Bool = false,
         sortIndex: Int = 0,
         createdAt: Date = .now,
         updatedAt: Date = .now) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.isolationPolicy = isolationPolicy
        self.primaryProfileItemID = primaryProfileItemID
        self.primarySpaceID = primarySpaceID
        self.isDefault = isDefault
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// The portion sealed (AES-256-GCM) at rest.
    var secret: PersonaSecret {
        PersonaSecret(displayName: displayName, kind: kind, isolationPolicy: isolationPolicy,
                      primaryProfileItemID: primaryProfileItemID, primarySpaceID: primarySpaceID)
    }
}

/// The encrypted-at-rest payload of a persona. New optional/defaulted keys let
/// older sealed blobs (which lack them) decode cleanly, so the sealed schema can
/// grow without a migration. Any writer that changes these MUST re-seal through
/// the repository so `updatedAt` bumps, or the whole-record last-writer-wins pull
/// gate drops the change.
nonisolated struct PersonaSecret: Codable, Sendable {
    var displayName: String
    var kind: PersonaKind
    var isolationPolicy: PersonaIsolationPolicy
    var primaryProfileItemID: String?
    var primarySpaceID: String?

    init(displayName: String, kind: PersonaKind,
         isolationPolicy: PersonaIsolationPolicy = .standard,
         primaryProfileItemID: String? = nil, primarySpaceID: String? = nil) {
        self.displayName = displayName
        self.kind = kind
        self.isolationPolicy = isolationPolicy
        self.primaryProfileItemID = primaryProfileItemID
        self.primarySpaceID = primarySpaceID
    }

    /// Custom decode so blobs written before a key existed decode to its default.
    /// A non-optional property with a default value is NOT decode-optional under
    /// synthesized `Codable` (it still throws `keyNotFound`); `decodeIfPresent`
    /// is what actually makes the sealed schema growable.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try c.decode(String.self, forKey: .displayName)
        kind = try c.decode(PersonaKind.self, forKey: .kind)
        isolationPolicy = try c.decodeIfPresent(PersonaIsolationPolicy.self, forKey: .isolationPolicy) ?? .standard
        primaryProfileItemID = try c.decodeIfPresent(String.self, forKey: .primaryProfileItemID)
        primarySpaceID = try c.decodeIfPresent(String.self, forKey: .primarySpaceID)
    }
}
