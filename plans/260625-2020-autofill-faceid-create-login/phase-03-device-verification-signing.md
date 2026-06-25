---
phase: 3
title: "Device verification & signing"
status: pending
priority: P1
effort: "0.5d"
dependencies: [1, 2]
---

# Phase 3: Device verification & signing

## Overview

The shared Keychain Access Group entitlement (Phase 1) changes signing. This phase verifies on a
**real device** that both targets sign + run with the new entitlement, and that the end-to-end
Face ID + Create-login flows work. Cannot be validated on simulator (entitlement/provisioning is
no-op there) or by compile alone.

## Requirements

- Functional (device):
  - Extension unlocks via **Face ID** (not master password) when biometric enrolled; fallback works.
  - Create-login flow saves an item visible in the app afterward with correct site/username/password.
- Non-functional:
  - Signed build (app + embedded extension) succeeds with the new `keychain-access-groups`.
  - fastlane `match` profiles include the Keychain Sharing capability for both bundle IDs.

## Architecture

No new code. Verification + provisioning reconciliation:
- Apple Developer portal: enable Keychain Sharing (group `com.bervion.vaultify.shared`) on both
  App IDs (`com.bervion.vaultify`, `com.bervion.vaultify.autofill`).
- `match`: regenerate/refresh provisioning profiles so both include the capability.
- Local signed run on device (Xcode) to confirm no entitlement mismatch crash at launch.

## Related Code Files

- Read/verify: `Vaultify/Vaultify.entitlements`, `VaultifyAutoFill/VaultifyAutoFill.entitlements`,
  `Project.swift`, `fastlane/Matchfile` / `fastlane/Fastfile`, `docs/deployment-guide.md`.

## Implementation Steps

1. Portal: add Keychain Sharing group to both App IDs.
2. `match` (development + appstore as used) → refresh profiles; confirm capability present.
3. `tuist generate` → run on a real iPhone via Xcode (signed).
4. Manual checks: (a) tap a password field in Safari → Face ID unlock; (b) "Create new login" →
   save → reopen app → item present & correct.
5. If CI release path affected, dry-run the tag→Actions signing (or confirm runner profiles) per
   `docs/deployment-guide.md`. Update the doc if steps changed.

## Success Criteria

- [ ] Signed device build of app + extension succeeds with the new entitlement.
- [ ] Face ID unlock works in the extension on device; master-password fallback intact.
- [ ] Create-login saves an item the app reads back correctly.
- [ ] `match` profiles include Keychain Sharing for both bundle IDs.
- [ ] `docs/deployment-guide.md` updated if the signing steps changed.

## Risk Assessment

- **Profile drift / CI signing failure** (HIGH if skipped): the whole point of this phase. Catch
  before merge to `main` (release tags auto-build on the self-hosted runner).
- **Device-only bugs**: biometric Keychain behaves differently than simulator → this phase is the
  only place these surface. Do not skip.

## Red Team Adjustments (2026-06-25)

1. **Rollback runbook for a broken release tag** (High). The `keychain-access-groups` entitlement lives
   in committed `.entitlements`; the release path is `tag v* → self-hosted runner → match → TestFlight`
   (CLAUDE.md). If `match` profiles lack the Keychain Sharing capability when a tag lands, the signed build
   fails **after** the tag exists. Add an explicit runbook: (a) gate merge to `main` on a **dry-run signed
   build on the self-hosted runner** (not just a local Xcode device run — local does not prove the runner's
   match cache); (b) `match nuke`/regenerate sequence if profiles are stale; (c) documented revert =
   revert the entitlement commit + delete the bad tag + confirm the prior tag still builds.
2. **Shared-group runtime self-test before device flows** (High). Before the manual Face ID test, run a
   write+read round-trip against the **team-prefixed** shared access group on device to catch
   `errSecMissingEntitlement (-34018)` early (distinguishes "entitlement/prefix wrong" from "not enrolled").
3. **Distinguish biometric failure modes** (Med). The device test must separate "not enrolled" vs
   "shared-group retrieve failed under the extension's `LAContext`" (log the OSStatus) — the fallback must
   not silently mask `errSecItemNotFound`/`errSecMissingEntitlement` as "no biometrics".
4. **Memory-budget test with a large vault** (Med). Seed hundreds of items, then in the extension: open
   picker (`VaultReader.logins` decrypts the whole table) → "Create new login" → save. Confirm no jetsam
   mid-write. If tight, switch the writer to a lightweight `FetchDescriptor` (fetchLimit/propertiesToFetch)
   instead of the full-table read path.
5. **Localization on device** (from Phase 1 #6). Verify the extension renders **VI** strings when the in-app
   language is Vietnamese (catalog bundled into the extension + `appResourceLocale` set from App Group).

### Added success criteria
- [ ] Dry-run signed build succeeds on the **self-hosted runner** before the first real release tag.
- [ ] On-device shared-group keychain write+read round-trip passes (prefix correct).
- [ ] Large-vault create-login completes with no jetsam.
- [ ] Extension shows VI strings under the in-app Vietnamese setting.
