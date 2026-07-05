import Foundation

/// Control-plane data models for Approval Mode sharing.
///
/// SECURITY TIME INVARIANT (ADR-7): every protocol timestamp is Unix epoch
/// MILLISECONDS (`Int64`) — an absolute UTC instant. Local time zones are
/// display-only; no `Calendar`/`TimeZone`/`DateComponents` in this kernel.
/// All types are `nonisolated` + `Sendable` (project default isolation is
/// MainActor; the kernel must run anywhere).

// MARK: - Capabilities (per-field, type-constrained)

/// TOTP fields can be `none` or `askEachTime` — never `shared` (the seed
/// stays in the owner's vault, ADR-1).
nonisolated enum TOTPFieldCapability: UInt8, Codable, Sendable {
    case none = 0
    case askEachTime = 1
}

/// Non-TOTP fields (password/username/url/text) can be `none` or `shared` —
/// `askEachTime` is deliberately unrepresentable for them (user-locked
/// decision 2: ask-each-time is TOTP-only in V1).
nonisolated enum ValueFieldCapability: UInt8, Codable, Sendable {
    case none = 0
    case shared = 1
}

/// A field's share capability. The two-case split makes invalid combinations
/// (password ask-each-time, TOTP shared) impossible at the type level.
nonisolated enum FieldCapability: Codable, Sendable, Equatable {
    case totp(TOTPFieldCapability)
    case value(ValueFieldCapability)

    var isAskEachTimeTOTP: Bool {
        if case .totp(.askEachTime) = self { return true }
        return false
    }

    var isSharedValue: Bool {
        if case .value(.shared) = self { return true }
        return false
    }
}

// MARK: - Grant

/// Owner-signed capability delegation for one item to one recipient.
/// Contains no secrets — it is signed (tamper-evident), not sealed.
/// `capabilities` keys are `DynamicField.id` values; the verifier FAILS CLOSED
/// on any fieldId not present here (M3 — field ids are mutable strings).
/// `Codable` serves the recipient's sealed projection snapshot (instant
/// re-hydration after unlock) — the CloudKit wire format stays the canonical
/// encoding. Snapshots only ever encode already-normalized grants, so the
/// synthesized decode may skip the init's pinned-key sorting.
nonisolated struct AccessGrant: Sendable, Equatable, Codable {
    var id: String
    var itemId: String
    /// Opaque recipient identifier — never an email/name (M2 metadata hygiene).
    var recipientId: String
    /// B's persistent HPKE public key (Curve25519) — `shared` blobs seal to it.
    var participantPubKey: Data
    /// Pinned P256 signing public keys of B's enrolled devices (ADR-4).
    /// Requests signed by any other key are rejected.
    var pinnedDeviceSigningKeys: [Data]
    var capabilities: [String: FieldCapability]
    /// Bumped on revoke; requests verified against the CURRENT epoch only.
    var epoch: UInt32
    var createdAtUnixMs: Int64
    var expiresAtUnixMs: Int64?
    var ownerSigningPubKey: Data
    var ownerSignature: Data

    /// Pinned keys are normalized to sorted order at construction so the
    /// in-memory value, the signed canonical bytes, and a decoded copy are
    /// all identical (`decode(encoded(x)) == x` — no phantom diffs in sync).
    init(id: String, itemId: String, recipientId: String, participantPubKey: Data,
         pinnedDeviceSigningKeys: [Data], capabilities: [String: FieldCapability],
         epoch: UInt32, createdAtUnixMs: Int64, expiresAtUnixMs: Int64?,
         ownerSigningPubKey: Data, ownerSignature: Data) {
        self.id = id
        self.itemId = itemId
        self.recipientId = recipientId
        self.participantPubKey = participantPubKey
        self.pinnedDeviceSigningKeys = pinnedDeviceSigningKeys
            .sorted { $0.lexicographicallyPrecedes($1) }
        self.capabilities = capabilities
        self.epoch = epoch
        self.createdAtUnixMs = createdAtUnixMs
        self.expiresAtUnixMs = expiresAtUnixMs
        self.ownerSigningPubKey = ownerSigningPubKey
        self.ownerSignature = ownerSignature
    }
}

// MARK: - Request

/// Recipient-signed ask for one `askEachTime` capability use.
nonisolated struct ApprovalRequest: Sendable, Equatable {
    var requestId: String
    var grantId: String
    /// Opaque id of B's device (label lives client-side, not in the record).
    var requesterDeviceId: String
    var itemId: String
    var fieldId: String
    /// Single-use anti-replay value; consumed authoritatively (H4).
    var nonce: Data
    /// Per-request ephemeral HPKE public key — the approval payload seals to
    /// THIS key (ADR-3), giving forward secrecy per request.
    var ephemeralPubKey: Data
    var createdAtUnixMs: Int64
    var expiresAtUnixMs: Int64
    /// Which pinned device key signed this request (must ∈ grant's pinned set).
    var requesterSigningPubKey: Data
    var requesterSignature: Data
}

// MARK: - Response

nonisolated enum ApprovalDecision: UInt8, Codable, Sendable {
    case approved = 1
    case rejected = 2
    /// Owner backgrounded/locked mid-ceremony (ADR-6 abort) — B should re-request.
    case interrupted = 3
}

/// Owner-signed answer to a request. For `approved`, `sealedPayload` is the
/// HPKE envelope (sealed to the request's EPHEMERAL key) containing a
/// `TOTPApprovalPayload`; the signature covers the ciphertext bytes.
nonisolated struct ApprovalResponse: Sendable, Equatable {
    var requestId: String
    var decision: ApprovalDecision
    var sealedPayload: Data?
    var respondedAtUnixMs: Int64
    var ownerSigningPubKey: Data
    var ownerSignature: Data
}

/// The plaintext inside an approved response's sealed envelope. Carries full
/// window context (ADR-7): B renders an ADVISORY countdown from
/// `periodEndUnixMs`, can reject stale responses, and can attribute latency —
/// but the relying party's clock is always the final authority.
nonisolated struct TOTPApprovalPayload: Codable, Sendable, Equatable {
    var code: String
    var counter: UInt64
    var period: UInt32
    var generatedAtUnixMs: Int64
    var periodStartUnixMs: Int64
    var periodEndUnixMs: Int64
    /// Echoes the request nonce — binds payload to the exact request.
    var requestNonce: Data
}

// MARK: - TOTP window math (ADR-7 — integer Unix arithmetic ONLY)

/// RFC 6238 moving-factor math on absolute Unix time. Timezones and DST can
/// never shift these values; two devices at the same instant anywhere on
/// Earth compute identical results.
nonisolated enum TOTPWindow {
    /// `period == 0` (malformed remote input) degrades FAIL-CLOSED: counter 0,
    /// zero remaining life — a garbage payload renders as already expired,
    /// it never traps and never looks fresh.
    static func counter(atUnixMs unixMs: Int64, period: UInt32) -> UInt64 {
        guard period > 0 else { return 0 }
        return UInt64(max(0, unixMs / 1000)) / UInt64(period)
    }

    static func periodStartUnixMs(atUnixMs unixMs: Int64, period: UInt32) -> Int64 {
        guard period > 0 else { return unixMs }
        return Int64(counter(atUnixMs: unixMs, period: period)) * Int64(period) * 1000
    }

    static func periodEndUnixMs(atUnixMs unixMs: Int64, period: UInt32) -> Int64 {
        guard period > 0 else { return unixMs }
        return periodStartUnixMs(atUnixMs: unixMs, period: period) + Int64(period) * 1000
    }

    /// Remaining life of the CURRENT window at `unixMs` (0 when malformed).
    static func remainingMs(atUnixMs unixMs: Int64, period: UInt32) -> Int64 {
        periodEndUnixMs(atUnixMs: unixMs, period: period) - unixMs
    }
}

/// Boundary-aware issuance policy (ADR-6). Named constants — never inline
/// magic numbers. `minimumRemainingLifetime` = estimated delivery budget (5s)
/// + minimum recipient use budget (10s) + clock-skew budget (3s, ADR-7/H8).
nonisolated struct TOTPIssuancePolicy: Sendable {
    var minimumRemainingLifetimeMs: Int64 = 18_000
    var responseTimeoutMs: Int64 = 20_000

    static let v1 = TOTPIssuancePolicy()

    /// True → issue the current-window code now; false → the issuer must WAIT
    /// for the next period boundary and generate the then-current code
    /// (never pre-send a future-period code — ADR-6).
    func canIssueNow(atUnixMs unixMs: Int64, period: UInt32) -> Bool {
        TOTPWindow.remainingMs(atUnixMs: unixMs, period: period) >= minimumRemainingLifetimeMs
    }
}
