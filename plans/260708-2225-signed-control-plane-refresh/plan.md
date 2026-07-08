# Signed Control-Plane Refresh — centralized lifecycle refresher

Owner directive (260708): Quick View GA `exposure` stuck hidden because the signed
capability manifest is never refreshed except as a side-effect of opening
Personas → Aliases. Fix as a CENTRALIZED control-plane lifecycle fix, not a
Quick View-specific patch.

## Root cause (verified)
- Launch: `AppEnvironment.init` only `applyCached()` (local, no network) — `AppEnvironment.swift:132`.
- Foreground `.active`: reload repo + `syncNow()` only — `RootView.swift:60`. No manifest refresh.
- `capabilityManifest.refresh()` invoked ONLY at `PersonaAliasesScreen.swift:209`.
- Fresh install → no cache → `quickViewExposure == nil` → resolver `.hidden` → entry hidden.

## Invariants (acceptance)
- INV-CP-01 freshness MUST NOT depend on visiting a feature screen.
- INV-CP-02 network refresh MUST NOT block startup/unlock/render/AutoFill.
- INV-CP-03 last-known-good verified state survives transient refresh failure.
- INV-CP-04 fresh install eventually fetches without user navigation.
- INV-CP-05 concurrent lifecycle triggers deduplicate.
- INV-CP-06 anti-rollback state env- and document-family-scoped.

## Phases
| # | File | Status |
|---|------|--------|
| 1 | phase-01-control-plane-refresher.md — coordinator (dedupe/freshness/independent failures) | ✅ done |
| 2 | phase-02-anti-rollback-and-env-scoping.md — recovery fix + env-scoped high-water | ✅ done |
| 3 | phase-03-lifecycle-wiring.md — launch-after-unlock + foreground triggers, decouple Persona | ✅ done |
| 4 | phase-04-tests.md — 12 owner scenarios + parity | ✅ done (431/431) |

Status: implemented on `main` working tree (not committed). Compile ✅ (app+ext), tests 431/431.
Owner decisions D1/D2/D3 locked (see report). Manual device QA owed before merge.

## Owner decisions required BEFORE implementation (see report)
1. Rollback recovery: relax `>` → `>=` (accept equal version when re-serving). [P0]
2. Env-scoping key migration: renaming version keys resets high-water → 0 once
   (side effect: unsticks currently-stuck prod installs). Approve one-time reset?
3. Stale thresholds (concrete numbers).

## Open question back to BE
- Case A: was any BETA manifest ever served at `manifest_version >= 7`? If yes,
  GA v7 is rejected on those devices and BE must bump above the highest ever served.

## Key deliverable
`plans/reports/from-app-to-owner-260708-2225-signed-control-plane-refresh-design.md`
answers the owner's 5 send-back items.
