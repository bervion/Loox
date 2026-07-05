---
title: "Approval Mode Sharing — capability delegation via CKShare"
description: "Owner shares per-field capability (none/shared/askEachTime) with another Loox user via CKShare; secrets never leave owner vault. Foreground approval ceremony (notification → open app → Face ID → unlock → generate → seal one ephemeral code). TOTP + password in scope, passkey OUT, no sessions. Full cross-user build, 1 PR."
status: in-progress
priority: P2
branch: "main"
tags: [sharing, cloudkit, ckshare, crypto, approval, hpke]
blockedBy: []
blocks: []
created: "2026-07-05T04:41:47.878Z"
createdBy: "ck:plan"
source: skill
---

# Approval Mode Sharing — capability delegation via CKShare

## Overview

**Goal:** owner A shares *capability* (not secrets) for a vault item to another Loox user B.
A configures per-field before sharing: each field `none` / `shared` (B sees value directly) /
`askEachTime` (B must request; A approves per-use). Model: **Grant → Request → Approve → Ephemeral
capability** ("share access, not secrets"). Secret seed/password never leaves A's sealed vault.

**Approval is a foreground user-presence ceremony (see ADR-1), not a background secret service.**
B's request produces a *user-visible* notification on A; A taps it, Loox opens to the verified
request, A satisfies Face ID / passcode which unlocks the vault, the current one-time code is
generated **in foreground**, sealed to B, and delivered. No background/locked path can derive or
issue a secret. No auto-approve, no approval sessions in V1.

**Transport:** CloudKit **CKShare** on a per-recipient custom zone (serverless, Apple-only). A owns
the zone; B is added as a **looked-up participant** (not a bearer URL) and sees the zone in shared DB.
Control-plane messages are device-signed with **pinned** device keys; `askEachTime` responses are
HPKE-sealed to B's **per-request ephemeral** key (forward secrecy). Static `shared` field blobs are
sealed to B's **persistent participant** key (two different keys — see ADR-3).

**Source of truth:** `plans/reports/brainstorm-260705-1137-approval-mode-sharing-report.md` +
Red Team Review (below, applied 2026-07-05).

**User-locked decisions (do NOT reverse):**
1. Full cross-user build in **1 PR** (phases are internal, one branch).
2. **Per-field share config** by owner before sharing. Modes: TOTP → `none`/`askEachTime`;
   password/username/url/text → `none`/`shared`. **`askEachTime` is TOTP-only** (password ask-each-time
   is low value + was an open question → resolved: not in V1).
3. **iCloud mandatory** for the feature (Apple-only, both parties on iCloud) — feature must actively
   check account + enable the required sync primitives (see ADR-2), not assume them.
4. Scope: **TOTP + password/username**. **Passkey-approval OUT** (R&D — extension lifecycle risk).
5. **Foreground approval ceremony only** (ADR-1). No background TOTP generation, no auto-approve, no
   approval sessions, no notification-action button that returns a secret directly.
6. **B's participant key is escrowed under B's own Vault Key** and synced like the Vault-Key envelope
   (ADR-2); multi-device B works. Trust is anchored by participant lookup + pinned device signing keys
   + a one-time out-of-band fingerprint (ADR-4).

**Codebase reuse (honest scope — mostly *pattern* reuse, NOT drop-in):**
- HPKE `Curve25519_SHA256_ChachaPoly` **technique** (ciphersuite + `info`-binding) →
  `VaultifyCore/Crypto/VaultKeyPairing.swift`, `PasskeyEnvelope.swift`. Both hard-code their `info` /
  payload length → `ApprovalSeal` is **new code** modeled on them, not a reused function.
- `P256.Signing` **type** is used in `WebAuthn.swift`, but it has **no verify path, no persistence, no
  key distribution** → the control-plane device signing identity (persist in Keychain, verify, publish,
  pin) is **net-new**. Genuine reuse: `VaultifyCore/Keychain/KeychainStore.swift`.
- Vault-Key escrow/pairing pattern → `VaultKeyEscrowService.swift`, `VaultKeyPairing.swift` (the model
  for B's participant-key escrow).
- CloudKit change-token delta fetch + single-flight + subscription → extract a shared helper from
  `CloudSyncService.swift` / `SyncCoordinator.swift` / `SyncPushService.swift` (DRY — do not fork).
- Per-field model → `VaultItem.fields: [DynamicField]`; **`DynamicField.id` is a mutable `var UUID()`**
  (`DynamicField.swift:11,21`) → capability keying must guarantee id stability + fail-closed on unknown id.
- TOTP → `VaultifyCore/TOTPGenerator.code(forStoredValue:date:)`.

**iCloud state (corrected after red-team):** iCloud is enabled **at build level only** — entitlements +
`VAULTIFY_ICLOUD` + provisioned container are present (`Project.swift:128`, `Vaultify.entitlements`).
But **runtime sync is opt-in OFF by default**: `SettingsStore.iCloudSyncEnabled` defaults `false`
(`SettingsStore.swift:84`, `AppEnvironment.swift:61`) and `CloudSyncService` early-returns when off
(`:48`). The feature must therefore **check `CKContainer.accountStatus` and enable the approval sync
primitives independently of the vault-sync toggle** (ADR-2). Phase 1 is NOT "plumbing only."

**Top risk — latency, and it CANNOT be fully closed for a 30s OTP.** `validUntil` only tells B when to
stop displaying; the relying party judges the code by *its own* clock, so latency + A↔B clock skew can
make a "valid-looking" code fail at the website. The foreground ceremony (ADR-1) means the round trip
is: request → alert push → A taps → app foreground → Face ID/unlock → generate → seal → response push →
B. Mitigation is honesty + a **front-loaded gating spike** (Phase 1) that measures real p50/p95 across
two accounts and proves the CKShare permission model **before** the crypto kernel and UI are built. If
p95 is unusable, escalate before Phases 4–8 (a relay is out of scope for this PR).

## Architecture Decision Records

**ADR-1 — TOTP approval requires foreground owner presence.**
Loox will not generate or release TOTP codes while the owner app is backgrounded or the vault is
locked. Approval requests use user-visible notifications. The owner must open Loox, authenticate with
Face ID/passcode, unlock the vault, review the verified request, and explicitly approve.
*Rationale:* preserves the vault lock + key-zeroisation guarantees (`RootView.swift:82` locks on
background, `VaultSession.swift:23` zeroises the key); keeps the TOTP seed exclusively inside the owner
vault; avoids background secret derivation; makes approval semantics explicit and auditable.
*Non-goals V1:* background auto-approval · approval sessions · silent TOTP issuance · sharing TOTP seeds
· notification-action buttons that return a secret. *(A separate future "Share TOTP Secret" capability —
explicitly warned as permanent possession — is the ONLY place seed-sharing may live; it must never
masquerade as Approval Mode.)*

**ADR-2 — iCloud is a runtime prerequisite; Approval Mode is a capability INDEPENDENT of vault-item sync.**
Two separate flags + two separate runtime services (Validation §1):
`vaultItemSyncEnabled` → `CloudSyncService` (uploads VaultItem records); `approvalModeEnabled` →
`ApprovalSyncService` (identity escrow, grants, requests, responses, revocation/nonce state). **Enabling
Approval Mode must NOT imply vault-item sync**, and the approval pipeline must NOT reuse the
`guard settings.iCloudSyncEnabled` gate. The **control plane must never pull the secret plane** — a user
with `vaultItemSyncEnabled=false` + `approvalModeEnabled=true` has zero VaultItem uploads yet full
approval function (TOTP seed stays local on A). The feature checks `CKContainer.accountStatus`.
Notification permission is a **fail-closed prerequisite**: no `askEachTime` grant until notifications
authorized. B's participant private key is **escrowed under B's own Vault Key** in a dedicated synced
record (modeled on `VaultKeyEscrowService`), so multi-device B works; it does NOT "ride vault-item sync".

**ADR-3 — Two recipient keys, two purposes.** `askEachTime` responses seal to B's **per-request
ephemeral** key (forward secrecy, `info = requestId+nonce`). Static `shared` field blobs seal to B's
**persistent participant** key. Phases 2/5/6 must consume this one contract (prior draft opened the
ephemeral-sealed response with the participant key — a bug).

**ADR-4 — Trust anchoring.** CKShare is restricted to a looked-up participant added **programmatically by
email/phone** (`CKUserIdentity` lookup, `publicPermission = .none`) — NOT `UICloudSharingController`, and
no bearer URL (Validation §4). B's device **signing** public keys are pinned in the owner-signed grant;
the verifier rejects any request signed by an unpinned key; enrolling a new B device requires A's
approval. A and B compare a short out-of-band **fingerprint** once, TOFU-pinned thereafter; a changed
owner key is rejected.

**ADR-5 — Push pipeline separation.** New `enum AppPushKind { vaultRemoteChange, approvalRequest,
approvalResponse }` routed by CloudKit `subscriptionID` / database scope. `approvalRequest` is a
**user-visible alert push** carrying only an opaque `requestOpaqueID` (no item title, account, service,
or code) and is **never** gated behind `iCloudSyncEnabled` (which currently drops it —
`SyncCoordinator.swift:46`). Sync stays a silent content-available push.

**ADR-6 — Phase 1 gate verdict: CONDITIONAL GO; boundary-aware TOTP issuance (user decision, 2026-07-05).**
*Verdict:* CONDITIONAL GO (not full GO).
*Evidence:* 10 observed roundtrips, median ≈ 3.0s; one 15.5s outlier; low remaining-lifetime samples
cluster around approvals made near the end of a 30s TOTP period; observed post-approval transport
typically ≈ 1–3s; sample does not isolate transport latency from human-interaction latency.
*Required mitigation:*
- Generate the TOTP only after owner approval (never on push arrival).
- If the current period has < `freshnessThreshold` remaining, **wait for the next period boundary, then
  generate the new current-period code** — never pre-send a future-period TOTP. A TOTP for counter N+1
  MUST NOT be delivered while local trusted time is still in counter N (acceptance test).
- `freshnessThreshold` is a **policy constant**, not a magic number:
  `estimatedDeliveryBudget (5s) + minimumRecipientUseBudget (10s) + clockSkewBudget (3s) = 18s` for V1
  (`TOTPIssuancePolicy { minimumRemainingLifetime = 18, responseTimeout = 20 }`).
- While waiting for the boundary the owner app must stay foreground with a valid vault session (ADR-1);
  do NOT read the seed until the boundary, do NOT cache the seed to survive backgrounding — if the app
  backgrounds mid-wait, ABORT issuance (B sees "approval interrupted — request again").
- Recipient timeout + superseding retry semantics ("Request Again" invalidates the old request); late or
  superseded responses are rejected fail-closed, never displayed.
- Continue latency instrumentation through integration testing (decomposed hop metrics, Phase 8).
*Stop condition:* if post-mitigation measurements still show a significant receipt tail <8s remaining, or
isolated transport p95 >10s at meaningful sample size → pause latency-sensitive approval rollout and
escalate transport design (Validation §1 options).

**ADR-7 — Security time invariant: Unix time only; clock skew, not timezone, is the threat (user, 2026-07-05).**
> All protocol expiration, nonce freshness, request lifetime, grant validity, and TOTP window
> calculations operate on **absolute Unix time**. Local time zones are **display-only**.
- Protocol timestamps (`createdAt`, `expiresAt`, `approvedAt`, `periodStart/End`…) encode as **Unix epoch
  milliseconds (`Int64`)** in models AND canonical bytes — never local wall-clock strings, never a
  timezone identifier in a security decision. UI converts to local time for display only.
- **Crypto kernel bans `Calendar.current` / `TimeZone.current` / `DateComponents`.** TOTP window math is
  integer Unix arithmetic: `counter = unixSeconds / period`, `remaining = period − unixSeconds % period`
  (RFC 6238 — timezone and DST cannot affect the moving factor; US↔VN is the same instant).
- `freshnessThreshold` semantics widened: it covers **delivery latency + recipient interaction + clock
  uncertainty + RP verification delay** — not just network (A remaining 18s − transport 3s − RP clock
  +8s fast could leave 7s at the RP).
- **Response payload carries full window context** (replaces bare `{code, validUntil}`):
  `TOTPApprovalPayload { code, counter: UInt64, period: UInt32, generatedAtUnixMs, periodStartUnixMs,
  periodEndUnixMs, requestNonce }` — enough for countdown, stale rejection, telemetry, malformed-response
  detection. B's countdown is **advisory** ("About Ns remaining"), never a validity promise; **B's clock
  never decides security validity — the RP server is the final authority.**
- **H8 (new red-team finding, user-found): time-source trust / clock skew unspecified.** V1 does NOT
  build an NTP service, but must: detect suspicious system-clock jumps; use the **monotonic clock** for
  internal durations/telemetry (wall clock can be adjusted mid-measurement); test ±5s/±10s/±20s skew;
  treat countdown as advisory.
- **Mandatory test:** mocked identical Unix instant with device timezones America/New_York ↔
  Asia/Ho_Chi_Minh and America/Los_Angeles ↔ Asia/Tokyo → same TOTP counter, same boundary, same
  remaining lifetime.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Transport + push + latency gating spike & CKShare enablement](./phase-01-icloud-ckshare-enablement.md) | ✅ Complete — CONDITIONAL GO (ADR-6, 2026-07-05) |
| 2 | [Control-plane crypto core + trust anchoring](./phase-02-control-plane-crypto-core.md) | ✅ Complete (2026-07-05, 161/161 tests, review applied) |
| 3 | [CKShare transport, participant escrow & control-plane sync](./phase-03-ckshare-transport-push.md) | ✅ Complete (2026-07-05; device QA rides Phase 8) |
| 4 | [Owner share-config UI](./phase-04-owner-share-config-ui.md) | ✅ Complete (2026-07-05; device QA rides Phase 8) |
| 5 | [Owner approval ceremony (foreground)](./phase-05-owner-approval-ux-sessions.md) | ✅ Complete (2026-07-05; ADR-6 device QA rides Phase 8) |
| 6 | [Recipient UX & request state machine](./phase-06-recipient-ux.md) | Pending |
| 7 | [Revocation & share management](./phase-07-revocation-share-management.md) | Pending |
| 8 | [Localization, DS compliance, integration gate & QA](./phase-08-localization-ds-compliance-qa.md) | Pending |

## Dependencies

**Soft overlap (no hard block):** `plans/260704-1751-ipad-mac-multiplatform-sidebar-menubar-sync`
also touches CloudKit. Keep Approval-Mode record types in a **separate custom zone** from the private
`Vault` zone; whichever ships first must not rename the shared container.

**Prereq facts:** iCloud entitlement + container provisioned; `VAULTIFY_ICLOUD` compiled. **NOT true at
runtime:** vault sync is opt-in-off by default — the feature must enable its own sync primitives (ADR-2).

## Global Success Criteria — TOTP approval ceremony
When B requests a TOTP capability:
- [ ] 1. A receives a **user-visible** approval notification (not a silent push).
- [ ] 2. Tapping it opens Loox in **foreground** to that exact request.
- [ ] 3. Loox **verifies request authenticity** (pinned signature, grant, participant, epoch, expiry,
       fresh nonce) *before* showing the approval UI.
- [ ] 4. A must satisfy user presence / **Face ID / passcode**.
- [ ] 5. The **vault must be unlocked** before any TOTP material is accessed.
- [ ] 6. The TOTP code is generated **only in foreground**.
- [ ] 7. Only the **current one-time code** is sealed to B (to the per-request ephemeral key).
- [ ] 8. The **TOTP seed never leaves** A's vault.
- [ ] 9. **No background path** can derive or issue a TOTP (verified — vault key absent when locked).

## Global Success Criteria — sharing & security
- [ ] A shares an item to B via a **looked-up participant** (no bearer URL); B accepts, sees it in B's
      vault marked "shared by A"; A & B confirmed a one-time fingerprint.
- [ ] `shared` fields render on B (and B **retains** them — revoke cannot claw back already-delivered
      values; UX states this); `askEachTime` (TOTP) shows "Request" only.
- [ ] B works on **multiple devices** (participant key escrowed under B's Vault Key).
- [ ] Notifications are a **fail-closed prerequisite**: no `askEachTime` grant without notification auth.
- [ ] A revokes B → B's further requests rejected (epoch bump, checked fresh on every approve); no TOTP
      seed reset; forged/unpinned requester, replayed nonce (authoritative across A's devices), stale
      epoch, expired request all rejected.
- [ ] CloudKit record **payloads** are ciphertext; residual metadata (item linkage, field kind, timing)
      is minimized (opaque zone/record names) and documented as an accepted side-channel.
- [ ] All new UI localized EN + VI; DS tokens only; `make check` compiles app + extension.
- [ ] Integration gate: signed records round-trip through real CKRecord encode/decode across two
      accounts (canonical bytes survive); version handshake present. DEBUG self-test proves crypto
      invariants (sign/verify/tamper, HPKE seal→open, replay, epoch).

## Red Team Review

### Session — 2026-07-05
**Findings:** 15 consolidated (from 26 raw across 4 hostile reviewers) — all evidence-backed, all Accept.
**Severity:** 4 Critical, 7 High, 4 Medium.
**User decisions:** C1 → foreground ceremony (ADR-1) + cut sessions; C2 → participant-key escrow under
B Vault Key (ADR-2); C4/C5 → participant lookup + pinned keys + OOB fingerprint (ADR-4); apply all.

| # | Finding | Sev | Disposition | Applied |
|---|---------|-----|-------------|---------|
| C1 | Vault locks + zeroises key on background; silent no-alert push → cannot notify/generate | Critical | Accept | ADR-1, ADR-5, P1, P5 |
| C2 | "Participant key rides vault sync" — no such mechanism; multi-device B split-brain | Critical | Accept | ADR-2, P2, P3 |
| C3 | "iCloud enabled" = compile flag only; runtime sync opt-in OFF | Critical | Accept | ADR-2, P1 |
| C4/C5 | No trust anchor for B's signing key / A's owner key; bearer URL MITM | Critical | Accept | ADR-4, P2, P3 |
| H1 | Core CKShare behavior unverified + latency measured last | High | Accept | P1 gating spike |
| H2 | `validUntil` can't close TOTP window; RP clock + skew | High | Accept | Top risk, P5, P6 |
| H3 | Contract mismatch: response sealed to ephemeral vs opened with participant key | High | Accept | ADR-3, P2/P5/P6 |
| H4 | Nonce store per-device; owner multi-device → replay/double-spend | High | Accept | P2 (authoritative nonce) |
| H5 | `shared` fields no forward secrecy; revoke can't claw back blobs | High | Accept | P6/P7 wording, success criteria |
| H6 | Push routing gated on `iCloudSyncEnabled` drops approval push | High | Accept | ADR-5, P1 |
| H7 | 4 Approval* services duplicate sync infra (DRY) | High | Accept | P3 (extract shared helper) |
| M1 | "Reuse HPKE/P256" overstated — net-new kernel | Medium | Accept | reuse section, P2 effort |
| M2 | CloudKit metadata leak; "only ciphertext" false | Medium | Accept | success criteria, P1/P3 opaque names |
| M3 | `DynamicField.id` mutable → capability orphaned on edit | Medium | Accept | P2/P4 (id stability + fail-closed) |
| M4 | YAGNI: cut sessions, collapse P2 files, trim P7, add integration gate | Medium | Accept | P2/P5/P7/P8 |
| H8 | Time-source trust / clock-skew policy unspecified (timezone harmless — skew is the real risk; user-found during gate session 2026-07-05) | High | Accept | ADR-7, P2/P5/P6/P8 |

### Whole-Plan Consistency Sweep
Applied across all phase files 2026-07-05: removed "Approval Session / auto-issue" (P5 title + body),
"silent push for approval" (→ alert push, ADR-5), "participant key rides vault sync" (→ escrow, ADR-2),
"reuse HPKE/P256 as drop-in" (→ net-new), single-device nonce (→ authoritative), response-open key
(→ ephemeral per ADR-3). Phase 1 reframed from "plumbing only" to gating spike. No residual
contradictions; `askEachTime` constrained to TOTP-only across P2/P4/P6.

## Validation Log

### Session 1 — 2026-07-05
Verification pass skipped (Red Team Review above already carries codebase evidence). 4 decisions:

**§1 — Latency gate policy (Phase 1, refined).** Measure TWO transport metrics separately, NOT just
"request→push": `T_transport` = request committed → owner **actionable alert** delivered; `T_roundtrip`
= request committed → response decryptable by B. PLUS a TOTP-specific metric: **remaining TOTP lifetime
at B receipt**. Gate:
- **GO:** p95 `T_transport` ≤ 5s · post-approval delivery comfortably low · ≥95% codes arrive with
  **≥15s** TOTP remaining.
- **CONDITIONAL GO:** p95 `T_transport` 5–10s · small tail of low remaining · require retry UX +
  code-gen-timing mitigation.
- **STOP / ESCALATE:** p95 `T_transport` > 10s · OR a significant fraction arrives with **<8s** remaining
  · OR CloudKit delivery operationally unreliable.
On STOP, **do NOT abort the feature** — split the roadmap: still ship non-latency-sensitive parts
(password `none|shared`, field snapshots, CKShare grant, revoke future access, non-interactive grants);
STOP before interactive-approval phases (TOTP Ask Owner, and future passkey/SSH/browser approval). Then
choose: (A) ship non-interactive grants only, (B) add a dedicated relay (e.g. Cloudflare ephemeral
control plane), (C) rework transport. Also: **generate the TOTP code only AFTER Face-ID approve** (not on
push arrival) so owner read-time doesn't eat the code's life (→ Phase 5).

**§2 — Approval Mode independent of vault-item sync (ADR-2).** Two flags `vaultItemSyncEnabled` vs
`approvalModeEnabled`; two services `CloudSyncService` vs new `ApprovalSyncService`. Acceptance test:
given `vaultItemSyncEnabled=false` + `approvalModeEnabled=true` → **no VaultItem uploads**, yet identity
escrow + grants + requests + responses sync and TOTP approval works. UX copy = "enable encrypted approval
transport", never "enable iCloud sync". Control plane must not pull secret plane. (→ Phase 3, Phase 8 test.)

**§3 — Fresh recipient must have a vault before accepting (Phase 6).** No Vault Key → no participant
identity escrow → no share acceptance. On opening an invite without a vault: persist a
`PendingShareAcceptance` (routing-only, non-sensitive), guide B through vault onboarding, then **resume**
acceptance. Participant identity creation is **transactional** (vault ready → create → seal under B Vault
Key → persist → publish) — never create the key then wait to escrow (crash-safe). No guest mode in V1.

**§4 — Participant added programmatically by email/phone (ADR-4, Phase 4).** Use `CKUserIdentity` lookup +
add-participant, NOT `UICloudSharingController`; more control over the fingerprint/pin ceremony.

### Whole-Plan Consistency Sweep (Validation)
Propagated §1→P1/P5, §2→P3/P8, §3→P6, §4→P4. No contradictions with the ADRs or Red Team decisions.
Recommendation: **proceed to implementation** — start with the Phase 1 gate.

### Session 2 — 2026-07-05 — Phase 1 gate ran
Spike executed on 2 devices / 2 real iCloud accounts (10 runs). Verdict: **CONDITIONAL GO** — full
decision record in **ADR-6** + phase-01 "Gate verdict". Key correction from the user during verdict:
the draft mitigation "send the NEXT window's code when remaining is low" was **rejected as a logic bug**
(future-code pre-send; the RP judges by ITS clock — ±1-step tolerance is not a contract, per H2). The
binding algorithm is **boundary-aware issuance**: wait for the boundary, then generate the now-current
code. Propagated: ADR-6 → P5 (issuance state machine incl. `WAITING_FOR_FRESH_WINDOW`, abort-on-background,
seed read only at boundary), P6 (timeout + superseding retry, stale-response fail-closed), P8 (decomposed
hop telemetry + post-mitigation stop condition). Gate wording amended: the ≥95%/≥15s criterion is
measured AFTER the issuance policy.
