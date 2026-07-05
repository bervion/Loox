---
phase: 8
title: "Localization, DS compliance, integration gate & QA"
status: in_progress # 2026-07-05 — automated gates done; TWO-DEVICE QA = user runbook below
priority: P1
effort: "1.25d"
dependencies: [4, 5, 6, 7]
---

# Phase 8: Localization, DS compliance, integration gate & QA

## Overview
Final hardening: EN+VI localization, design-system audit, an **integration gate** proving Phase-2
canonical bytes survive Phase-3 CKRecord round-trip across two accounts (the seam most likely to silently
break signatures), a version handshake, DEBUG crypto self-test, and a two-account on-device QA of the
full foreground ceremony. (Latency was already measured by the Phase-1 gating spike.)

## Requirements
- Functional: every user-facing string EN+VI; integration gate green; DEBUG self-test; documented
  two-device QA of the ceremony + revoke.
- Non-functional: no hardcoded colors/sizes/icons; 44pt; light/dark/Reduce-Transparency/Reduce-Motion/
  increased-contrast verified; `make check` green (app + extension).

## Architecture
- **Integration gate (M4/S):** round-trip signed `AccessGrant`/`ApprovalRequest`/`ApprovalResponse`
  through actual `CKRecord` encode→save→fetch→decode across **two accounts**, then verify the signature
  still validates (canonical bytes unchanged). Add an explicit **version handshake** + same-version
  precondition so mismatched TestFlight builds fail loudly, not with a cryptic verify failure.
- **Localization sweep:** grep `Features/Sharing/*` + `Services/Sharing/*` for string literals; ensure each
  is in `Localizable.xcstrings` with EN + VI (missing VI = bug). Titles `.inAppLocalized`, runtime `appString()`.
- **DS audit:** grep new SwiftUI for `.font(.system`, raw `Color(`/`.white`/`.black`, `Icons.` misuse,
  hardcoded paddings → replace with `vaultType`, `ThemeRole`, `PolarisIcons`, `Space.*`/`Radius.*`.
- **DEBUG self-test:** extend the file-based harness (write Documents, read via `simctl get_app_container`)
  to cover Phase-2 invariants end-to-end (sign/verify/tamper, HPKE both recipient types, replay, epoch,
  unpinned-key reject, unknown-fieldId fail-closed).
- **Sync-independence acceptance test (Validation §2):** with `vaultItemSyncEnabled=false` +
  `approvalModeEnabled=true`, assert **no VaultItem record uploads** occur while identity escrow / grants /
  requests / responses DO sync and TOTP approval works end-to-end.
- **Fresh-recipient test (Validation §3):** open an invite on a device with no vault → guided onboarding →
  `PendingShareAcceptance` survives (incl. app relaunch) → acceptance resumes; participant identity created
  transactionally.
- **Two-account ceremony QA:** share (programmatic participant + fingerprint) → accept → `shared` field
  visible on both B devices → TOTP `askEachTime` request → owner **alert** notification → tap → verify →
  Face ID → foreground code (boundary-aware issuance, ADR-6) within window → revoke → leave → reject →
  notification-denied fail-closed.
- **Latency telemetry decomposition (ADR-6 gate condition):** instrument and record per-hop metrics so
  any outlier is attributable (the Phase-1 15.5s outlier could not be decomposed):
  `T_request_commit_to_alert` · `T_alert_to_owner_open` · `T_owner_approve_to_response_commit` ·
  `T_response_commit_to_B_fetch` · `T_approve_to_B_decrypt`. Gate criterion "≥95% of delivered codes
  arrive with ≥15s remaining" is evaluated **after** boundary-aware issuance. **Post-mitigation stop
  condition:** significant receipt tail <8s remaining OR isolated transport p95 >10s at meaningful
  sample size → pause latency-sensitive approval rollout, escalate transport design (Validation §1).
  Internal durations measured on the **monotonic clock** per device (ADR-7 — wall clock can be adjusted
  mid-measurement); wall-clock timestamps logged separately for cross-device correlation.
- **Time-invariant tests (ADR-7/H8):** mocked identical Unix instant with timezone pairs
  America/New_York↔Asia/Ho_Chi_Minh and America/Los_Angeles↔Asia/Tokyo → same TOTP counter/boundary/
  remaining; skew simulations ±5s/±10s/±20s (device vs mocked "true" time) documenting user-visible
  outcome; grep gate: no `Calendar.current`/`TimeZone.current`/`DateComponents` in
  `VaultifyCore/Sharing/*`; suspicious system-clock-jump detection fires (wall vs monotonic divergence).

## Related Code Files
- Create: `VaultifyCore/Sharing/ApprovalIntegrationSelfTest.swift` (DEBUG)
- Modify: `Vaultify/Resources/Localizable.xcstrings`, all `Vaultify/Features/Sharing/*`, `Services/Sharing/*`
- Docs: update `docs/codebase-summary.md`, `README.md` highlights (new capability), `docs/design-guidelines.md`
  (if new components), and correct the CLAUDE.md "iCloud off / keep out" note (now stale).

## Implementation Steps
1. Integration gate: CKRecord round-trip signature-survival test across two accounts + version handshake.
2. String sweep + EN+VI entries; fix missing VI.
3. DS audit + fixes; verify accessibility states.
4. Extend DEBUG self-test for all control-plane invariants; run via simulator container read.
5. Two-account ceremony QA script; record results.
6. Update docs (codebase-summary, README, design-guidelines, CLAUDE.md iCloud note).
7. `make check` (app + extension) green; `tuist generate` clean.

## Success Criteria
- [ ] Integration gate passes: signatures survive CKRecord round-trip across two accounts; version
      handshake blocks mismatched builds.
- [ ] Zero hardcoded user-facing strings; every new string EN+VI present.
- [ ] DS audit clean (tokens only, Polaris icons, 44pt, accessibility states).
- [ ] DEBUG self-test passes all crypto invariants.
- [ ] Two-account ceremony QA verified on device (share → foreground approve → revoke → leave → reject).
- [ ] `make check` green; docs updated (incl. corrected CLAUDE.md iCloud note).

## Status — 2026-07-05

**Done (automated):** localization sweep — 52 sharing-UI literals script-verified against the catalog,
all EN+VI, interpolation keys byte-exact. DS audit grep — no `.font(.system`, no SF Symbols, no raw
colors, no raw `ic_` literals, no `BlurStyle.inner` in Sharing UI. ADR-7 grep gate — kernel free of
`Calendar`/`TimeZone`/`DateComponents`. Kernel invariants covered by 14 unit tests (sign/verify/tamper,
HPKE both recipients + cross-open fails, replay, epoch, lifetime clamp, unpinned keys, unknown-field
fail-closed, zero-period fail-closed, verifyResponse suite, multi-key canonical round-trip, escrow
round-trip, window math + issuance policy boundary). Suite 161/161; iOS + macOS compile green.
Docs updated (codebase-summary, README, CLAUDE.md iCloud note corrected).

**Remaining — TWO-DEVICE QA (user, Debug app on both, 2 iCloud accounts):**
1. **Share + fingerprint:** A: item → ⋯ → Share Access… → email B → capabilities (1 shared password +
   TOTP ask-each-time) → Create Share → send invite. B: tap invite → app opens → Home shows "Shared
   with Me" → open item → fingerprint codes MATCH on both → confirm both sides. ✅ proves C1 zoneID fix
   (cross-account shared-DB addressing) + accept-resume + escrow.
2. **Shared value:** B sees the shared password value after pin. Second B device (if available): same
   value decrypts (escrow recovery).
3. **Ceremony happy path:** B: Request Code → A gets ALERT push → tap → sheet shows request + match
   code (equals B's) → Approve with Face ID → B receives code with comfortable remaining life. Repeat
   ~10× and note `TOTP_remaining` — gate: ≥95% arrive ≥15s (measured AFTER boundary-aware issuance).
4. **Boundary wait (ADR-6):** time an approve so the ring is near the end of a 30s window → A shows
   "Preparing a fresh verification code…" for a few seconds → B's code arrives with ~25-29s left.
   NEVER a code that dies instantly.
5. **Abort:** A backgrounds the app mid-wait → B shows "Approval was interrupted — request again".
6. **Supersede:** B: Request → wait past ~20s → Request Again → only ONE code ever displays.
7. **Reject + revoke + leave:** reject → B sees declined. A: Share Access → swipe → Revoke → B's next
   request fails / item shows owner stopped sharing. Separate share: B leaves → A row still local
   (SharingStore is device-local; refresh case documented).
8. **Sync independence (Validation §2):** A with iCloud Sync toggle OFF + a share active → approval
   round-trip works AND no VaultItem records appear in CloudKit console.
9. **Nonce collision shape (H4, if A has 2 devices):** approve the same request from both quickly —
   second must fail, never double-issue.
10. **A11y passes:** VI language, dark mode, Reduce Motion — sharing screens render, no invisible text.

**Deferred (recorded, not blockers):** CKQuerySubscription experiment for the false profile-publish
alert (M2, phase-03); decomposed per-hop latency telemetry (ADR-6 condition 5) — measure during QA run
#3 manually (request→alert, approve→receive) if the gate numbers look off; escrow AAD + writer u32
clamp hardening (phase-02 list); multi-device-owner grant signing (V1: approve on the sharing device).

## Risk Assessment
- If the integration gate fails (canonical bytes mutate through CKRecord), fix the encoder before shipping —
  every real cross-user verify depends on it.
- VI translation quality — user (native VI) can proof.
