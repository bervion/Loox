import Foundation

/// Where a forwarding inbox came from. `personaProfile` inboxes are derived
/// from a persona's profile email (one per persona, email follows the profile);
/// `manual` inboxes are user-added and vault-global.
nonisolated enum ForwardingInboxSource: String, Codable, Sendable {
    case personaProfile
    case manual
}

/// Ownership-verification state of a forwarding inbox (DEC-DST-01). Mail only
/// forwards to a `verified` destination once the server enforces it; the backend
/// is authoritative (INV-DST-N01), the client only mirrors what it reports.
nonisolated enum DestinationVerificationStatus: String, Codable, Sendable {
    case unverified   // never begun, or a fresh inbox
    case pending      // verification email sent, awaiting the user's web confirm
    case verified     // backend confirmed inbox control
    case revoked      // e.g. after Erase Vault — plaintext scrubbed, must re-verify
}

/// A real inbox that private-email aliases forward to. First-class so the user
/// can see and change where mail goes without the app copying the raw email
/// into every alias. The email itself is identity-bearing → sealed at rest
/// (`ForwardingInboxSecret`); only sort/sync metadata is plaintext.
nonisolated struct ForwardingInbox: Identifiable, Equatable, Sendable {
    var id: String
    var email: String
    var label: String?
    var source: ForwardingInboxSource
    /// Owning persona for `.personaProfile` inboxes — keeps derivation
    /// idempotent (exactly one derived inbox per persona). nil for manual.
    var personaId: String?
    /// Explicit vault-wide default for NEW aliases. When none is set, a new
    /// alias defaults to its persona's derived profile inbox.
    var isDefault: Bool
    /// Opaque backend id (128-bit) for this inbox's verified-destination row.
    /// Set when verification begins; used to poll status and (once the server
    /// enforces it) to route forwarding by id instead of raw email.
    var relayDestinationID: String?
    var verificationStatus: DestinationVerificationStatus
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString,
         email: String,
         label: String? = nil,
         source: ForwardingInboxSource = .manual,
         personaId: String? = nil,
         isDefault: Bool = false,
         relayDestinationID: String? = nil,
         verificationStatus: DestinationVerificationStatus = .unverified,
         sortIndex: Int = 0,
         createdAt: Date = .now,
         updatedAt: Date = .now) {
        self.id = id
        self.email = email
        self.label = label
        self.source = source
        self.personaId = personaId
        self.isDefault = isDefault
        self.relayDestinationID = relayDestinationID
        self.verificationStatus = verificationStatus
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var secret: ForwardingInboxSecret {
        ForwardingInboxSecret(email: email, label: label, source: source,
                              personaId: personaId, isDefault: isDefault,
                              relayDestinationID: relayDestinationID,
                              verificationStatus: verificationStatus)
    }
}

/// Encrypted-at-rest payload of an inbox. Custom `Decodable` so older blobs
/// missing a key decode to its default (the growable-sealed-schema rule: a
/// non-optional property with a default still throws `keyNotFound` under
/// synthesized Codable — `decodeIfPresent` is what makes the schema growable).
nonisolated struct ForwardingInboxSecret: Codable, Sendable {
    var email: String
    var label: String?
    var source: ForwardingInboxSource
    var personaId: String?
    var isDefault: Bool
    var relayDestinationID: String?
    var verificationStatus: DestinationVerificationStatus

    init(email: String, label: String? = nil,
         source: ForwardingInboxSource = .manual,
         personaId: String? = nil, isDefault: Bool = false,
         relayDestinationID: String? = nil,
         verificationStatus: DestinationVerificationStatus = .unverified) {
        self.email = email
        self.label = label
        self.source = source
        self.personaId = personaId
        self.isDefault = isDefault
        self.relayDestinationID = relayDestinationID
        self.verificationStatus = verificationStatus
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        email = try c.decode(String.self, forKey: .email)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        source = try c.decodeIfPresent(ForwardingInboxSource.self, forKey: .source) ?? .manual
        personaId = try c.decodeIfPresent(String.self, forKey: .personaId)
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        relayDestinationID = try c.decodeIfPresent(String.self, forKey: .relayDestinationID)
        verificationStatus = try c.decodeIfPresent(DestinationVerificationStatus.self,
                                                   forKey: .verificationStatus) ?? .unverified
    }
}
