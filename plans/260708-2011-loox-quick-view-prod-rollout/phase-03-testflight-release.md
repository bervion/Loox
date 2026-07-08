---
phase: 3
title: "TestFlight Release"
status: pending
priority: P1
effort: "0.5d"
dependencies: [1, 2]
---

# Phase 3: TestFlight Release

## Overview

Cut a release carrying the Quick View build (schema-2 manifest verifier, `cap-2026-02` trust root,
BIP-39 SAS, App Attest) to TestFlight so App Attest runs on real devices and the schema-2 verifier is
on testers' devices BEFORE any schema-2 manifest publishes (Phase 4).

## Requirements

- On `main`, clean tree, all suites green. Release flow per `docs/deployment-guide.md`:
  `make beta` (→ `vX.Y.Z-beta.N`) or `make release` (conventional-commit bump + AI EN/VI notes + tag)
  → tag `v*` → GitHub Actions self-hosted runner → `tuist generate` → fastlane `match` signs app +
  extension → uploads to TestFlight via ASC API key.
- App Attest requires a real device (simulator `isSupported=false`). TestFlight build reads as the
  beta cohort (`QuickViewBuildCohort.isBeta` via sandbox receipt) so the exposure override isn't
  needed on device.

## Implementation Steps

1. Confirm Phases 1–2 green + no open app bugs.
2. `make beta` (or `make release`) on `main`; verify version bumped in `Project.swift`.
3. Watch the Actions run → TestFlight processing; confirm app + AutoFill extension signed.
4. Smoke on a physical device: install, unlock, open an item → "Open on Computer" appears (beta
   cohort) → scan the prod/staging `/open` QR → full E2E render. Confirm App Attest register+assert
   succeed on-device (shadow).
5. Distribute to the beta cohort.

## Success Criteria

- [ ] Beta build on TestFlight; app + extension signed; version bumped
- [ ] On-device App Attest register/assert works (shadow); full E2E renders on browser
- [ ] Schema-2 verifier confirmed present (device can verify a schema-2 manifest) — unblocks Phase 4 publish
- [ ] Beta cohort has the build

## Risk Assessment

- Self-hosted runner must have stable Xcode + Tuist + Ruby/Bundler (deployment-guide runbook).
- Do NOT publish a schema-2 manifest until this build is on devices (Phase 4 ordering).
