---
phase: 1
title: Face ID unlock in extension
status: completed
priority: P1
effort: 0.5-1d
dependencies: []
---

# Phase 1: Face ID unlock in extension

## Overview

Let the AutoFill extension unlock with **Face ID (1 tap)** instead of the master password.
Enabled by a **shared Keychain Access Group** so the extension can read the biometric-gated
Vault Key the app already stores via `BiometricKeyStore`. Master password stays as fallback.

## Requirements

- Functional:
  - Extension `AutoFillView`: on appear, if a biometric key is provisioned → prompt Face ID →
    on success use the returned Vault Key, skip master-password form, go straight to the list.
  - Fail / cancel / not-enrolled / biometric error → show master-password form (current behavior).
  - App writes the biometric Vault Key into the **shared** keychain group so the extension reads it.
  - Silent migration: existing app-only biometric key re-provisioned into the shared group via a
    **one-time** `migrateBiometricKeyToSharedGroupIfNeeded()` (guarded by a settings flag) — NOT on
    every unlock. Must delete the old default-group copy. See Red Team Adjustments #3 (the prose
    below about "finding the success site" / "store deletes first" is superseded — that site does
    not exist; the migration is net-new code).
- Non-functional:
  - Keep zero-knowledge: key item stays `WhenUnlockedThisDeviceOnly`, `.biometryCurrentSet`,
    **not** iCloud-synced.
  - Biometric path must NOT run Argon2 (fast + low memory for the extension memory budget).
  - All new strings localized EN + VI.

## Architecture

**Keychain sharing.** Today `KeychainStore` items use only `kSecAttrService` (no access group),
so each process (app vs `...autofill`) sees its own default keychain group → extension can't read
the app's biometric key. Fix: introduce a shared access group and tag the biometric key item with it.

- Shared group id: `$(AppIdentifierPrefix)com.bervion.vaultify.shared` (team-prefixed at runtime;
  in entitlements declared as `com.bervion.vaultify.shared`, system prepends the team prefix).
- `KeychainStore`: add an optional `accessGroup` parameter to `set` / `get` / `delete`
  (default `nil` = unchanged for all existing callers — DRY, no behavior change elsewhere).
- `BiometricKeyStore`: use the shared group for the `vault.biometricKey` item in `store` /
  `retrieve` / `isEnrolled` / `delete` (add `kSecAttrAccessGroup`). Both targets compile this
  (already in `VaultifyCore/**`).

**Extension unlock flow** (`AutoFillView`):
- Add a `biometricUnlocking` state. On `.task`/`.onAppear`, if `BiometricKeyStore.isEnrolled`
  → call `BiometricKeyStore.retrieve(reason:)` off-main → success: set `items =
  VaultReader.logins(vaultKey:)`, `unlocked = true`. Failure → reveal `unlockForm`.
- Master-password path unchanged (Argon2 fallback).

**App provisioning / migration.** Find where the app currently calls `BiometricKeyStore.store`
(biometric enable in onboarding `EnableBiometricView` / Settings / `VaultSession`). After the
`accessGroup` change, new stores land in the shared group automatically. For already-enrolled
users: on the next successful in-app biometric unlock, re-`store` the key (now into the shared
group) — idempotent (`store` deletes first). No UI change.

## Related Code Files

- Modify: `VaultifyCore/Keychain/KeychainStore.swift` — optional `accessGroup` param.
- Modify: `VaultifyCore/Keychain/BiometricKeyStore.swift` — tag item with shared group.
- Modify: `VaultifyAutoFill/AutoFillView.swift` — auto biometric unlock path + fallback.
- Modify: `Vaultify/Vaultify.entitlements` — add `keychain-access-groups`.
- Modify: `VaultifyAutoFill/VaultifyAutoFill.entitlements` — add `keychain-access-groups`.
- Modify: `Project.swift` — (only if entitlements are inline; here they are file-based, so verify
  both `.entitlements` are referenced — they are). No source-glob change (no new files).
- Read for context: `Vaultify/Security/VaultSession.swift`, `Vaultify/Features/Unlock/LockScreen.swift`,
  `Vaultify/Features/Onboarding/EnableBiometricView.swift`, `VaultifyCore/VaultReader.swift`.

## Implementation Steps

1. `KeychainStore`: add `accessGroup: String? = nil` to `set`/`get`/`delete`; when non-nil add
   `kSecAttrAccessGroup` to the query dicts. Existing callers unaffected (default nil).
2. Add `SharedConfig.keychainAccessGroup = "com.bervion.vaultify.shared"` constant (single source).
3. `BiometricKeyStore`: pass `SharedConfig.keychainAccessGroup` on store/retrieve/isEnrolled/delete.
4. Entitlements: add to BOTH files:
   ```xml
   <key>keychain-access-groups</key>
   <array><string>$(AppIdentifierPrefix)com.bervion.vaultify.shared</string></array>
   ```
5. Apple Developer portal: ensure the App ID(s) allow the Keychain Sharing group; update fastlane
   `match` provisioning so both app + extension profiles include it. (Verified for real in Phase 3.)
6. `AutoFillView`: add biometric auto-unlock on appear with master-password fallback; localize any
   new strings (e.g. Face ID reason) EN + VI in `Localizable.xcstrings`.
7. App migration: at the in-app biometric unlock success site, re-`store` the Vault Key (now shared).
8. `tuist generate` → compile app + extension (workspace) → fix errors.

## Success Criteria

- [ ] Extension compiles; `BiometricKeyStore` reads/writes the shared-group item.
- [ ] Simulator/compile: `AutoFillView` shows biometric path when enrolled, master-password form otherwise.
- [ ] No iCloud-sync attribute on the key item; still `.biometryCurrentSet` + `ThisDeviceOnly`.
- [ ] New strings present with EN + VI values.
- [ ] (Device, deferred to Phase 3) Face ID prompt appears in the extension and unlocks.

## Risk Assessment

- **Provisioning/signing breakage** (HIGH): adding a keychain group requires portal + match update;
  a stale profile fails the CI signed build. Mitigation: Phase 3 device/signing gate before merge;
  keep the entitlement value exact.
- **Migration gap**: users who never re-unlock in-app keep the old app-only key → extension Face ID
  silently unavailable, falls back to master password (acceptable, not a regression). Mitigation:
  re-store on next unlock covers them; document.
- **`.biometryCurrentSet` invalidation**: if biometrics changed, retrieve fails → fallback path. OK.

## Red Team Adjustments (2026-06-25)

These corrections supersede any conflicting text above (red-team verified against live code).

1. **`accessGroup` on `KeychainStore.set/get` alone is a NO-OP for this feature** (Critical).
   `BiometricKeyStore.isEnrolled/store/retrieve` build their queries **inline**
   (`BiometricKeyStore.swift:15-26,34-40,49-55`) and never route through `KeychainStore.set/get`.
   → Add `kSecAttrAccessGroup` directly to **all four** inline queries (isEnrolled, store, retrieve,
   and the delete path via `KeychainStore.delete` `:73` — which must also forward the group).
2. **Runtime access-group string MUST be team-prefixed** (High). Entitlement uses
   `$(AppIdentifierPrefix)com.bervion.vaultify.shared`; the runtime `kSecAttrAccessGroup` value must be
   `WDNL2F75V7.com.bervion.vaultify.shared` (NOT the bare suffix — that yields `errSecMissingEntitlement`
   `-34018`). Keychain-access-group format ≠ App-Group format (`group.com...`, no prefix). Provide the
   prefixed value from `SharedConfig` (compose at runtime; team id `WDNL2F75V7` per CLAUDE.md).
3. **The "re-store on next unlock" migration site does NOT exist** (Critical). `store` is called only in
   `enableBiometricUnlock` (`VaultSession.swift:117`); `unlock`/`unlockWithBiometrics` only call
   `adoptUnlocked` (`:151`) and never re-store; `unlockWithBiometrics` zeroes the key bytes (`:98`).
   → Add an explicit `migrateBiometricKeyToSharedGroupIfNeeded()` that runs **once** (guarded by a
   `settings` flag) after a successful in-app unlock when biometric is enrolled. It must: read the OLD
   default-group item, write into the shared group, then **delete the old default-group item**
   (`BiometricKeyStore.delete` currently queries with no group → old copy is orphaned otherwise = raw
   Vault Key left in two groups). Mitigate crash window (write-new before delete-old). Do NOT re-store on
   every unlock (keychain churn + lockout window).
4. **Cross-group `isEnrolled` TOCTOU + fallback** (Med). After flipping queries to the shared group, the
   pre-migration item is invisible → `isEnrolled` may be false / `retrieve` may throw. `AutoFillView` MUST
   reveal `unlockForm` on **ANY** `BiometricKeyStore` error (cancel, `.store(status)`, unavailable), not
   just `.cancelled`; on `errSecItemNotFound` clear stale enrollment so the next attempt skips biometrics.
5. **`provideCredentialWithoutUserInteraction` invariant** (High). It currently returns
   `userInteractionRequired` (`CredentialProviderViewController.swift:39-45`). Add a non-functional
   requirement: it MUST keep returning `userInteractionRequired` — biometric unlock is interactive-only,
   no silent-fill path. Add a success criterion asserting this.
6. **Localization does not reach the extension** (High). `Localizable.xcstrings` is bundled app-only
   (`Project.swift:75`); the extension target declares no `resources:` (`:120-121`), and `String(localized:)`
   resolves the **main bundle** = the extension bundle (no catalog) → new AND existing `AutoFillView`
   strings render English keys regardless of the user's VI choice. → Add `Vaultify/Localizable.xcstrings`
   to the extension's `resources:` in `Project.swift`, and set `appResourceLocale` from the App-Group
   `UserDefaults` (the catalog is shared; `ThemeReader` already reads `SharedConfig.appGroup`) on extension
   launch. Treat localization as a **wiring** task, not just a catalog edit.
7. **Stale comment** (Low). `SharedConfig.swift:5-6` says "no shared-Keychain access group required" —
   update it: still true for the ciphertext key-bundle, but the **biometric** Vault Key now uses a shared
   group. Note: the shared group is unavoidable for extension biometric unlock (App Group can't share
   keychain) — the `wrappedByBiometric`-in-bundle alternative still needs a shared-group SE key, so it was
   rejected; keep the existing raw-key-gated-by-biometric pattern.

<!-- Updated: Validation Session 1 - V3 (silent migration confirmed), V4 (fix existing + new strings) -->
**Validation decisions:** V3 — migration is silent on next in-app unlock (no prompt; extension Face ID
falls back to master password until then). V4 — the localization wiring (#6) must fix the **existing**
`AutoFillView` strings (`:25,46,102`) too, not just new ones.

### Added success criteria
- [ ] `isEnrolled`/`store`/`retrieve`/`delete` all carry the **team-prefixed** shared access group.
- [ ] One-time migration moves the key to the shared group and deletes the old default-group copy
      (assert exactly one `vault.biometricKey` item post-migration).
- [ ] `provideCredentialWithoutUserInteraction` still returns `userInteractionRequired`.
- [ ] Extension renders VI strings (catalog bundled + `appResourceLocale` set from App Group).
