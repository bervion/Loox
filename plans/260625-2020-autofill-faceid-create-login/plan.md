---
title: AutoFill — Face ID unlock + Create-login from extension
description: ''
status: pending
priority: P2
branch: feat/identity-profile
tags: []
blockedBy: []
blocks: []
created: '2026-06-25T13:28:19.937Z'
createdBy: 'ck:plan'
source: skill
---

# AutoFill — Face ID unlock + Create-login from extension

## Overview

Two AutoFill UX upgrades for the Credential Provider extension, plus a device-signing gate.
**Phase 1** — unlock the extension with **Face ID** (1 tap) instead of typing the master
password, via a shared Keychain Access Group so the extension can read the biometric-gated
Vault Key the app stores. **Phase 2** — let the user **create + save a new login** (site /
username / email / generated password, prefilled from the default identity) directly from the
extension during web registration, returning the password to fill. **Phase 3** — verify on a
real device that the new shared-keychain entitlement signs and runs (provisioning/match risk).

Design + locked decisions: `plans/reports/from-brainstorm-to-planner-260625-2020-autofill-faceid-create-login-report.md`.

### iOS constraints (hard limits — shape scope)
- Extension is a separate process: cannot reuse the app's in-memory unlocked state → Face ID is the proper 1-tap equivalent.
- Third-party managers can only return `ASPasswordCredential` (username + password) → **no multi-field web identity fill** (name/DOB). Out of scope.
- No hook to auto-capture a manually typed password → only credentials flowing **through** the extension are saved (the Create-login flow). Out of scope: silent capture.

### Source of truth / conventions
- New UI strings localized **EN + VI** in `Localizable.xcstrings` (mandatory).
- Crypto/data types `nonisolated`; design tokens only (no hardcoded visuals); Polaris icons.
- Add a file → `tuist generate`. Build the workspace (see CLAUDE.md build quirk).

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Face ID unlock in extension](./phase-01-face-id-unlock-in-extension.md) | Completed |
| 2 | [Create & save new login from extension](./phase-02-create-save-new-login-from-extension.md) | Completed |
| 3 | [Device verification & signing](./phase-03-device-verification-signing.md) | Pending |

## Dependencies

Builds on completed work (no active blockers):
- `260613-2114-autofill-credential-provider` (completed) — extension + `VaultReader` exist.
- `260624-0959-identity-profile-feature` (completed) — default identity (`isDefaultIdentity`) used for Phase 2 prefill.

Phase order: 1 → 2 → 3 (3 verifies the entitlement change from 1). Phase 2 is independent of 1's
biometric path but reuses the same extension UI host, so sequence after 1 to avoid merge churn.

## Red Team Review

### Session — 2026-06-25
**Findings:** 16 (15 accepted, 1 rejected) · 3 hostile reviewers (Security Adversary, Assumption
Destroyer, Failure Mode Analyst). Each finding is detailed in the phase files under "Red Team
Adjustments (2026-06-25)".
**Severity breakdown:** 5 Critical, 7 High, 3 Medium (accepted); 1 High rejected on validation.

| # | Finding | Severity | Disposition | Applied To |
|---|---------|----------|-------------|------------|
| 1 | Silent-migration re-store site does not exist; needs one-time guarded migrate + delete old-group copy | Critical | Accept | Completed |
| 2 | `accessGroup` on `KeychainStore.set/get` is a no-op; all 4 inline `BiometricKeyStore` queries need `kSecAttrAccessGroup` | Critical | Accept | Completed |
| 3 | Default identity unreadable: `logins` password-filter + `decrypt` omits `isDefaultIdentity` | Critical | Accept | Phase 2 (#1) |
| 4 | `PasswordGenerator` move not trivial: wordlist `Bundle.main` app-only | Critical | Accept | Phase 2 (#2) |
| 5 | `ASCredentialIdentityStore` append clobbered by app `replace`/`clear` | Critical | Accept | Phase 2 (#3) |
| 6 | Localization catalog not in extension bundle → VI strings broken in extension | High | Accept | Phase 1 (#6) |
| 7 | Runtime access-group needs team prefix `WDNL2F75V7.` | High | Accept | Phase 1 (#2) |
| 8 | Extension can't push CloudKit; "pull picks it up" wrong direction | High | Accept | Phase 2 (#4) |
| 9 | Two local writers not governed by LWW; `VaultStore` `fatalError` on write | High | Accept | Phase 2 (#5) |
| 10 | Orphan item on fill-cancel/failed registration | High | Accept | Phase 2 (#6) |
| 11 | No rollback runbook for broken release tag; need runner dry-run | High | Accept | Phase 3 (#1) |
| 12 | `provideCredentialWithoutUserInteraction` must stay `userInteractionRequired` | High | Accept | Phase 1 (#5) |
| 13 | `VaultWriter` column/FieldKind contract; independent of `VaultRepository`; `passwordChangedAt` | Medium | Accept | Phase 2 (#7) |
| 14 | Biometric fallback on ANY error + `isEnrolled`/`retrieve` TOCTOU | Medium | Accept | Phase 1 (#4) |
| 15 | Extension write memory budget untested (large vault → jetsam) | Medium | Accept | Phase 3 (#4) |
| 16 | Replace shared keychain with `wrappedByBiometric` in `VaultKeyBundle` | High | **Reject** | — |

**Rejection rationale (#16):** Premise invalid. Extension biometric unlock requires a biometric-gated
item the extension process can read; iOS shares keychain only via a shared access group (App Group
shares files/UserDefaults, not keychain). A `wrappedByBiometric` bundle field still needs a shared-group
Secure-Enclave KEK → does NOT avoid the entitlement change. User's locked decision (shared keychain
group) stands. Only the valid sub-point kept: update the stale `SharedConfig.swift:5-6` comment.

### Whole-Plan Consistency Sweep (Red Team)
- Phase 1: superseded the "re-store on next unlock / store deletes first" migration prose and the
  `KeychainStore.set/get` param framing → now point to one-time guarded migration + all-4-inline-queries.
- Phase 2: superseded "filter `isDefaultIdentity` on logins", "saveCredentialIdentities (not replace)"
  framing (now best-effort + app foreground reload), and the "LWW resolves concurrency" risk row.
- Phase 3: added rollback runbook, runner dry-run, shared-group runtime self-test, memory + VI tests.
- No remaining contradictions across plan.md / phase files. Localization-in-extension (Finding 6) is now
  a cross-cutting requirement referenced from Phase 1 and re-verified in Phase 3.

## Validation Log

### Session 1 — 2026-06-25
Verification pass skipped (Red Team section already carries codebase-evidenced verification; no
`[UNVERIFIED]` tags remain). 4 product/decision questions asked; all resolved.

| # | Decision | Choice | Impact |
|---|----------|--------|--------|
| V1 | Orphan item on failed/abandoned registration | **Save normally, NO flag** | ⚠️ Overrides Red Team Finding #10's recommended "unconfirmed" flag. User accepts vault may accrue junk logins from abandoned signups; user prunes manually. Phase 2 Adjustment #6 simplified — no metadata marker, no badge. |
| V2 | Generator passphrase in extension | **Bundle wordlist into extension** | Add `eff_large_wordlist.txt` to the extension's `resources:` in `Project.swift`; load via module bundle (`Bundle(for:)`), not `Bundle.main`. Passphrase available in extension. Phase 2 Adjustment #2 → pick the bundle option (not char-pool-only). |
| V3 | Migration for already-enrolled Face ID users | **Silent on next in-app unlock** | One-time guarded migrate; until it runs, extension Face ID falls back to master password. No user prompt. Confirms Phase 1 Adjustment #3 design. |
| V4 | Existing AutoFillView strings broken in extension (Finding #6) | **Fix old + new** | Localization wiring (catalog into extension resources + `appResourceLocale` from App Group) covers ALL extension strings, not just new ones. Phase 1 Adjustment #6 scope confirmed to include existing literals (`AutoFillView.swift:25,46,102`). |

### Whole-Plan Consistency Sweep (Validation)
- Phase 2 orphan handling reconciled to V1 (no flag) — removed the "unconfirmed marker" success criterion.
- Phase 2 generator reconciled to V2 (bundle wordlist) — resource bundling now a required step + success criterion.
- Phase 1 localization scope reconciled to V4 (existing + new strings).
- No remaining contradictions. `Failed: 0` — plan eligible for implementation.
