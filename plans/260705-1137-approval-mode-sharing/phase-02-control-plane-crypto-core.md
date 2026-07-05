---
phase: 2
title: "Control-plane crypto core + trust anchoring"
status: completed # 2026-07-05 — 161/161 tests, review applied (see Implementation Status)
priority: P1
effort: "2.5d"
dependencies: [1]
---

# Phase 2: Control-plane crypto core + trust anchoring

## Overview
The transport-agnostic security kernel (VaultifyCore, `nonisolated`). **This is net-new crypto** — the
existing HPKE/P256 sites are *pattern* references only (their `info`/lengths are hard-coded; WebAuthn has
no verify/persistence). Delivers: persistent device signing identity, canonical sign/verify with **pinned
key sets** (ADR-4), HPKE sealing to the correct key per ADR-3, authoritative replay protection, epoch,
and B's participant-identity escrow model. Independently testable; the whole trust model rests here.

## Requirements
- Functional: create/persist a device signing identity; build+sign `ApprovalRequest`; verify against a
  grant using a **pinned** recipient-signing-key set; seal `askEachTime` responses to the per-request
  ephemeral key and `shared` blobs to the participant key; enforce authoritative nonce-once + epoch +
  expiry; compute a stable **out-of-band fingerprint** for A↔B.
- Non-functional: `nonisolated`/`Sendable`; deterministic versioned canonical encoding (survives CKRecord
  round-trip — validated in Phase 8 gate); no plaintext secret/Vault Key in any control-plane record.
- **Time invariant (ADR-7/H8):** every protocol timestamp is **Unix epoch milliseconds (`Int64`)** in
  models and canonical bytes; NO `Calendar`/`TimeZone`/`DateComponents` anywhere in the kernel; TOTP
  window math = integer Unix arithmetic. `ApprovalPayload` replaced by
  `TOTPApprovalPayload { code, counter: UInt64, period: UInt32, generatedAtUnixMs, periodStartUnixMs,
  periodEndUnixMs, requestNonce }` (countdown advisory; RP is final authority).

## Architecture
- **Device signing identity (net-new):** `DeviceSigningIdentity` — `P256.Signing.PrivateKey` persisted via
  `KeychainStore`; exposes `publicKeyRaw`, `signature(for:)`, static `verify(_:signature:publicKey:)`.
- **Trust anchoring (ADR-4):** `AccessGrant` carries the **set of pinned B device signing public keys**
  (owner-signed). `ApprovalVerifier` rejects any `requesterSignature` whose key ∉ pinned set. Enrolling a
  new B device key requires an owner-approved enrollment (Face ID). `TrustFingerprint` derives a short
  human-comparable string from (ownerSigningPubKey, participantPubKey) for the one-time OOB compare;
  once confirmed, TOFU-pin — reject grants whose owner key later differs.
- **Participant identity escrow (ADR-2):** define `ParticipantIdentity { participantPubKey (HPKE),
  participantPrivKey }`; its private key is sealed under **B's Vault Key** and written to a dedicated
  synced record (Phase 3), modeled on `VaultKeyEscrowService` — NOT piggybacked on item sync.
- **Models (`Codable`, `Sendable`, `nonisolated`):**
  - `CapabilitySet` = `fieldId → FieldCapability`. `FieldCapability`: TOTP field → `none|askEachTime`;
    other fields → `none|shared`. **`askEachTime` is representable only for TOTP** (constrain the type so
    password ask-each-time is unrepresentable — resolves the open question, M3/N).
  - `AccessGrant { id, itemId, recipientId, participantPubKey, pinnedDeviceSigningKeys:[Data],
    capabilities, epoch, expiresAt?, ownerSigningPubKey, ownerSignature }`.
  - `ApprovalRequest { requestId, grantId, requesterDeviceId, context(.totp itemId), nonce,
    ephemeralPubKey, createdAt, expiresAt, requesterSignature }`.
  - `ApprovalResponse { requestId, decision, sealedPayload?, ownerSigningPubKey, ownerSignature }`;
    `ApprovalPayload { code, validUntil, requestNonce }`.
- **Seal contract (ADR-3):** `ApprovalSeal.sealResponse(payload, toEphemeral:info:)` where `info =
  requestId+nonce`; `sealSharedBlob(value, toParticipant:)`. Two distinct recipients — never cross them.
- **Field-id stability (M3):** capability keys must be stable across owner edits; verifier **fails closed**
  on an unknown/absent fieldId (no default-open). Document the id-preservation requirement for the editor.
- **Authoritative nonce (H4):** `ApprovalNonceStore` consumes a nonce by **creating a CloudKit
  create-if-not-exists record** (record name = nonce) so a second owner device colliding on the same
  nonce fails; local durable cache (Keychain/app-group) as fast path, never TTL-pruned below max request
  lifetime.
- **Canonical encoding:** explicit versioned deterministic byte layout (NOT default `JSONEncoder`); a
  `version` byte enables same-version precondition + future negotiation.

## Related Code Files
- Create (collapse to ~3–4 files, M4 — not one-per-type): `VaultifyCore/Sharing/ApprovalModels.swift`
  (grant/request/response/capability/fingerprint), `ApprovalCrypto.swift` (device identity + canonical +
  seal), `ApprovalVerifier.swift` (+ nonce store interface), `ParticipantIdentity.swift`
- Reference/reuse: `VaultifyCore/Keychain/KeychainStore.swift` (genuine reuse), `VaultKeyPairing.swift` /
  `PasskeyEnvelope.swift` (HPKE technique), `VaultKeyEscrowService.swift` (escrow model),
  `VaultifyCore/Models/DynamicField.swift`, `FieldKind.swift`, `TOTPGenerator.swift`

## Implementation Steps
1. `DeviceSigningIdentity` (persist/sign/verify).
2. Models + `FieldCapability` (TOTP-only `askEachTime` constrained by type); `nonisolated`/`Sendable`.
3. `TrustFingerprint` + pinned-key set on grant; verifier rejects unpinned keys.
4. `ApprovalCrypto` canonical (versioned) + `ApprovalSeal` (ADR-3 two-recipient contract).
5. `ParticipantIdentity` + Vault-Key-sealed escrow encoding (transport in Phase 3).
6. `ApprovalNonceStore` interface with authoritative create-if-not-exists semantics (impl wired in P3).
7. `ApprovalVerifier`: pinned-signature ∧ grant epoch ∧ participant ∧ not-expired ∧ nonce-fresh ∧
   fail-closed on unknown fieldId; typed failure reasons.
8. DEBUG file-based self-test: sign/verify/tamper, HPKE seal→open (both recipient types), replay rejected,
   stale epoch rejected, unpinned key rejected, unknown fieldId fails closed.

## Success Criteria
- [ ] Request signed on device A-sim verifies on B-sim only when its signing key is pinned; unpinned → reject.
- [ ] Tamper (itemId/epoch/expiry/fieldId) → verify fails; unknown fieldId → fail closed.
- [ ] `askEachTime` payload seals to ephemeral key & opens with ephemeral private key; `shared` blob seals
      to participant key — cross-open fails (ADR-3 enforced).
- [ ] Replayed nonce rejected authoritatively (second device collides); expired/stale-epoch rejected.
- [ ] Fingerprint deterministic + stable; changed owner key rejected after pin.
- [ ] All types `nonisolated` under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- [ ] **ADR-7:** zero `Calendar`/`TimeZone`/`DateComponents` in kernel (grep); all timestamps Int64 unix
      ms; mocked same-instant test across NY↔HCMC and LA↔Tokyo yields same counter/boundary/remaining.

## Implementation Status — 2026-07-05

**Complete (uncommitted).** 5 files in `VaultifyCore/Sharing/`: `ApprovalModels.swift` (capability types,
grant/request/response, `TOTPApprovalPayload` per ADR-7, `TOTPWindow` integer math, `TOTPIssuancePolicy`),
`ApprovalCanonical.swift` (CanonicalWriter/Reader, versioned type-tagged encode/decode — transported bytes
ARE the canonical bytes), `ApprovalCrypto.swift` (`DeviceSigningIdentity` P256+Keychain, `ApprovalSeal`
HPKE two-recipient, `TrustFingerprint`), `ApprovalVerifier.swift` (+`ApprovalNonceStore` protocol),
`ParticipantIdentity.swift` (escrow under Vault Key). 14 unit tests in
`VaultifyTests/ApprovalKernelTests.swift`; suite 161/161; iOS+macOS compile green; ADR-7 grep gate clean.
Deviation: unit tests (XCTest) instead of the file-based DEBUG self-test — cleaner for pure logic; the
device self-test remains a Phase 8 item.

**Review applied** (`plans/reports/from-code-reviewer-260705-phase2-approval-crypto-kernel-report.md` —
0 crypto defects): H1 `verifyRequest` now takes explicit `trustedOwnerSigningKeys` (no self-pin
tautology; storage ACLs are not the trust anchor); H2 kernel-owned `verifyResponse` (requestId binding,
owner pin, signature, decision/payload consistency); M1 pinned keys normalized sorted at init
(decode(encoded(x)) == x, multi-key test added); M2 request-lifetime clamp
(`maxRequestLifetimeMs = 120s`); M3 HPKE info via CanonicalWriter (injective, pre-wire-ship); M4
`loadOrCreate` throws `.corruptKeyMaterial` instead of silently regenerating; Low: `TOTPWindow` fails
closed on `period == 0`; nonce/ephemeral-key shape checked BEFORE the ceremony (`.malformedRequest`).

**Accepted/deferred (documented, not bugs):** app+AutoFill extension share one signing identity via the
shared keychain group — intentional for V1 (one logical "device"); escrow AAD domain separation,
writer-side `UInt32(count)` trap, fingerprint ~50-bit strength note → Phase 8 hardening list.
**→ Phase 3 must decide:** which key signs grants for a multi-device OWNER (the
`trustedOwnerSigningKeys` set is the kernel hook; distribution/sync of that set is transport work);
align `ApprovalConfig` TTL units (TimeInterval seconds) with kernel Int64-ms convention.

## Risk Assessment
- Canonical-encoding drift → signature mismatch. Mitigation: versioned encoder + Phase 8 CKRecord
  round-trip gate + self-test.
- This is a large security kernel (effort raised to 2.5d after red-team reclassified "reuse" as net-new).
  Keep files cohesive but under ~200 LoC; split only if a file actually exceeds it.
