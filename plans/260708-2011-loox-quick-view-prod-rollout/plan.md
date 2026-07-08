---
title: Loox Quick View — Production Rollout & Finalization
description: >-
  Post-merge path to prod: staging drills, browser matrix, TestFlight, prod
  config re-sign + schema-2, and the required-before-active rollout ladder to
  GA.
status: pending
priority: P1
branch: main
tags:
  - quick-view
  - rollout
  - release
  - qa
blockedBy: []
blocks: []
created: '2026-07-08T13:16:15.014Z'
createdBy: 'ck:plan'
source: skill
---

# Loox Quick View — Production Rollout & Finalization

## Overview

App-side Quick View is **complete + merged to `main`** (PR #72) and E2E-verified on staging (scan QR →
resolve → approve → seal → browser renders fields). This plan takes it to production under the
owner-frozen **required-before-active** rollout (DEC-QV-ROLLOUT-01): QA the live server-state drills +
browser matrix, ship the app to TestFlight, re-sign prod config to `cap-2026-02` + publish schema-2
exposure, then walk the assertion shadow→required ladder before flipping exposure to `ga`.

**Predecessor plan:** `plans/260708-1038-loox-quick-view-browser-handoff/` (design, red-team,
validation, parity — all done). **BE handoff:** `plans/reports/to-backend-260708-2011-quick-view-prod-finalization-handoff.md`.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Adversarial Staging Drills (QV-A4)](./phase-01-adversarial-staging-drills-qv-a4.md) | Completed |
| 2 | [Browser Matrix QA (QV-A5)](./phase-02-browser-matrix-qa-qv-a5.md) | Pending |
| 3 | [TestFlight Release](./phase-03-testflight-release.md) | Pending |
| 4 | [Prod Config (resign + QR verify + schema-2)](./phase-04-prod-config-resign-qr-verify-schema-2.md) | Pending |
| 5 | [Prod Rollout Ladder to GA](./phase-05-prod-rollout-ladder-to-ga.md) | Pending |

## Ordering & dependencies

```
1 drills (staging) ─┐
2 browser matrix  ─┼─► 3 TestFlight release ─► 4 prod config (resign + schema-2 publish) ─► 5 ladder → GA
                    │        (schema-2 verifier must be on devices BEFORE a schema-2 manifest publishes)
```
- Phases 1–2 run now (staging live). Phase 3 needs 1–2 green. Phase 4 schema-2 publish is gated on
  Phase 3 (app on devices). Phase 5 is owner/BE-gated ops; **prod active requires assertion=required**
  (worker 503s otherwise — do not relax).

## Ownership split

- **App team / Claude:** Phase 1–2 execution + fixes, Phase 3 release cut (`make beta`/`release`).
- **Owner (root key):** `resign-config.sh` prod, manifest publishes, exposure flip.
- **BE:** QR fix confirmed on prod, assertion ladder, vector regen (base64url), `/open` prod headers.

## Non-goals
- Passkey handoff, multi-item, persistent sessions (V1 non-goals, unchanged).
- No app code changes expected unless a drill/matrix finding surfaces a real bug.

## Risks
- Publishing a schema-2 manifest before the app build reaches devices → schema-1 apps fail to verify
  it (fall back to bundled defaults). Strict ordering (Phase 3 before Phase 4 publish) mitigates.
- Prod active while assertion below required = open mailbox → encoded 503 guard must stay on.
