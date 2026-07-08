---
phase: 6
title: "Device & Browser QA on Staging (QV-A5)"
status: pending
priority: P2
effort: "0.5d + manual"
dependencies: [5]
---

# Phase 6: Device & Browser QA on Staging (QV-A5)

## Overview

**Manual, cross-team.** End-to-end happy-path + UX QA on live staging with the real `/open`
page across the browser matrix. Gate before assertion-shadow verdicts and prod manifest flip
(BE rollout steps 4–5). Analogous to A6 in the auxiliary-domains plan — expect a Release/
TestFlight-style caveat if staging config lags DEBUG.

## Requirements

- Browser matrix: Chrome / Safari / Firefox / Edge × Windows / macOS / Linux (Safari macOS-only).
- Per cell: session create → QR scan → SAS match → approve (default fields) → render → one-shot
  consume → `[Close & Clear]`.
- Signaling: SSE primary works; kill SSE → long-poll fallback still delivers "payload ready".
- Enter-code path on at least 2 browsers (code readability, TTL countdown parity).
- Clipboard warning UX on copy ("copied to THIS computer's clipboard").
- Render TTLs: 5 min max render, 2 min hidden auto-lock (owner-locked) — verify actual timing.
- Real-device QR scan reliability at chosen density variant (validates Phase 1 benchmark in the
  wild: older device + low light).
- App-side: TestFlight/Release build if staging capability manifest/service-state lags DEBUG
  config (auxiliary-domains A6 lesson — check staging manifest ships `quick_view` first).

## Implementation Steps

1. Confirm staging: quick-view worker + `/open` live, `quick_view` capability in staging
   manifest, assertion mode = shadow.
2. Run matrix; record per-cell pass/fail + notes in checklist below.
3. UX findings → small fixes (strings, spacing, countdown) directly; protocol findings →
   escalate to BE before prod flip.
4. Report verdict to owner: go/no-go along the owner-frozen rollout (DEC-QV-EXPOSURE-01):
   `1 staging off → 2 staging shadow → 3 staging required → 4 prod dark deploy → 5 prod beta cohort +
   shadow → 6 collect verdicts → 7 prod required → 8 verify health → 9 public GA manifest active`.
   This device/browser QA slots at steps 2–3 (staging) and re-runs against the beta cohort at step 5.
   **Public GA (exposure=public) stays hidden until assertion=required (step 7, INV-QV-24);** step 5's
   beta shadow is where real-device App Attest learning happens (invalidKey, re-registration,
   challenge retry, latency, stale builds) — but must NOT claim "fully protected."

## Success Criteria

- [ ] All matrix cells pass happy path + one-shot + clear
- [ ] SSE and long-poll fallback both verified
- [ ] TTL/auto-lock timings verified against owner-locked values
- [ ] QR scan reliability acceptable on oldest supported device
- [ ] Go/no-go recorded against 9-step rollout; public GA held until step 7 required-mode (DEC-QV-EXPOSURE-01/INV-QV-24)
- [ ] Beta cohort real-device App Attest verdicts collected in shadow (step 5) before required

## Risk Assessment

- Staging config drift (manifest/service-state) can block DEBUG builds silently — verify config
  plane FIRST (auxiliary-domains A6 caveat precedent).
- Browser quirks (Safari WebCrypto non-extractable keys, Firefox SSE buffering) are BE/web-side
  fixes; app team only verifies and reports.
- Verify `/open` field-level TOTP countdown + redaction on `valid_until` (DEC-QV-TOTP-01) across the
  browser matrix — clock-skew edge (browser slightly behind → code shown 1–2s past validity).

<!-- Updated: Validation Session 1 — 9-step rollout (DEC-QV-EXPOSURE-01), field-level TOTP countdown verification (DEC-QV-TOTP-01) -->

## Unresolved questions

None. Rollout gating is owner-frozen; execution depends on BE staging + cohort allowlist.
