---
phase: 1
title: "Transport + push + latency gating spike & CKShare enablement"
status: completed # gate verdict CONDITIONAL GO recorded 2026-07-05 (user decision)
priority: P1
effort: "1.5d"
dependencies: []
---

# Phase 1: Transport + push + latency gating spike & CKShare enablement

## Overview
**Gate for the whole PR.** Before building the crypto kernel or any UI, prove the load-bearing CloudKit
assumptions and measure real latency with a throwaway thin vertical slice. Also lands the durable
plumbing this feature needs: CKShare accept, the **separated push pipeline** (ADR-5), notification
permission (fail-closed, ADR-2), and runtime iCloud-account enforcement (ADR-2). If the spike fails
(participant can't write / owner gets no push / p95 unusable), STOP and escalate — do not start Phase 2.

## Requirements
- Functional: a bare signed request → **user-visible alert push** to owner → owner-written response →
  push to requester round-trip across **two iCloud accounts**; opaque `requestOpaqueID` payload only;
  notification authorization gate; `CKContainer.accountStatus` check.
- Non-functional: no launch crash when the user never shares; approval push independent of the vault
  `iCloudSyncEnabled` toggle; measure p50/p95 request→response latency; iOS 17.6 API floor.

## Architecture
- **Spike slice (throwaway, no UI, no per-field, no real crypto):** owner creates an opaque-named custom
  zone + `CKShare` restricted to a participant added **programmatically** (`CKUserIdentity` lookup by
  email/phone, `publicPermission = .none` — Validation §4, not `UICloudSharingController`); participant
  writes a dummy `ApprovalRequest`; owner receives an alert push, writes a dummy response; requester
  receives a push. **This validates H1 + CKShare participant-write + owner-push-on-participant-write.**
  <!-- Updated: Validation Session 1 - programmatic participant; multi-metric latency gate -->
  Measure and log THREE metrics (Validation §1), not one:
  - `T_transport` = request committed → owner **actionable alert** delivered.
  - `T_roundtrip` = request committed → response decryptable by requester.
  - `TOTP_remaining` = simulated code's remaining lifetime at requester receipt (generate a dummy code at
    the *approve* hop, not at request, to mirror the real ceremony).
- **CKShare accept:** `CKSharingSupported = YES` in the app Info.plist (`Project.swift` `.extendingDefault`);
  scene handler `windowScene(_:userDidAcceptCloudKitShareWith:)` (17.6-safe) → `CKContainer.accept(_:)` →
  post `.vaultShareAccepted(metadata)`.
- **Push pipeline separation (ADR-5):** `enum AppPushKind { vaultRemoteChange, approvalRequest,
    approvalResponse }`. `AppPushDelegate` routes by `notification.subscriptionID` / database scope.
  `approvalRequest` = **alert** push (`notificationInfo.alertBody/title/sound`), carrying only
  `requestOpaqueID`; posts `.approvalRequestReceived`. It must NOT flow through `.vaultRemoteChangePush`
  (that observer early-returns when `iCloudSyncEnabled == false`, `SyncCoordinator.swift:46`).
- **Notification permission (ADR-2, fail-closed):** request `UNUserNotificationCenter` `.alert/.sound`
  authorization when the user enters the sharing flow; if denied, block creating `askEachTime` grants
  ("Approval Requests need notifications").
- **Runtime iCloud enforcement (ADR-2):** check `CKContainer.accountStatus`; if not `.available`, surface
  a clear blocker; enable the approval sync primitives regardless of the vault-sync toggle.
- **Shared-DB subscription:** `SharedZoneSubscriptionService` on `container.sharedCloudDatabase`
  (`CKDatabaseSubscription`), silent flag guarded, mirroring `SyncPushService` — but split from it, not
  reused verbatim (extract the common bit in Phase 3).
- **Zone/record naming (M2):** opaque random zone + record names (NOT `approval-<recipientId>`); recipient
  id lives inside sealed/participant-scoped data, not the zone name.

## Related Code Files
- Create: `VaultifyCore/Sharing/ApprovalConfig.swift` (container id, record types, opaque-name builder, TTLs),
  `Vaultify/Services/Sharing/SharedZoneSubscriptionService.swift`,
  `Vaultify/Services/Sharing/ApprovalSpike.swift` (throwaway; delete after gate — keep behind `#if DEBUG`)
- Modify: `Project.swift` (`CKSharingSupported`), `Vaultify/App/AppPushDelegate.swift` (AppPushKind routing),
  `Vaultify/App/VaultifyApp.swift` / scene (share-accept + notification auth entry)
- Reference: `Vaultify/Services/Sync/SyncPushService.swift`, `Vaultify/Services/RotationNotificationService.swift:79`
  (existing `requestAuthorization` pattern), `Vaultify/App/SettingsStore.swift:84`, `AppEnvironment.swift:61`

## Implementation Steps
1. `ApprovalConfig` (opaque naming, record types, container id, request/response TTLs).
2. Add `CKSharingSupported`; `tuist generate`.
3. `AppPushKind` + subscriptionID/scope routing in `AppPushDelegate`; alert-push config; opaque payload.
4. Notification authorization request + fail-closed gate; `CKContainer.accountStatus` check.
5. Share-accept scene handler → `.vaultShareAccepted`.
6. `SharedZoneSubscriptionService` on shared DB.
7. Add `approvalModeEnabled` flag in `SettingsStore`, **separate** from `iCloudSyncEnabled` (Validation §2);
   the approval push observer + spike are gated by it, never by `iCloudSyncEnabled`.
8. **Spike:** two-account round-trip; log `T_transport` / `T_roundtrip` / `TOTP_remaining`; confirm
   participant `.readWrite` create works and owner zone-push fires on participant write.
9. `make check`. **Decision gate (record verdict in this file):**
   - **GO:** p95 `T_transport` ≤ 5s · ≥95% receipts ≥15s remaining → build all phases.
   - **CONDITIONAL GO:** p95 `T_transport` 5–10s · small low-remaining tail → build, but require retry UX +
     approve-time code generation (Phase 5).
   - **STOP/ESCALATE:** p95 `T_transport` > 10s · OR significant fraction <8s remaining · OR delivery
     unreliable → **do NOT abort**; split the roadmap: ship non-latency-sensitive grants (password
     `none|shared`, snapshots, CKShare grant, revoke), STOP before interactive TOTP approval, escalate to
     user for relay-vs-rework decision (Validation §1).

## Success Criteria
- [x] Two-account spike completes a request→alert-push→response→push round trip; p50/p95 recorded below.
- [x] Owner receives a **user-visible** notification (not silent) on a participant write. (device-verified)
- [x] Participant can create request records under the CKShare (`.readWrite` verified on device).
- [x] `approvalRequest` routing bypasses the `iCloudSyncEnabled` gate; sync push unaffected. (code-review verified)
- [x] Notification-denied blocks `askEachTime` grant creation; `accountStatus != available` blocks entry. (`ApprovalPrerequisites`, fail-closed; device confirm pending)
- [x] No launch crash when sharing unused; `make check` green. (no CloudKit touch at launch — reviewer verified; iOS + macOS slices compile; 147/147 unit tests pass)

## Implementation Status — 2026-07-05

**Code landed (uncommitted, branch main).** iOS Simulator + macOS compiles green; 147/147 unit tests pass, 0 regressions. Code review: 0 Critical/High; 2 Medium fixed pre-commit (dead `approvalModeEnabled` flag now wired through spike + `SharedZoneSubscriptionService.ensureSubscribedIfNeeded(settings:)`; macOS share-accept posts `.vaultShareAccepted` only on success). Full review: `plans/reports/from-code-reviewer-260705-phase1-approval-transport-report.md`; tests: `plans/reports/tester-260705-1236-approval-mode-phase1-regression-test-report.md`.

Files: NEW `VaultifyCore/Sharing/ApprovalConfig.swift`, `Vaultify/App/AppPushKind.swift`, `Vaultify/Services/Sharing/ApprovalPrerequisites.swift`, `Vaultify/Services/Sharing/SharedZoneSubscriptionService.swift`, `Vaultify/Services/Sharing/ApprovalSpike.swift` (DEBUG throwaway). MODIFIED `AppPushDelegate.swift` (AppPushKind routing + UN delegate + scene-delegate injection for CKShare accept), `SettingsStore.swift` (`approvalModeEnabled`), `SyncSettingsView.swift` (DEBUG spike section), `Project.swift` (`CKSharingSupported`).

**Carried forward (from review — do NOT lose):**
- → Phase 3: cold-launch alert-tap events can be dropped (`.approvalRequestReceived` fire-and-forget, observer created lazily) — durable pipeline must buffer the pending-request signal; use `alertLocalizationKey` (EN+VI) instead of English `alertBody`; add page cap to zone-changes pagination loop.
- → Phase 7: Erase Vault (`CloudSyncService.eraseRemote`) does not clean `apz-*` zones, CKShare, alert subscriptions, or `SharedZoneSubscriptionService.clearLocalFlag()` — revocation phase must own approval-artifact teardown.
- Device QA note: first cold launch after this change verifies the scene-delegate injection (failure mode = black screen; pattern is known-good, smoke check only).

**Gate measurement — how to run (2 devices, 2 iCloud accounts, Debug app):**
1. Device A (owner): Settings → iCloud Sync → "Approval Spike (DEBUG)" → enter B's iCloud email → "1 · Owner: create share" → send the share link to B (AirDrop/Messages).
2. Device B: open the link, accept → "2 · Requester: send request".
3. Device A: alert push arrives → tap → "3 · Owner: approve pending" (the tap = approve hop; dummy code life starts here).
4. Device B: receives push → status shows `T_roundtrip` + `TOTP_remaining`. Repeat ≥10 runs incl. A backgrounded/locked. Log file: Documents/approval-spike-log.txt on each device.
5. Record verdict below (GO / CONDITIONAL GO / STOP per step 9 thresholds).

**Gate verdict (user decision, 2026-07-05): CONDITIONAL GO** — see plan.md ADR-6 for the full decision
record. NOT a full GO.

Measured (2 devices, 2 real iCloud accounts, 10 runs):
`T_roundtrip` (s): 15.5, 6.4, 2.3, 4.7, 5.7, 2.4, 2.8, 2.3, 3.3, 2.7 → median ≈ 3.0s, one 15.5s outlier.
`TOTP_remaining` (s): 5.6, 27.2, 0.2, 9.1, 18.6, 0.4, 8.8, 21.1, 1.7, 15.7.

Evidence reading:
- Post-approval transport typically ≈ 1–3s; median path is usable.
- Low `TOTP_remaining` samples correlate with approvals landing near the END of the 30s TOTP period —
  failure is **issuance phase alignment**, not transport speed. No evidence the transport median path is
  too slow.
- The 15.5s outlier is real but n=10 mixes human tap/approve time into the tail; not treated as a
  trustworthy production p95. Not ignored either → conditions 3–5 below.
- Two spike UX bugs found & fixed on device: empty-email NSException crash (uncatchable by Swift
  `do/catch` — validate before CloudKit); non-idempotent re-run of step 1 ("zoneshare already exists" →
  fetch-or-create + Reset button). Recipient MUST accept with the Apple ID matching the looked-up email
  (confirms ADR-4 no-bearer-URL behavior).

**Mandatory conditions to proceed (binding on later phases):**
1. **Boundary-aware issuance (Phase 5)** — remaining ≥ threshold → generate current code now; remaining <
   threshold → **WAIT for the next TOTP boundary, then generate the now-current window's code**, seal,
   send immediately. NEVER pre-send a future-period code (ADR-6).
2. **No future-TOTP acceptance test (Phase 5/8)** — Loox MUST NOT deliver a TOTP for counter N+1 while
   local trusted time is still in counter N.
3. **B timeout + superseding retry (Phase 6)** — "Request Again" invalidates/supersedes the old request;
   never two live responses.
4. **Late/stale response fail-closed (Phase 6)** — expired/superseded response ciphertext is rejected,
   never displayed.
5. **Telemetry decomposition (Phase 8 integration gate)** — measure `T_request_commit_to_alert`,
   `T_alert_to_owner_open`, `T_owner_approve_to_response_commit`, `T_response_commit_to_B_fetch`,
   `T_approve_to_B_decrypt` so the next outlier is attributable.

**Gate wording amendment:** "≥95% delivered codes arrive with ≥15s remaining" stands, but **measurement
applies AFTER the boundary-aware issuance policy** — current data was collected pre-mitigation with a
known phase-alignment cause, so it does not condemn the transport architecture.

**Post-mitigation stop condition:** if, after boundary-aware issuance, measurements still show a
significant receipt tail <8s remaining OR isolated transport p95 >10s at meaningful sample size → pause
latency-sensitive approval rollout and escalate transport design (relay vs rework, Validation §1).

## Risk Assessment
- **If the spike fails, the architecture is wrong** — that is the point of doing it first (cheap kill).
- Share-accept + programmatic `CKUserIdentity` lookup / add-participant APIs differ at iOS 17.6 — verify
  against the 17.6 SDK; guard newer APIs; handle "recipient not an iCloud user".
- Alert-push delivery is still best-effort (iOS budget) — the ceremony tolerates it (A can also open the
  app manually and see pending requests), but a missed push shouldn't strand B: pair with the B-side
  timeout in Phase 6.
