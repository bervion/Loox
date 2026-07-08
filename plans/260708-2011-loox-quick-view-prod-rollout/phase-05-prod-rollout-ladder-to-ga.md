---
phase: 5
title: "Prod Rollout Ladder to GA"
status: pending
priority: P1
effort: "staged, owner/BE-gated"
dependencies: [4]
---

# Phase 5: Prod Rollout Ladder to GA

## Overview

Walk the owner-frozen **required-before-active** ladder (DEC-QV-ROLLOUT-01). Prod MUST NOT be active
while upload-assertion enforcement is below `required` — the worker 503s this and the app fails closed
(`public`+shadow → no entry, INV-QV-24). Public GA = flipping `quick_view.exposure` to `ga` only after
assertion=required + health verified.

## Requirements — ladder (in order)

```
prod dark deploy (mode=disabled, assertion=off)
  → prod beta cohort + shadow          (exposure=beta; App Attest shadow accepts beta cohort)
  → collect App Attest verdicts        (real-device: invalidKey, re-registration, challenge retry,
                                        assertion latency, stale builds)
  → assertion = required               (BE flips QUICK_VIEW_ASSERTION_MODE; upload now enforced)
  → verify health                      (error rates, latency, 503 guard behaves)
  → flip exposure = ga                 (public GA — general users see entry only when required)
```

- Owner/BE own each rung; app team monitors verdicts + confirms the app honors each manifest state.
- Kill switch: `quick_view` service-state (`maintenance|disabled|retired`) + capability breaker — an
  outage never touches the Core Vault (optional-network by design).

## Implementation Steps

1. Prod dark deploy (worker present, capability disabled).
2. Publish `exposure=beta` (from Phase 4); confirm only the beta cohort sees the entry, general build
   sees nothing, and `public`+shadow would fail closed.
3. Collect App Attest shadow verdicts from the beta cohort until clean.
4. BE flips assertion → `required`; confirm uploads without a valid assertion now rejected in prod.
5. Verify health (dashboards, 503 guard, error/latency); confirm `required-before-active` holds.
6. Owner flips `exposure=ga`; confirm general (non-beta) devices now show the entry (assertion required
   satisfied). Announce GA.

## Success Criteria

- [ ] Prod dark → beta+shadow → verdicts clean → required → health OK → `ga`, in order
- [ ] Prod never active while assertion below required (503 guard verified)
- [ ] Beta cohort exclusive during shadow; general users gated until `ga`+required
- [ ] Kill switch / breaker verified (outage doesn't touch Core Vault)
- [ ] GA announced; history/telemetry clean

## Risk Assessment

- Skipping "assertion=required" before active reopens the shadow-window race (INV-QV-16 unenforced) —
  the encoded 503 guard prevents it; do not relax.
- A stale signer keyset degrades Quick View to unavailable (never blocks Core Vault) — monitor keyset
  freshness during rotation windows.

## Next Steps

Post-GA: monitor; consider V2 non-goals later (passkey handoff, multi-item, Mac/iPad native enter-code).
Archive both Quick View plans via `/ck:plan archive` once GA is stable.
