---
phase: 1
title: Adversarial Staging Drills (QV-A4)
status: completed
priority: P1
effort: 0.5d
dependencies: []
---

# Phase 1: Adversarial Staging Drills (QV-A4)

## Overview

Run the live server-state + race drills against staging (shadow assertion, beta cohort) that unit
tests can't cover. Automated adversarial coverage is already green (409/409). Checklist authority:
`plans/260708-1038-loox-quick-view-browser-handoff/reports/qv-a4-adversarial-staging-drills-checklist.md`.

## Requirements

Prereqs live: quick-view worker + signer keyset (`cap-2026-02`) + `/open` (QR now decodable). DEBUG
build with launch arg `-quick_view_exposure_override beta`. Curl helper (create session) in the checklist.

Drills to pass:
- Happy path control (scan + enter code) → browser renders exactly the toggled fields; history row =
  `item_id+timestamp+result` only.
- One-shot consume (2nd consume fails); session expired (>180s); reused session (2nd upload fails).
- **Concurrent-approval race** → exactly one ciphertext lands, loser handled gracefully.
- **QR-photographed / bind-first** → legitimate approval still wins (no dead-lock).
- SAS mismatch = abort-only; airplane mid-ceremony = calm generic error, no partial state.
- Guard2 TOTP → 2FA toggle absent; TOTP window-edge → wait/abort bounded by session TTL.
- Exposure matrix: public build + `exposure=beta` → no entry; `public`+shadow → fail closed.
- Failure discipline: unknown/expired/consumed/foreign are one generic message (no oracle).
- Log hygiene: no session_id / code / SAS / plaintext in device logs.

## Implementation Steps

1. Point a DEBUG build at staging (default) + set the exposure override to beta.
2. Walk the checklist; use the curl helper for the race / one-shot scripted uploads.
3. File any failure; fix app-side if it's an app bug, else escalate (BE staging / contract).
4. Record pass/fail per drill in the checklist; attach anomalies.

## Success Criteria

- [ ] All drills pass; race + QR-photographed confirm exactly-one-winner, no dead-lock
- [ ] Generic-failure discipline verified (no state oracle)
- [ ] No sensitive material in logs
- [ ] Any app-bug fixes merged; suite still green

## Risk Assessment

- Race/one-shot need two clients or scripted curl — attestation is shadow, so a scripted upload
  without the attest trio is accepted (sufficient for the race test).
