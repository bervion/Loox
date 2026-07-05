---
phase: 6
title: "Recipient UX & request state machine"
status: pending
priority: P1
effort: "1.5d"
dependencies: [3]
---

# Phase 6: Recipient UX & request state machine

## Overview
The recipient (B) side: an accepted shared item appears read-only in B's vault ("shared by A"). `shared`
fields render values (and B retains them); the TOTP field shows a "Request" control that drives an
explicit request state machine and displays the returned ephemeral code with a live countdown, with a
hard timeout so B is never stranded.

## Requirements
- Functional: accepted share surfaces read-only, badged "shared by A"; per-field rendering by capability;
  Request button for the TOTP field; ephemeral code + countdown + copy/AutoFill; explicit states with
  timeout and reject handling; security code shown for the owner-side match.
- Non-functional: never persist the ephemeral secret past `validUntil`; clearly distinguish shared (not
  owned); `shared` values are decrypted with B's **persistent participant** key, approved codes with the
  **per-request ephemeral** private key (ADR-3); localized EN+VI; DS-compliant.

## Architecture
- **Accept precondition (Validation §3):** B must have an initialized vault (Vault Key) BEFORE a share can
  be cryptographically accepted — no Vault Key → no participant escrow → no accept. If B opens an invite
  without a vault: persist a `PendingShareAcceptance` (routing-only, non-sensitive), guide B through vault
  onboarding, then **resume** acceptance (invite must survive onboarding, even across a crash). Participant
  identity is created **transactionally** post-vault (Phase 3), never as a pre-vault transient. No guest
  mode in V1.
- **Request state machine:** `IDLE → REQUESTING → WAITING_FOR_OWNER → {APPROVED → CONSUMED | REJECTED |
  EXPIRED | SUPERSEDED}`. `EXPIRED` fires from a B-side timeout keyed on `ApprovalRequest.expiresAt`
  (H2/U) — B does not wait forever if a push is lost. `WAITING_FOR_OWNER` shows the security code for
  A↔B match, elapsed time, and past the threshold offers: "This request is taking longer than usual —
  [Keep Waiting] [Request Again]".
- **Superseding retry (ADR-6 gate condition):** "Request Again" must **invalidate/supersede** the old
  request (request generation counter or `supersedesRequestID`, with authoritative active-request state)
  so an old approval + a new approval can never both be live. Owner side verifies against the active
  request only.
- **Late/stale response fail-closed (ADR-6 gate condition):** a response arriving for an expired or
  superseded request is **rejected and never displayed** — no "late ciphertext arrived → show code
  anyway" path. Also render the owner's `WAITING_FOR_FRESH_WINDOW` signal ("Approved by {owner} ·
  Preparing a fresh code…") so the boundary wait doesn't look like a hang.
- **Keys (ADR-3):** `shared` `SharedFieldBlob` opened with the participant private key (recovered from B's
  Vault-Key escrow, Phase 3); `APPROVED` payload opened with the request's ephemeral private key + `info =
  requestId+nonce`.
- **Shared item model:** `SharedItemView` fed by `ApprovalRecipientService` (Phase 3) — a read-only
  projection (metadata + decrypted `shared` values + TOTP placeholder). Badge "Shared by {owner}".
- **Ephemeral display (ADR-7):** reuse `TotpRingView`/countdown driven by the payload's
  `periodEndUnixMs` (owner-generated window context), not a local seed. The countdown is **advisory** —
  "About Ns remaining", never an exact validity promise; **B's clock never decides security validity**
  (the RP server is the final authority). On `EXPIRED` → "Request again"; copy/AutoFill for the code.
  Ephemeral secret dropped at period end, never written to the store. Local timezone is display-only.
- **Placement:** "Shared with me" section/list, visually separated from owned items; search integration.

## Related Code Files
- Create: `Vaultify/Features/Sharing/SharedItemView.swift`, `SharedItemsListScreen.swift`,
  `RequestCodeView.swift`, `RequestStateMachine.swift`, `PendingShareAcceptance.swift` (routing-only,
  survives onboarding), `AcceptShareFlow.swift` (vault-precondition + resume)
- Modify: `Vaultify/Features/Home/HomeScreen.swift` (Shared-with-me entry), search integration
- Reference: `Vaultify/Features/Home/Components/TotpRingView.swift`, `TotpCardView.swift`,
  `ItemDetail/TOTPFieldRow.swift`, `DetailFieldRow.swift`, `Vaultify/Services/Sharing/ApprovalRecipientService.swift`

## Implementation Steps
1. `RequestStateMachine` (IDLE→REQUESTING→WAITING→APPROVED/REJECTED/EXPIRED/SUPERSEDED/CONSUMED) with
   `expiresAt` timeout + superseding "Request Again" + stale-response rejection (ADR-6).
2. `SharedItemView`: read-only projection + "Shared by" badge; `shared` values via participant key.
3. `RequestCodeView`: Request → waiting (security code) → code + countdown (validUntil) → EXPIRED "Request
   again". Open payload with ephemeral private key (ADR-3). Copy/AutoFill.
4. `SharedItemsListScreen` + Home "Shared with me" entry; wire search.
5. Reject → clear waiting with a localized message.
6. Ensure ephemeral secret dropped at `validUntil`; never persisted.
7. Localize EN+VI; DS tokens; light/dark/Reduce-Motion.
8. `make check`.

## Success Criteria
- [ ] Accepted share appears read-only, badged, not editable; works on B's second device (escrow key).
- [ ] `shared` fields show values (participant-key decrypt); TOTP shows only Request until approved.
- [ ] Request → WAITING (security code) → valid code + countdown; push lost → EXPIRED via timeout, not a
      permanent spinner; reject → clear denial.
- [ ] Approved payload opens with the **ephemeral** private key (ADR-3); ephemeral code never persisted,
      gone after `validUntil`.
- [ ] **ADR-6:** "Request Again" supersedes the old request (two live responses impossible); a late
      response for an expired/superseded request is rejected fail-closed, never shown.

## Risk Assessment
- Latency makes "Waiting…" feel stuck — show elapsed + allow cancel; EXPIRED timeout bounds it.
- Users expect owned-item behavior (edit/AutoFill passkey) — copy sets expectation: capability, not
  ownership. `shared` values are retained by B and are NOT clawed back on revoke (state this).
