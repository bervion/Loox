---
phase: 3
title: "CKShare transport, participant escrow & control-plane sync"
status: completed # 2026-07-05 — see Implementation Status; device round-trip QA rides Phase 8
priority: P1
effort: "2d"
dependencies: [1, 2]
---

# Phase 3: CKShare transport, participant escrow & control-plane sync

## Overview
Wire the Phase-2 kernel onto CloudKit CKShare (behavior proven by the Phase-1 spike). Owner creates a
per-recipient looked-up share, publishes the owner-signed grant + `shared` blobs; B publishes its
Vault-Key-escrowed participant identity; both exchange signed request/response with proper token-based
delta fetch and recovery. **Extract the shared change-token + single-flight helper from the existing sync
code (DRY, H7) — do not fork it.**

## Requirements
- Functional: owner creates share to a looked-up participant; B writes its participant identity + reads
  the grant; B writes signed `ApprovalRequest`; owner reads it, writes `ApprovalResponse`; B reads it.
  Authoritative nonce consumption (Phase 2) enforced server-side.
- Non-functional: control-plane zone separate + opaque-named (M2); payloads ciphertext only; graceful
  offline/retry; shared-DB change-token expiry recovery; single-flight; no duplicate sync logic.

## Architecture
- **Shared sync helper (H7):** extract the change-token cursor + single-flight loop currently inline in
  `CloudSyncService`/`SyncCoordinator` into a small reusable component used by BOTH the private-DB path
  and the new shared-DB path. `ApprovalRecordMapping` mirrors the existing `ckRecord/apply` shape.
- **Owner side — `ApprovalShareService`:** create opaque `approval-<opaque>` zone + `CKShare` restricted
  to a looked-up participant (`publicPermission = .none`, ADR-4); publish `AccessGrant` (with pinned B
  device keys) + sealed `SharedFieldBlob`s; write signed `ApprovalResponse`; consume nonce authoritatively.
- **Approval sync governance (ADR-2 / Validation §2):** all approval CloudKit work is a distinct
  `ApprovalSyncService` gated by `approvalModeEnabled` — **never** the `iCloudSyncEnabled` gate, and it
  **must not upload VaultItem records** (control plane ≠ secret plane). A user with `vaultItemSyncEnabled
  =false` + `approvalModeEnabled=true` gets full approval function and zero VaultItem uploads.
- **Participant escrow (ADR-2, transactional — Validation §3):** on accept (B already has a vault, Phase 6),
  B **transactionally** creates `ParticipantIdentity` → seals its private key under **B's Vault Key** →
  persists → publishes `participantPubKey` (never create-then-wait-to-escrow; crash-safe). Escrow record
  lives in B's private DB (modeled on `VaultKeyEscrowService`) so B's other devices recover it. A re-seals
  `shared` blobs when the item mutates.
- **Channel:** `ApprovalRequest` written by B (participant `.readWrite`, verified in Phase 1);
  `ApprovalResponse` written by A. Each carries a Phase-2 signature.
- **Fetch + recovery (H2-transport, U):** shared DB uses `CKFetchDatabaseChangesOperation` (DB token) →
  `CKFetchRecordZoneChangesOperation` (per-zone token); each handles `CKErrorChangeTokenExpired` by
  resetting that token and refetching (port the private-path reset at `CloudSyncService.swift:143-148`).
- **Coordinator:** `ApprovalCoordinator` (uses the shared single-flight helper) reacts to
  `.approvalRequestReceived` / `.approvalResponseReceived` (ADR-5 pipeline) and fetches deltas.

## Related Code Files
- Create: `Vaultify/Services/Sharing/ApprovalShareService.swift`, `ApprovalRecipientService.swift`,
  `ApprovalCoordinator.swift`, `ApprovalRecordMapping.swift`, `ParticipantEscrowService.swift`
- Create (shared, DRY): `Vaultify/Services/Sync/ZoneDeltaSyncHelper.swift` (extracted token+single-flight)
- Modify: `Vaultify/Services/Sync/CloudSyncService.swift` + `SyncCoordinator.swift` (adopt the extracted
  helper), `Vaultify/App/AppPushDelegate.swift`, `SharedZoneSubscriptionService.swift`
- Reference: `VaultKeyEscrowService.swift` (escrow model), `CloudSyncService.swift:133-187` (token/delta)

## Implementation Steps
1. Extract `ZoneDeltaSyncHelper`; refactor `CloudSyncService`/`SyncCoordinator` to use it (no behavior change).
2. `ApprovalRecordMapping`: Phase-2 models ↔ `CKRecord` (Data fields ciphertext/public; opaque names).
3. `ApprovalShareService.share(item:capabilities:to:)`: looked-up participant zone + CKShare + publish.
4. `ParticipantEscrowService`: create identity, Vault-Key-seal private key, sync record; publish pubkey.
5. `ApprovalRecipientService.request(.totp)`: build+sign (Phase 2) + save.
6. `ApprovalShareService.respond(...)`: verify (Phase 2, pinned) + seal (ADR-3) + authoritative nonce + save.
7. Shared-DB delta fetch with DB + per-zone tokens and `changeTokenExpired` reset both levels.
8. Wire push (ADR-5) → coordinator → fetch → domain events. Handle `.zoneNotFound`/`.userDeletedZone` (revoked).

## Success Criteria
- [ ] Private-DB sync unchanged after the helper extraction (regression check).
- [ ] Owner-sim shares to a looked-up participant-sim; B accepts, publishes escrowed participant identity,
      reads the grant; B's second device recovers the participant key and opens `shared` blobs.
- [ ] B writes a request; owner fetches within the Phase-1 measured latency; owner responds; B fetches & opens.
- [ ] `changeTokenExpired` on shared DB recovers (reset + refetch) without losing the delta.
- [ ] Authoritative nonce: a replayed request on a 2nd owner device collides and fails.
- [ ] CloudKit records show only ciphertext/public data; zone/record names opaque.

## Risk Assessment
- CKShare participant write + owner push already de-risked by Phase 1 spike; if Phase 1 flagged a
  permission gap, resolve it here before UI phases.
- Escrow record conflict (B accepts on two devices near-simultaneously) — resolved FIRST-writer-wins
  (create-if-not-exists; the losing device adopts the existing identity). Deliberate change from the
  earlier "last-writer by signed timestamp" draft: last-writer would let a second device silently
  replace a key the owner may already have pinned. (Planner-authored mitigation, not a user decision —
  confirmed by review 2026-07-05.)

## Implementation Status — 2026-07-05

**Complete (uncommitted).** NEW: `ZoneDeltaSyncHelper.swift` (ChangeTokenCursor + ZoneDeltaFetch
zone/database delta loops w/ reset-once recovery + SingleFlight — H7 extraction),
`ApprovalRecordMapping.swift` (canonical blob = single opaque `blob` field; nonce markers),
`ApprovalShareService.swift` (idempotent looked-up share, `alertLocalizationKey` push copy EN+VI,
publishGrant + sealed blobs + stale-blob GC, fetchGrantFresh, verifyInbound w/ `CloudKitNonceStore`
create-if-not-exists, respond), `ParticipantEscrowService.swift` (transactional escrow; creates the
private "Vault" zone itself — ADR-2 works with vault sync OFF), `ApprovalRecipientService.swift`
(TOFU pin in Keychain; pin ASSERTED in sendRequest/fetchSharedFieldValues; kernel verifyResponse;
payload sanity), `ApprovalCoordinator.swift` (push-driven single-flight owner inbox; zoneNotFound →
unregister). MODIFIED: CloudSyncService/SyncCoordinator adopt the helper (review-verified
semantics-identical), AppEnvironment wiring + erase clears approval device-local state,
ApprovalConfig record types + ms TTLs, Localizable.xcstrings push keys. 161/161 tests; iOS+macOS green.

**Review applied** (`plans/reports/from-code-reviewer-260705-phase3-ckshare-transport-report.md`):
H1 delta-cursor-as-state-query bug fixed at all 4 sites (stateless nil-cursor mode in ZoneDeltaFetch);
H2 escrow zone now created idempotently; M1 `partialFailure` unwrapped in nonce store + escrow collision;
M3 pre-pin grant can no longer send requests or decrypt.

**Decision (M2, recorded):** owner alert subscription fires on ALL participant zone writes → one false
"approval request" alert when B publishes its profile at accept time. ACCEPTED for V1 (UX noise, not
security — alert copy is static, tapping shows an empty inbox; a CKQuerySubscription filtered to
ApprovalRequest creation is the Phase-8 improvement, needs on-device verification first).

**Carried forward:** → Phase 5/6: call `refreshOwnerRequests()` on foreground/unlock; wire
`SharedZoneSubscriptionService.ensureSubscribedIfNeeded(settings:)` into the recipient accept flow
(currently DEBUG-spike-only); `changedZoneIDs` (DB-token) unwired until multi-zone recipient UX needs
it. → Phase 7: GC consumed/expired nonce records; full approval-artifact teardown on erase/revoke.
→ Phase 8: on-device verify of the `modifyRecords` collision error shape (nonce H4) during 2-account QA;
CKQuerySubscription experiment (M2).

**Open (unchanged from P2):** multi-device-owner grant-signing key distribution (V1 assumes the owner
approves on the device that created the grant; kernel API already takes a key set).
