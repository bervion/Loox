import Foundation

/// Shared constants for the Approval Mode transport: CloudKit container,
/// record/subscription identifiers, opaque naming, and message TTLs.
///
/// Zone and record names are opaque random strings — the recipient identity or
/// item linkage must never be readable from CloudKit metadata (record payloads
/// are ciphertext, but zone/record NAMES are visible server-side metadata).
nonisolated enum ApprovalConfig {
    /// Same container as vault sync; approval data lives in SEPARATE custom
    /// zones so the control plane never mixes with the private `Vault` zone.
    static let containerID = "iCloud.com.bervion.vaultify"

    // MARK: Record types

    /// Written by the participant (recipient B) into the owner's shared zone.
    static let requestRecordType = "ApprovalRequest"
    /// Written by the owner (A) after the foreground approval ceremony.
    static let responseRecordType = "ApprovalResponse"
    /// Owner-signed `AccessGrant` canonical blob (one per zone/recipient).
    static let grantRecordType = "ApprovalGrant"
    /// HPKE blob of one `shared` field value, sealed to B's participant key.
    static let sharedFieldRecordType = "ApprovalSharedField"
    /// B's published identity: participant pubkey + device signing pubkeys.
    static let participantProfileRecordType = "ApprovalParticipantProfile"
    /// Create-if-not-exists nonce consumption marker (authoritative, H4).
    static let nonceRecordType = "ApprovalNonce"
    /// B's Vault-Key-sealed participant private key (B's PRIVATE db).
    static let participantEscrowRecordType = "ApprovalParticipantEscrow"
    /// Encrypted presentation metadata (title/host) — separate from the grant.
    static let displayEnvelopeRecordType = "ApprovalDisplayEnvelope"

    // MARK: Fixed record names (zone is per-recipient + opaque-named; a fixed
    // name inside it leaks nothing beyond the already-visible recordType, and
    // singleton naming gives last-writer-wins conflict election for free).

    /// Pre-Family-sharing zone-wide singleton names: at most ONE grant (and
    /// its display envelope) per zone. Kept as read/write fallbacks so a
    /// share published before per-grant naming (`FamilyShareTransport`)
    /// keeps working — never remove without a migration.
    static let legacyGrantRecordName = "grant"
    static let legacyDisplayEnvelopeRecordName = "display-envelope"
    static let participantProfileRecordName = "participant-profile"
    static let participantEscrowRecordName = "approval-participant-escrow"

    /// Deterministic per-grant record name (Family sharing, `FamilyShareTransport`):
    /// lets N grants coexist in one zone instead of the legacy singleton
    /// overwriting on every publish. `grantId` is already opaque (CSPRNG),
    /// so the name leaks nothing beyond record existence + count.
    static func grantRecordName(grantId: String) -> String { "grant:" + grantId }

    /// Deterministic per-grant display-envelope name — pairs with
    /// `grantRecordName(grantId:)`.
    static func displayEnvelopeRecordName(grantId: String) -> String { "display:" + grantId }

    // MARK: Subscription identifiers (push routing keys — see AppPushKind)

    /// Owner-side alert subscription on an approval zone in the PRIVATE db.
    /// Per-zone id: `approval-req-<opaqueZoneName>` so routing can prefix-match.
    static let requestSubscriptionPrefix = "approval-req-"
    /// Participant-side silent database subscription on the SHARED db.
    static let sharedDatabaseSubscriptionID = "approval-shared-db"

    static func requestSubscriptionID(zoneName: String) -> String {
        requestSubscriptionPrefix + zoneName
    }

    /// Owner-side SILENT subscription on the participant-profile record in an
    /// approval zone: fires when the recipient's device publishes its identity
    /// (the moment the share becomes actionable for the owner). Per-zone id so
    /// routing can prefix-match and revoke can delete it by name.
    static let acceptSubscriptionPrefix = "approval-accept-"

    static func acceptSubscriptionID(zoneName: String) -> String {
        acceptSubscriptionPrefix + zoneName
    }

    // MARK: Public-DB invite rendezvous (U5 — opaque inbox, push = hint)

    /// Public-db record carrying an invite drop. Shares the type used by
    /// link invites ("inv-…" records); rendezvous drops add the queryable
    /// `recipientInboxID` field that link records simply lack.
    static let publicInviteRecordType = "LooxInvite"
    /// Recipient-published inbox descriptor, keyed by the OPAQUE CloudKit
    /// user record id (never email or any PII-derived value — U3).
    static let inviteInboxDescriptorRecordType = "LooxInviteInbox"
    /// Recipient-side query subscription on the PUBLIC db (invite drops
    /// addressed to this account's inboxID).
    static let inviteInboxSubscriptionID = "loox-invite-inbox"

    // MARK: Opaque naming

    /// Random, meaning-free identifier for zone and record names. 20 bytes of
    /// CSPRNG entropy, hex-encoded — no recipient id, item id, or field kind.
    static func opaqueName() -> String {
        CryptoRandom.bytes(20).map { String(format: "%02x", $0) }.joined()
    }

    /// Approval zones are recognizable by prefix (so the app can enumerate its
    /// own approval zones) but carry no recipient information.
    static let zonePrefix = "apz-"

    static func opaqueZoneName() -> String { zonePrefix + opaqueName() }

    // MARK: TTLs (Int64 unix MILLISECONDS — kernel time convention, ADR-7)

    /// A request older than this is stale — the owner UI must not offer it for
    /// approval (TOTP codes rotate every 30s; a minutes-old ask is meaningless).
    /// Matches `ApprovalVerifier.maxRequestLifetimeMs`.
    static let requestTTLMs: Int64 = 120_000
    /// A sealed response is discarded by the requester after this window.
    static let responseTTLMs: Int64 = 90_000
}
