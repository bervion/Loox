import CryptoKit
import Foundation

/// Verification of inbound control-plane artifacts. FAIL-CLOSED throughout:
/// any missing/unknown/ambiguous input is a rejection with a typed reason —
/// never a default-open. Verification runs BEFORE any approval UI (ADR-1).

/// Single-use nonce consumption. The Phase-3 implementation is AUTHORITATIVE
/// across the owner's devices (CloudKit create-if-not-exists record named by
/// the nonce, H4) with a durable local fast path; tests use an in-memory one.
nonisolated protocol ApprovalNonceStore: Sendable {
    /// Atomically consume `nonce`. Returns true if it was fresh (first use),
    /// false if already consumed. Throws when authority is unreachable — the
    /// verifier maps that to a rejection (fail closed), not an approval.
    func consume(nonce: Data, expiresAtUnixMs: Int64) async throws -> Bool
}

nonisolated enum ApprovalVerifyFailure: Error, Equatable {
    case ownerKeyUnpinned      // grant/response owner key not trusted/pinned
    case badGrantSignature
    case grantExpired
    case staleEpoch            // grant epoch ≠ current (revoked / superseded)
    case grantMismatch         // request points at a different grant/item
    case requesterKeyUnpinned  // signing key ∉ grant's pinned device set
    case badRequestSignature
    case requestExpired
    case requestLifetimeTooLong // B-signed lifetime exceeds the kernel clamp
    case malformedRequest      // nonce/ephemeral key shape invalid
    case unknownField          // fieldId not in capabilities → FAIL CLOSED (M3)
    case capabilityNotGranted  // field exists but isn't askEachTime TOTP
    case replayedNonce
    case nonceAuthorityUnavailable
    case responseMismatch      // response.requestId ≠ the awaited request
    case badResponseSignature
    case malformedResponse     // decision/payload combination inconsistent
}

/// Verification WITHOUT nonce consumption — for showing a request in UI
/// before the owner acts. The nonce is single-use; burning it at display
/// time would make a viewed-then-dismissed request permanently unapprovable.
/// NEVER use for issuance: the approve path must consume authoritatively.
nonisolated struct PreviewNonceStore: ApprovalNonceStore {
    init() {}
    func consume(nonce: Data, expiresAtUnixMs: Int64) async throws -> Bool { true }
}

nonisolated enum ApprovalVerifier {

    /// Hard upper bound on a request's B-signed lifetime. Without it the
    /// requester could sign a decade-long request, keeping it approvable and
    /// forcing unbounded nonce retention. Matches the transport-level TTL.
    static let maxRequestLifetimeMs: Int64 = 120_000

    /// Grant-level checks: TOFU owner-key pin, signature, expiry.
    /// `pinnedOwnerSigningKey` is nil only before the one-time fingerprint
    /// ceremony; after pinning, a changed owner key is rejected (ADR-4).
    static func verifyGrant(_ grant: AccessGrant,
                            pinnedOwnerSigningKey: Data?,
                            nowUnixMs: Int64) -> ApprovalVerifyFailure? {
        if let pinned = pinnedOwnerSigningKey, pinned != grant.ownerSigningPubKey {
            return .ownerKeyUnpinned
        }
        guard DeviceSigningIdentity.verify(grant.signingBody(),
                                           signature: grant.ownerSignature,
                                           publicKeyRaw: grant.ownerSigningPubKey) else {
            return .badGrantSignature
        }
        if let expiresAt = grant.expiresAtUnixMs, nowUnixMs >= expiresAt {
            return .grantExpired
        }
        return nil
    }

    /// Full owner-side request verification (Global Success Criterion 3).
    /// `trustedOwnerSigningKeys` is the explicit trust root: the owner's own
    /// enrolled device signing keys — a grant signed by anything else is
    /// rejected regardless of internal consistency (storage ACLs are NOT the
    /// trust anchor). `currentEpoch` MUST come from a fresh fetch of the
    /// owner's epoch state at approve time — never a cached value (revoke
    /// must bite immediately). The nonce is consumed LAST so an
    /// otherwise-invalid request can't burn a nonce record.
    static func verifyRequest(_ request: ApprovalRequest,
                              grant: AccessGrant,
                              trustedOwnerSigningKeys: [Data],
                              currentEpoch: UInt32,
                              nowUnixMs: Int64,
                              nonceStore: any ApprovalNonceStore) async -> ApprovalVerifyFailure? {
        // 1. Request ↔ grant linkage.
        guard request.grantId == grant.id, request.itemId == grant.itemId else {
            return .grantMismatch
        }
        // 2. Grant provenance: signed by one of the owner's OWN keys.
        guard trustedOwnerSigningKeys.contains(grant.ownerSigningPubKey) else {
            return .ownerKeyUnpinned
        }
        if let failure = verifyGrant(grant, pinnedOwnerSigningKey: nil, nowUnixMs: nowUnixMs) {
            return failure
        }
        // 3. Epoch freshness — a revoked recipient's grant is stale.
        guard grant.epoch == currentEpoch else { return .staleEpoch }
        // 4. Requester key must be pinned in the grant (ADR-4).
        guard grant.pinnedDeviceSigningKeys.contains(request.requesterSigningPubKey) else {
            return .requesterKeyUnpinned
        }
        // 5. Request signature over canonical bytes.
        guard DeviceSigningIdentity.verify(request.signingBody(),
                                           signature: request.requesterSignature,
                                           publicKeyRaw: request.requesterSigningPubKey) else {
            return .badRequestSignature
        }
        // 6. Shape sanity BEFORE the ceremony: a garbage ephemeral key must
        // fail here, not after Face ID when sealing the response.
        guard request.nonce.count >= 16, request.nonce.count <= 64,
              (try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: request.ephemeralPubKey)) != nil else {
            return .malformedRequest
        }
        // 7. Lifetime (absolute Unix time — ADR-7) + kernel clamp: the
        // requester signs its own expiry, so bound it server-side of trust.
        guard nowUnixMs < request.expiresAtUnixMs else { return .requestExpired }
        guard request.expiresAtUnixMs > request.createdAtUnixMs,
              request.expiresAtUnixMs - request.createdAtUnixMs <= Self.maxRequestLifetimeMs,
              request.expiresAtUnixMs <= nowUnixMs + Self.maxRequestLifetimeMs else {
            return .requestLifetimeTooLong
        }
        // 8. Capability lookup — unknown fieldId FAILS CLOSED (M3).
        guard let capability = grant.capabilities[request.fieldId] else {
            return .unknownField
        }
        guard capability.isAskEachTimeTOTP else { return .capabilityNotGranted }
        // 9. Nonce — authoritative single use, consumed only now.
        do {
            guard try await nonceStore.consume(nonce: request.nonce,
                                               expiresAtUnixMs: request.expiresAtUnixMs) else {
                return .replayedNonce
            }
        } catch {
            return .nonceAuthorityUnavailable
        }
        return nil
    }

    /// Recipient-side (B) response verification — kernel-owned so Phase 5/6
    /// cannot hand-roll it inconsistently: requestId binding, TOFU-pinned
    /// owner key, signature, and decision/payload consistency (`approved`
    /// without a payload — or a payload on reject — is malformed).
    static func verifyResponse(_ response: ApprovalResponse,
                               expectedRequestId: String,
                               pinnedOwnerSigningKey: Data) -> ApprovalVerifyFailure? {
        guard response.requestId == expectedRequestId else { return .responseMismatch }
        guard response.ownerSigningPubKey == pinnedOwnerSigningKey else { return .ownerKeyUnpinned }
        guard DeviceSigningIdentity.verify(response.signingBody(),
                                           signature: response.ownerSignature,
                                           publicKeyRaw: response.ownerSigningPubKey) else {
            return .badResponseSignature
        }
        switch response.decision {
        case .approved:
            guard let payload = response.sealedPayload, !payload.isEmpty else {
                return .malformedResponse
            }
        case .rejected, .interrupted:
            guard response.sealedPayload == nil else { return .malformedResponse }
        }
        return nil
    }
}
