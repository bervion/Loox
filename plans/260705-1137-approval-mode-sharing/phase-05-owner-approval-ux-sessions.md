---
phase: 5
title: "Owner approval ceremony (foreground)"
status: pending
priority: P1
effort: "1.5d"
dependencies: [3]
---

# Phase 5: Owner approval ceremony (foreground)

## Overview
The owner's approve/reject experience as a **foreground user-presence ceremony** (ADR-1). A user-visible
alert push announces a request; A taps it, Loox opens to the *verified* request, A authenticates (Face
ID/passcode) which unlocks the vault, the current one-time code is generated **in foreground**, sealed to
B's per-request ephemeral key (ADR-3), and delivered. **No background generation, no auto-approve, no
approval sessions** — those are removed from V1 (M4) because the vault key is zeroised on background.

## Requirements
- Functional: alert push (opaque `requestOpaqueID`) → tap → fetch + **verify before showing UI** →
  context-rich sheet (service, requester device, time, security code to compare) → Face ID → unlock →
  generate current TOTP → seal to ephemeral key → respond; explicit reject path.
- Non-functional: notification = attention only (no secret in payload, no action button that returns a
  secret); Face ID via existing `BiometricAuth`; vault must be unlocked before seed access; temp plaintext
  buffers zeroed after use; localized EN+VI; DS-compliant.

## Architecture
- **Notification → app (ADR-5):** `.approvalRequestReceived` carries only `requestOpaqueID`. Tapping opens
  the app; a killed/backgrounded app cannot approve headless (ADR-1) — the tap brings A to foreground.
  A pending-requests inbox also lets A find requests if a push was missed.
- **Verify-before-show:** on open, `ApprovalVerifier` (Phase 2) checks pinned signature, grant, participant,
  **fresh epoch fetch**, expiry, nonce. Only a passing request renders the approval sheet.
- **`ApprovalRequestSheet`:** shows item title, capability, requester device label, timestamp, and a
  derived **security code** (from the verified request) that also shows on B's screen for visual match.
  Reject = one tap → signed `decision: reject` response.
- **Approve ceremony:** `BiometricAuth` Face ID/passcode → `VaultSession.unlock()` → read the TOTP seed →
  `TOTPGenerator.code(forStoredValue:date:)` → `ApprovalPayload{code, validUntil, requestNonce}` →
  `ApprovalSeal.sealResponse(toEphemeral:)` (ADR-3) → `ApprovalShareService.respond(...)` → zero temp
  buffers → relock per existing session policy.
- **Boundary-aware issuance (ADR-6 — MANDATORY, gate condition):** generate the TOTP **only at the
  approve hop** (after Face ID), never on push arrival. Then:
  ```
  OWNER_APPROVED → CHECK_TOTP_WINDOW
    ├─ remaining ≥ policy.minimumRemainingLifetime → ISSUE_NOW
    └─ remaining <  policy.minimumRemainingLifetime → WAITING_FOR_FRESH_WINDOW
         → (boundary reached, still foreground + vault session valid) → ISSUE_NOW
  ```
  **NEVER pre-send a future-period code** — a TOTP for counter N+1 must not be delivered while local
  trusted time is still in counter N (the RP judges by its own clock; ±1-step tolerance is not a
  contract — H2). `ISSUE_NOW` = read seed → generate current-period code → seal → send immediately.
  - Policy constant, not magic number: `TOTPIssuancePolicy { minimumRemainingLifetime: 18 /* = delivery
    5 + recipient-use 10 + skew 3 */, responseTimeout: 20 }` (own small type, tunable).
  - **Seed-exposure minimization:** during `WAITING_FOR_FRESH_WINDOW` do NOT read the TOTP seed yet —
    compute timing only; at the boundary re-check foreground + vault session validity, THEN read seed →
    generate → seal → zero. Never cache the seed across the wait.
  - **Abort on background/lock (ADR-1/C1):** if the app backgrounds or the vault locks mid-wait
    (key zeroised, `RootView.swift:82`), ABORT issuance — no background continuation. B receives an
    "approval interrupted — request again" outcome; A can re-auth on return per the state machine.
  - UI copy while waiting — A: "✓ Approved · Preparing a fresh verification code…"; B: "Approved by
    {owner} · Preparing a fresh code…" (bounded by threshold, <18s).
  - **Time math (ADR-7):** window/boundary computed ONLY as `unixSeconds / period` and
    `period − unixSeconds % period` — never `Calendar`/`TimeZone` (DST/timezone must not shift the
    boundary). The wait itself is scheduled off monotonic time; the threshold covers delivery +
    recipient use + clock uncertainty + RP verification delay, not just network.
- **Latency honesty (H2):** `validUntil = current TOTP period end` (owner clock). B renders by it; if
  latency/skew consumed the window, B sees "Request again" (Phase 6). Do NOT claim the code will be
  accepted by the relying party — only that it was current when sealed.

## Related Code Files
- Create: `Vaultify/Features/Sharing/ApprovalRequestSheet.swift`, `PendingApprovalStore.swift`,
  `PendingApprovalInbox.swift`
- Modify: `Vaultify/App/AppPushDelegate.swift` (deep-link opaque id → sheet), `ApprovalShareService.swift`
  (respond)
- Reference: `VaultifyCore/Keychain/BiometricAuth.swift`, `VaultifyCore/TOTPGenerator.swift`,
  `Vaultify/Security/VaultSession.swift`, `Vaultify/App/RootView.swift:82` (background lock — the reason
  for ADR-1), `Vaultify/shared` PolarisModal (reject styling)

## Implementation Steps
1. `PendingApprovalStore` + `PendingApprovalInbox` (queue verified inbound; list for missed pushes).
2. Deep-link: tapping the alert push resolves `requestOpaqueID` → fetch → verify → present sheet.
3. `ApprovalRequestSheet` with context + security code + Approve(Face ID)/Reject.
4. Approve ceremony: Face ID → unlock → **boundary-aware issuance state machine (ADR-6)** → seal to
   ephemeral (ADR-3) → respond → zero buffers. Includes `TOTPIssuancePolicy`, `WAITING_FOR_FRESH_WINDOW`
   wait UI, and abort-on-background/lock.
5. Reject: signed reject response so B stops waiting.
6. Localize EN+VI; DS tokens; Reduce Motion/Transparency checks.
7. `make check`.

## Success Criteria
- [ ] Alert push (user-visible) → tap → app foreground → request verified BEFORE the sheet shows.
- [ ] Approve requires Face ID + unlocked vault; code generated only in foreground; seed never leaves vault.
- [ ] Approved code sealed to the **ephemeral** key (opens on B per ADR-3); temp buffers zeroed.
- [ ] Reject delivers a signed reject B can see.
- [ ] No session / auto-issue / background path exists (grep: no auto-approve code).
- [ ] **ADR-6 acceptance test:** a code for TOTP counter N+1 is never delivered while trusted local time
      is still in counter N; remaining < threshold → issuance waits for the boundary; backgrounding
      mid-wait aborts issuance (no seed cached across the wait).
- [ ] Fully localized + DS-compliant.

## Risk Assessment
- Missed alert push (iOS budget) → A never taps. Mitigation: pending-requests inbox + B-side timeout
  (Phase 6); acceptable because approval is inherently interactive.
- Clock skew makes B's countdown mildly wrong even for a good code — render from owner `validUntil`, not
  B's clock; document that RP acceptance depends on the RP clock.
