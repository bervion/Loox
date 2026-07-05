# Code Review — Phase 3: CKShare Transport & Control-Plane Sync

Scope: ZoneDeltaSyncHelper.swift (NEW), CloudSyncService.swift, SyncCoordinator.swift (refactor), Services/Sharing/* (NEW), AppEnvironment.swift, ApprovalConfig.swift, Localizable.xcstrings, AppPushKind/AppPushDelegate. ~1,100 LOC net. Compile green (iOS+macOS), 161/161 tests pass.

## Overall Assessment

Transport layer is well-architected: signatures gate everything B can tamper with, opaque naming holds, ADR-2 governance is clean, and the sync-helper extraction is genuinely behavior-identical. **One high-severity functional bug (delta cursor misused as state query) breaks the owner inbox and recipient reads; one high ADR-2 violation (escrow zone never created without vault sync).** Both are contained to the new sharing layer — the vault sync path regresses nothing.

## Critical / High

### H1 — Persisted delta cursors misused for "current state" queries (confirmed; the flagged bug is real)
`ZoneDeltaFetch.pull` is a **delta** primitive: records consumed by a cursor never reappear. Four call sites use persisted cursors where "all records currently in the zone" is required:

- `ApprovalShareService.fetchLiveRequests` (ApprovalShareService.swift:165-174) — doc says "full refetch keeps this stateless" but cursor `approval_owner_scan_<zone>` persists in UserDefaults. Consequences:
  - `ApprovalCoordinator.refreshOwnerRequests` **replaces** `pendingOwnerRequests` with the fetch result (ApprovalCoordinator.swift:76). Any refresh with no new changes (foreground/unlock, second push) returns `[]` → **live unanswered requests vanish from the inbox**.
  - App restart: in-memory inbox empty + cursor persisted → pending requests are **permanently invisible**. Directly contradicts "the inbox is the source of truth" (ApprovalCoordinator.swift:51-52).
- `ApprovalRecipientService.fetchSharedFieldValues` (:91-93, cursor `approval_recipient_fields_`) — second call returns `{}`; shared field values disappear on re-open.
- `ApprovalRecipientService.fetchResponse` (:143-145, cursor `approval_recipient_resp_`) — (a) two concurrent pending requests: R1's poll **consumes R2's response record** through the cursor; R2's poll never sees it → request permanently unanswerable within `responseTTLMs`. (b) verify-throws-then-retry: response already consumed → gone.
- `ApprovalShareService.recordIDs(ofType:)` GC (:208-215, cursor `approval_owner_gc_`) — works incrementally by accident, but if a `publishGrant` fails after the scan advanced the cursor, those stale blobs are never GC'd (leak only, sealed + grant-id-mismatched — not a security issue).

**Fix:** make the cursor optional in `ZoneDeltaFetch.pull` — `nil` = full refetch from `since: nil`, nothing persisted. Use stateless mode for all four sites (zones are tiny; this matches the comments' stated intent). Keep persisted cursors only where delta semantics are wanted (vault pull).

### H2 — `ParticipantEscrowService` never creates the "Vault" zone → breaks ADR-2 "approval without vault sync"
ParticipantEscrowService.swift:55 saves into zone `Vault` of B's private DB, but that zone is only created by `CloudSyncService.sync()` (gated on `iCloudSyncEnabled`, CloudSyncService.swift:47,54) — the `VaultKeyEscrowService` precedent runs *after* a successful sync so the zone exists there. A recipient with vault sync OFF (the exact ADR-2 scenario) gets `zoneNotFound` on first identity creation; `fetchEscrowEnvelope`'s `try?` (:77) silently swallows the same error, so the flow reaches the doomed save. **Fix:** `modifyRecordZones(saving: [zone])` before the create (idempotent), mirroring `CloudSyncService.sync`.

## Medium

### M1 — `modifyRecords` batch error shape: top-level `.partialFailure` not unwrapped
- `CloudKitNonceStore.consume` (ApprovalShareService.swift:232-246) handles per-record `serverRecordChanged` in `saveResults` and a top-level `serverRecordChanged` throw. If the async API instead throws top-level `.partialFailure` (documented shape for atomic-zone batches; single-record ops are sometimes promoted, sometimes not), a genuine replay classifies as `nonceAuthorityUnavailable` instead of `replayedNonce`. **Fail-closed either way — H4 security holds** — but diagnosis/UX differ, and the plan's device-QA criterion ("replayed request on 2nd owner device collides", phase-03 line 74) is still unchecked.
- Same gap in `ParticipantEscrowService.ensureIdentity` (:60-68) is worse: the 2-device race's losing device throws instead of adopting the winner's identity (recoverable on retry via the cloud-copy fast path, but a needless user-facing error at the exact moment the race happens).
- **Fix (both):** on catch, unwrap `CKError.partialFailure` → inspect `partialErrorsByItemID` for `serverRecordChanged` before rethrowing.

### M2 — Owner alert subscription fires on ALL zone writes, not just requests
`CKRecordZoneSubscription` (ApprovalShareService.swift:82-92) cannot filter by record type. Concretely:
- B accepting the share and publishing the **participant profile** triggers "Someone is asking for a verification code" on the owner's device — a false security alert before any request exists.
- Owner's own writes (grant publish, response, **nonce marker created during verify**) alert the owner's *other* devices (CloudKit only suppresses the originating device).
False alarms in a security-approval feature erode exactly the trust the alert is for. Options: `CKQuerySubscription(recordType: ApprovalRequest, firesOn: .firesOnRecordCreation)` (needs the record type queryable — weigh against the no-console-index stance that motivated the delta-pull design), or client-side triage (silent push + local notification only when `fetchLiveRequests` actually yields a new request). Flag for lead decision before Phase 5.

### M3 — Pre-pin grant "display only" is convention-enforced, not API-enforced
`fetchGrant` returns a fully-usable `AccessGrant` pre-pin (`verifyGrant` with nil pin = self-signature only, ApprovalRecipientService.swift:72-84). Neither `sendRequest` (:117) nor `fetchSharedFieldValues` (:88) checks the pin — a Phase-5/6 caller can decrypt shared blobs / send requests against an unpinned (potentially swapped) grant. `fetchResponse` does gate (:139-141), which caps the blast radius, but decrypting shared-field values from a swapped grant would display attacker-chosen "shared" values as if from the owner. **Fix:** return an `UnverifiedGrant` wrapper pre-pin, or assert pin presence in `sendRequest`/`fetchSharedFieldValues`.

## Low / Informational

- **L1** `verifyInbound` passes `currentEpoch: grant.epoch` from the same fresh fetch (ApprovalShareService.swift:186-187) — the kernel's epoch check (ApprovalVerifier.swift:91) is tautological here. Revocation is actually enforced by grant-id rotation + fresh fetch (step 1 `grantMismatch`), so no vulnerability; document, or track a local epoch when multi-device owner signing lands.
- **L2** `ZoneDeltaFetch.changedZoneIDs` has zero callers — plan step 7's DB-token level isn't wired (recipient uses `allRecordZones`). Dead code or Phase-5 placeholder; either wire it or drop it.
- **L3** Approval cursor keys (`approval_owner_scan_/gc_`, `approval_recipient_*`) are never removed on `unregisterZone`/revoke → UserDefaults litter. (Moot if H1's stateless fix lands.)
- **L4** Nonce marker records carry `expiresAtMs` but nothing GC's them — unbounded (tiny) growth per zone.
- **L5** `AppEnvironment.eraseEverything` (AppEnvironment.swift:66-74) clears no approval state: `ParticipantEscrowService.clearLocalCache()` (currently caller-less), pinned owner keys, `approval_owner_zone_names`, `SharedZoneSubscriptionService.clearLocalFlag()`. The stale keychain envelope fails gracefully post-erase (unsealable → falls through to create), but teardown must land by Phase 5/6.
- **L6** `ApprovalCoordinator.refreshOwnerRequests` doc claims "also called on foreground/unlock" — no such caller exists yet; only the push observer triggers it. Note for Phase 5 wiring (a missed push currently DOES strand a request until the next push).
- **L7** `SharedZoneSubscriptionService.ensureSubscribedIfNeeded` has no production caller (DEBUG spike only) — recipient push pipeline unwired, expected Phase 5/6.
- **L8** `createShare` dedupe keys off `lookupInfo?.emailAddress` (ApprovalShareService.swift:64-66); for an already-accepted participant CloudKit may not populate it → duplicate `addParticipant` attempt. Add to device QA.
- **L9** `pendingOwnerRequests` exposes unverified request contents (fieldId/itemId) to the UI pre-`verifyInbound` — fine as designed (ids are opaque; ceremony verifies), noting for Phase-5 reviewers.

## Deviation Assessment: escrow FIRST-writer-wins (vs plan "last-writer by signed timestamp")

**Deviation justified — implementation is superior.** Plan phase-03 line 81 (Risk Assessment, planner-authored mitigation — not a user-confirmed decision) suggested last-writer election. Last-writer would let B's second device silently replace an identity the owner may already have pinned into a signed grant → orphaned sealed blobs + a key-substitution surface. Create-if-not-exists first-writer (ParticipantEscrowService.swift:54-67) makes the pinned key immutable by construction, and the loser adopts the winner. Lead should update the plan text to record the deviation.

## Critical-Check Results (per task)

| Check | Verdict |
|---|---|
| (a) `pull()` refactor regression | **Clean.** Same UserDefaults key/archive, same token-init/reset-once/per-page persist, same type dispatch + default-break, deletions ignored. Diff-verified byte-for-byte semantics. `SyncCoordinator` divergence (escrow block now runs after a coalesced call) is **benign**: `status` is `.syncing` synchronously before the first suspension inside `sync()` (CloudSyncService.swift:52), so the `.success` guard fails during flight; residual paths hit fingerprint/flag no-op guards. |
| (b) Nonce-store atomicity | Create-if-not-exists via `.ifServerRecordUnchanged` on a tagless new record **does** collide as `serverRecordChanged` — correct CloudKit pattern. Per-record failure handled. Gap: top-level `.partialFailure` shape (M1) — fail-closed regardless, security holds. |
| (c) Cursor reuse | **Confirmed real bug** — H1, highest-priority fix. |
| (d) Trust model | Pre-pin misuse possible (M3). `publishProfile` under `.readWrite` zone-wide share: valid (participants can write; profile trust anchored by fingerprint ceremony + grant pinning, not the record). Grant singleton + `.allKeys`: safe — B tampering fails owner-signature verify; grant-id rotation makes stale requests `grantMismatch`. B deleting nonce markers ≈ self-DoS only (each approval still needs the owner ceremony). |
| (e) ADR-2 | **Verified.** No VaultItem uploads anywhere in Services/Sharing; grep confirms zero `iCloudSyncEnabled` gates in approval paths; push routing explicitly bypasses the sync observer (AppPushKind.swift:5-8). One violation in spirit: H2 (escrow depends on a zone only vault sync creates). |
| (f) Escrow zone | Unknown types ignored by vault pull ✓ (default-break, CloudSyncService.swift:143). Error-shape handling ok for per-record + promoted top-level; `.partialFailure` gap (M1). Zone-existence bug (H2). |
| (g) Isolation | Clean. All services `@MainActor`; `CloudKitNonceStore`/`ApprovalRecordMapping`/`AppPushKind` `nonisolated` + Sendable-safe; containers lazy — `AppEnvironment.init` touches no CloudKit ✓. |
| (h) iOS 17.6 floor | All clear — `recordZoneChanges/databaseChanges(since:)`, `allRecordZones`, `CKRecordNameZoneWideShare`, `shareParticipant(forEmailAddress:)`, `container.accept` are iOS 15+. `CKSharingSupported` added to Info.plist ✓ (Project.swift:82). |
| Localization | `approval.push.title/body` present EN+VI, JSON valid (634 keys); "Loox" is the current brand (Project.swift:43), not a typo. |

## Recommended Actions (priority order)
1. **H1** — add stateless (nil-cursor) mode to `ZoneDeltaFetch.pull`; adopt in `fetchLiveRequests`, `fetchSharedFieldValues`, `fetchResponse`, `recordIDs(ofType:)`.
2. **H2** — create the `Vault` zone in `ParticipantEscrowService.ensureIdentity` before the escrow save.
3. **M1** — unwrap `.partialFailure` → `partialErrorsByItemID` in both create-if-not-exists sites.
4. **M2** — lead decision: query-subscription vs client-side alert triage, before Phase 5 UI.
5. **M3** — `UnverifiedGrant` wrapper or pin assertions in `sendRequest`/`fetchSharedFieldValues`.
6. Track L5/L6/L7 as explicit Phase-5/6 todo items so wiring isn't forgotten.

## Positive Observations
- Signed-canonical-bytes-as-single-blob transport (ApprovalRecordMapping) eliminates the entire re-serialization/signature-mismatch bug class.
- `ZoneDeltaFetch` extraction is a faithful, well-documented refactor; H7 goal (no fork of the delta loop) achieved.
- Push routing fail-safe: unknown subscription ids default to the idempotent sync pull, never an approval route (AppPushKind.swift:25-28).
- Transactional escrow (publish-before-use) and first-writer-wins are the right crash-safety and pinning calls.
- `ApprovalPrerequisites` fail-closed gates (live account check + notification auth) are exactly right for ADR-5.

## Unresolved Questions
1. M2 alert-noise strategy: is a queryable `ApprovalRequest` index acceptable given the no-console-index stance, or should Phase 5 do silent push + local-notification triage?
2. Empirical shape of async `modifyRecords` errors for a 1-record atomic collision (promoted `serverRecordChanged` vs `.partialFailure`) — resolve during the planned 2-device nonce QA (phase-03 criterion line 74).
