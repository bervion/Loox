import Foundation

/// Control-plane data models for Approval Mode sharing.
///
/// SECURITY TIME INVARIANT (ADR-7): every protocol timestamp is Unix epoch
/// MILLISECONDS (`Int64`) — an absolute UTC instant. Local time zones are
/// display-only; no `Calendar`/`TimeZone`/`DateComponents` in this kernel.
/// All types are `nonisolated` + `Sendable` (project default isolation is
/// MainActor; the kernel must run anywhere).

// MARK: - Capabilities (per-field, type-constrained)

/// TOTP fields: `none`, `askEachTime`, or `shared` (seed hand-over).
/// `shared` is a CONSCIOUS reversal of ADR-1 (user decision 260705): it is
/// only offered behind an explicit warning modal, encodes as wire v2, and a
/// delivered seed is not cryptographically revocable (INV-08).
nonisolated enum TOTPFieldCapability: UInt8, Codable, Sendable {
    case none = 0
    case askEachTime = 1
    case shared = 2
}

/// Passkey slots (wire v2 only): `askEachTime` = the owner signs the
/// assertion on THEIR device per use (INV-07); `shared` = private-key
/// hand-over behind the same warning modal semantics as TOTP `shared`.
nonisolated enum PasskeyFieldCapability: UInt8, Codable, Sendable {
    case none = 0
    case askEachTime = 1
    case shared = 2
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
    case passkey(PasskeyFieldCapability)

    var isAskEachTimeTOTP: Bool {
        if case .totp(.askEachTime) = self { return true }
        return false
    }

    /// Capabilities whose plaintext ships in a sealed shared blob: classic
    /// shared values AND the v2 hand-over modes (TOTP seed, passkey key).
    var isSharedValue: Bool {
        switch self {
        case .value(.shared), .totp(.shared), .passkey(.shared): return true
        default: return false
        }
    }

    /// The v2 hand-over modes (TOTP seed, passkey key): delivered material the
    /// owner cannot pull back (INV-08), so picking one always goes through the
    /// hand-over confirmation first.
    var isHandOver: Bool {
        switch self {
        case .totp(.shared), .passkey(.shared): return true
        default: return false
        }
    }

    /// Grants something (any non-none mode) — drives the owner sheet's
    /// "at least one capability" gate across all three kinds.
    var grantsAnything: Bool {
        switch self {
        case .totp(.none), .value(.none), .passkey(.none): return false
        default: return true
        }
    }

    /// Encodable only in wire v2 — a v1 grant carrying one of these is
    /// malformed (decode rejects; the layout guard in ApprovalCanonical).
    var requiresWireV2: Bool {
        switch self {
        case .passkey: return true
        case .totp(.shared): return true
        default: return false
        }
    }
}

// MARK: - Passkey capability slots (wire v2)

/// Passkeys are not `DynamicField`s — their capability rides in the grant's
/// map under a synthetic slot id derived from the credential id, so the
/// fail-closed verifier rule ("unknown fieldId → reject") keeps working
/// unchanged for passkey slots.
nonisolated enum PasskeySlot {
    static let prefix = "passkey::"

    static func slotId(credentialID: Data) -> String { prefix + credentialID.hexString }

    static func isPasskeySlot(_ fieldOrSlotId: String) -> Bool {
        fieldOrSlotId.hasPrefix(prefix)
    }

    static func credentialID(fromSlotId id: String) -> Data? {
        guard id.hasPrefix(prefix) else { return nil }
        return Data(hexString: String(id.dropFirst(prefix.count)))
    }
}

/// Plaintext of an approved passkey assertion, sealed to the request's
/// ephemeral key (forward secrecy) and bound to the request via the HPKE
/// info AND the echoed fields below — the requester verifies every echo
/// before completing the WebAuthn ceremony (INV-09).
nonisolated struct PasskeyApprovalPayload: Codable, Sendable, Equatable {
    var authenticatorData: Data
    var signature: Data
    var userHandle: Data
    var credentialID: Data
    var clientDataHash: Data
    var requestNonce: Data
}

// MARK: - Device scope (wire v2)

/// Whether the recipient may use this grant on all their enrolled devices or
/// exactly the device(s) named in `allowedDeviceKeyBindings` (sealed
/// per-device — not merely policy-checked, INV-04/05).
nonisolated enum DeviceScope: UInt8, Codable, Sendable {
    case multi = 0
    case single = 1
}

// MARK: - Device key bindings (per-device seal, P03)

/// Names one recipient device inside a v2 grant: the stable device id plus a
/// hash binding of its CURRENT HPKE public key. The raw public key lives in
/// the profile's device directory, OUTSIDE the signed grant — verifiers must
/// check `SHA256(directory pubkey) == hpkePublicKeyHash` before sealing to or
/// trusting that key (substitution guard, INV-12).
nonisolated struct DeviceKeyBinding: Codable, Sendable, Equatable {
    var deviceKeyID: Data
    var hpkePublicKeyHash: Data
}

/// One entry of the recipient-published device directory (participant
/// profile record). Public material only — never a private key.
nonisolated struct DeviceHPKEDirectoryEntry: Codable, Sendable, Equatable {
    var deviceKeyID: Data
    var hpkePublicKey: Data
    var label: String
    var addedAtUnixMs: Int64

    static func encodeDirectory(_ entries: [DeviceHPKEDirectoryEntry]) throws -> Data {
        try JSONEncoder().encode(entries)
    }

    /// Lenient decode: an unreadable directory yields [] (legacy profiles
    /// predate the field entirely) — grants v2 then simply cannot seal to
    /// this recipient until a device republishes.
    static func decodeDirectory(_ data: Data?) -> [DeviceHPKEDirectoryEntry] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([DeviceHPKEDirectoryEntry].self, from: data)) ?? []
    }
}

/// Pure merge rules for the multi-device profile record (unit-tested): each
/// device republished the singleton profile with `.allKeys` before P03a,
/// silently dropping sibling devices — merging keeps every enrolled device.
nonisolated enum ParticipantProfileMerge {
    /// Upsert by deviceKeyID (a republish refreshes label/key), stable order
    /// by first enrollment time then id — deterministic for tests and UI.
    static func directory(existing: [DeviceHPKEDirectoryEntry],
                          upserting entry: DeviceHPKEDirectoryEntry) -> [DeviceHPKEDirectoryEntry] {
        var merged = existing.filter { $0.deviceKeyID != entry.deviceKeyID }
        merged.append(entry)
        return merged.sorted {
            ($0.addedAtUnixMs, $0.deviceKeyID.hexString) < ($1.addedAtUnixMs, $1.deviceKeyID.hexString)
        }
    }

    /// Union preserving existing order; the new key appends if unseen.
    static func signingKeys(existing: [Data], adding key: Data) -> [Data] {
        existing.contains(key) ? existing : existing + [key]
    }
}

extension Data {
    nonisolated var hexString: String { map { String(format: "%02x", $0) }.joined() }

    nonisolated init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
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
    /// Wire v2 (P03b): device scope + the device-key bindings sealed to.
    /// `.multi` + empty bindings keeps the grant on wire v1, bit-identical
    /// to pre-P03b bytes — existing signatures stay valid.
    var deviceScope: DeviceScope
    var allowedDeviceKeyBindings: [DeviceKeyBinding]

    /// True when any field forces the v2 canonical layout.
    var requiresWireV2: Bool {
        deviceScope != .multi || !allowedDeviceKeyBindings.isEmpty
            || capabilities.values.contains { $0.requiresWireV2 }
    }

    /// Pinned keys and device bindings are normalized to sorted order at
    /// construction so the in-memory value, the signed canonical bytes, and
    /// a decoded copy are all identical (`decode(encoded(x)) == x` — no
    /// phantom diffs in sync; INV-12 deterministic ordering).
    init(id: String, itemId: String, recipientId: String, participantPubKey: Data,
         pinnedDeviceSigningKeys: [Data], capabilities: [String: FieldCapability],
         epoch: UInt32, createdAtUnixMs: Int64, expiresAtUnixMs: Int64?,
         ownerSigningPubKey: Data, ownerSignature: Data,
         deviceScope: DeviceScope = .multi,
         allowedDeviceKeyBindings: [DeviceKeyBinding] = []) {
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
        self.deviceScope = deviceScope
        self.allowedDeviceKeyBindings = allowedDeviceKeyBindings
            .sorted { $0.deviceKeyID.lexicographicallyPrecedes($1.deviceKeyID) }
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
    /// Wire v2 (passkey askEachTime): the exact 32-byte WebAuthn
    /// clientDataHash the approved assertion must sign — binds this approval
    /// to ONE challenge (INV-09). Nil for TOTP requests, which then encode
    /// bit-identical to wire v1. Realizes the P00
    /// `PasskeyAssertionApprovalRequestV1` transcript as a version bump of
    /// the audited request artifact instead of a parallel rail (amendment
    /// noted in security-invariants.md).
    var payloadBinding: Data? = nil
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
