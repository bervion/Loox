---
phase: 2
title: Create & save new login from extension
status: completed
priority: P2
effort: 1-1.5d
dependencies:
  - 1
---

# Phase 2: Create & save new login from extension

## Overview

On a web registration form, let the user **create + save a new login** straight from the AutoFill
extension: generate a strong password, prefill site + username/email from the default identity,
confirm in a small editable form, save the encrypted item into the shared vault, and return the
password to fill. Saving requires a new write path (`VaultWriter`) since the extension was read-only.

## Requirements

- Functional:
  - Credential list in `AutoFillView` gains a top row **"＋ Create new login"** (after unlock).
  - Tapping opens `CreateLoginView`:
    - Site/title prefilled from the requesting `serviceIdentifiers` (domain).
    - Username/email prefilled from the **default identity** (email, else name); editable.
    - Password auto-generated (shared `PasswordGenerator`), with regenerate + strength indicator.
    - **Save & fill** button.
  - On save: seal a new `ItemRecord` with the current Vault Key, insert into the shared store
    (`updatedAt = now`), refresh `ASCredentialIdentityStore`, then complete the request with
    `ASPasswordCredential(user, password)` to fill the field.
- Non-functional:
  - Reuse existing crypto/model (DRY) — no new encryption scheme.
  - New item's `updatedAt = now` so CloudKit pull (whole-record LWW by `updatedAt`) picks it up.
  - All new strings localized EN + VI.

## Architecture

**Generator reuse.** Move `Vaultify/Services/PasswordGenerator.swift` →
`VaultifyCore/PasswordGenerator.swift` so both targets compile it. Update any app imports/usages
(same module per target, so likely just the file move + `tuist generate`). Verify no app-only deps.

**Write path (`VaultWriter`, new in VaultifyCore).** Symmetric to `VaultReader`:
- Build an `ItemSecret` (category `.login`, title=site, fields=[username/email, password, url]).
- `AESGCM.seal(JSONEncoder().encode(secret), key: vaultKey)` → `ItemRecord(sealed:..., updatedAt:
  now, createdAt: now, ...)`; insert via `VaultStore()` (same `@MainActor` store the app uses).
- Mirror plaintext columns the schema needs (favorite/pinned/archived defaults, rotateDays 0).
- Keep it minimal: no favicon fetch, no rotation scheduling (the app handles enrichment on next
  open — keeps the extension light + within memory budget).

**Identity prefill.** ⚠️ Superseded by Red Team Adjustment #1 — do NOT filter `logins` for
`isDefaultIdentity` (logins drops identities AND the reader never sets `isDefaultIdentity`). Use a
dedicated `VaultReader.defaultIdentity(vaultKey:)` that skips the password filter and reads
`record.isDefaultIdentity`. Use email if present, else name, for the username default.

**Credential index refresh.** After insert, append an `ASPasswordCredentialIdentity` for the new
item (host from the saved url + username + recordIdentifier=id) via `ASCredentialIdentityStore`
(saveCredentialIdentities, not replace, to avoid clobbering). Mirrors `CredentialIdentityService`.

**Controller wiring.** `CredentialProviderViewController`: the `onSelect` completion already fills;
add an `onSaved`/path so after CreateLoginView saves it calls `complete(user:password:)`.

## Related Code Files

- Create: `VaultifyCore/PasswordGenerator.swift` (moved from `Vaultify/Services/`).
- Create: `VaultifyCore/VaultWriter.swift` (new write path).
- Create: `VaultifyAutoFill/CreateLoginView.swift` (new SwiftUI form).
- Modify: `VaultifyAutoFill/AutoFillView.swift` — "Create new login" entry + navigation.
- Modify: `VaultifyAutoFill/CredentialProviderViewController.swift` — save→fill completion.
- Modify: `VaultifyCore/VaultReader.swift` — `defaultIdentity` helper.
- Modify: `Vaultify/Localizable.xcstrings` — new EN + VI strings.
- Read for context: `Vaultify/Data/Repositories/VaultRepository.swift` (`add` seal pattern),
  `Vaultify/Services/CredentialIdentityService.swift`, `VaultifyCore/Store/ItemRecord.swift`,
  `VaultifyCore/Models/ItemSecret.swift`.
- Delete: `Vaultify/Services/PasswordGenerator.swift` (after move; update references).

## Implementation Steps

1. Move `PasswordGenerator` to `VaultifyCore/`; `tuist generate`; fix app references; compile.
2. Add `VaultReader.defaultIdentity(vaultKey:)` returning the default identity's email/name.
3. Implement `VaultWriter.createLogin(site:username:password:vaultKey:) -> String` (returns new id):
   build `ItemSecret`, seal, insert `ItemRecord` with `updatedAt = now`.
4. Build `CreateLoginView` (site/username/password fields, regenerate, strength, Save & fill);
   localize strings EN + VI.
5. `AutoFillView`: add "＋ Create new login" row → navigate to `CreateLoginView`, pass
   `serviceIdentifiers` + default-identity prefill.
6. On save: call `VaultWriter`, refresh `ASCredentialIdentityStore` (save, not replace), then
   `complete(user:password:)`.
7. `tuist generate` → compile app + extension → fix errors.

## Success Criteria

- [ ] `PasswordGenerator` compiles in both targets; app still uses it (no regression).
- [ ] `VaultWriter.createLogin` seals + inserts an item readable by the app (round-trip decrypt).
- [ ] New item has `updatedAt = now` (survives CloudKit LWW pull).
- [ ] `CreateLoginView` prefills site from domain + username/email from default identity.
- [ ] After save, the field is filled with the generated password.
- [ ] New strings present with EN + VI.

## Risk Assessment

- **Extension writes to SwiftData store** (MED): model must match the app's `ItemRecord` schema
  (shared `VaultifyCore/**` ✓). Mitigation: round-trip test (write in ext path, read via `VaultReader`).
- **Concurrent write app↔extension** (re-rated MED, see Adjustment #5): NOT resolved by `updatedAt`
  LWW (that governs only CloudKit `upsertFromRemote`). Real risk = SQLite lost-update / merge-conflict +
  `VaultStore.init` `fatalError`. Mitigation: recoverable error handling in the write path + app
  re-fetch on foreground. No cross-process lock (YAGNI), but do not claim LWW resolves it.
- **Memory budget** (LOW): generate + single AES-GCM seal is light. No Argon2 here (key already in hand).
- **Identity coupling** (LOW): if no default identity exists, prefill empty — must not crash.

## Red Team Adjustments (2026-06-25)

These corrections supersede any conflicting text above (red-team verified against live code).

1. **Default identity is structurally UNREADABLE by the current reader** (Critical). `VaultReader.logins`
   ends with `.filter { $0.passwordField != nil }` (`VaultReader.swift:33`) → identities (template has no
   `.password`, `ItemCategory.swift:67-76`) are dropped. AND `VaultReader.decrypt` (`:41-48`) constructs
   `VaultItem` **without** `isDefaultIdentity` → always `false` (the marker is a plaintext `ItemRecord`
   column `:40`, not in `ItemSecret`; the app reader passes it at `VaultRepository.swift:266`, the
   extension reader does not). → `VaultReader.defaultIdentity(vaultKey:)` is **real work**: a dedicated
   fetch that (a) does NOT apply the password filter, (b) reads `record.isDefaultIdentity` and threads it
   into `VaultItem`, (c) decrypts the identity's email/name fields. Remove the "filter `isDefaultIdentity`
   on `logins`" wording entirely. Define fallback when zero defaults found (prefill empty, no crash).
2. **Moving `PasswordGenerator` is NOT just a file move** (Critical). `passphrase` loads the EFF wordlist
   via `Bundle.main.url(forResource: "eff_large_wordlist"...)` (`PasswordGenerator.swift:6`); that resource
   is bundled app-only (`Project.swift:77`), and the extension declares no `resources:` (`:120-121`). In the
   extension `Bundle.main` = extension bundle → empty wordlist → empty passphrase.
   → **Decision V2: bundle the wordlist into the extension.** Add `eff_large_wordlist.txt` to the
   extension's `resources:` in `Project.swift` and change `DicewareWordList` to load via the **module
   bundle** (`Bundle(for:)` / `Bundle.module`), NOT `Bundle.main`, so both targets resolve it. Verify
   resource bundling on device (not just source compilation). Passphrase IS exposed in `CreateLoginView`.
3. **`ASCredentialIdentityStore` append gets clobbered** (Critical). The app calls
   `replaceCredentialIdentities` on every `reload()` (`CredentialIdentityService.swift:24`,
   `VaultRepository.swift:54`) and `removeAllCredentialIdentities` on lock (`:33`, `VaultRepository.swift:30`).
   The extension's `saveCredentialIdentities` append survives only until the app's next replace/clear with a
   list that may not yet include the new on-disk item. → The item DATA is safe on disk; the QuickType
   suggestion is best-effort. Guarantee the app does a full `reload()` (re-fetch+decrypt) on
   `willEnterForeground` so the new item is in `items` before the next `replace`. Document the extension
   save as best-effort UX. Also `CredentialIdentityService` is app-target → the extension needs net-new
   `ASCredentialIdentityStore.saveCredentialIdentities([...])`; handle empty-host (skip indexing if the
   user cleared the site field — `autofillHost` needs a non-empty URL, `VaultReader.swift:54-57`).
4. **Extension cannot push to CloudKit — "pull picks it up" is the wrong direction** (High). Sync is
   triggered only from the app (`RootView.swift:35` → `env.syncNow()`); the extension never runs it.
   `ItemRecord.init` defaults `dirty = true` (`ItemRecord.swift:65`) so a push WILL include it — but only
   when the **app** next runs `syncNow`. Risk: a remote `upsertFromRemote` sets `dirty = false`
   (`VaultStore.swift:60`) and could clean the record before any push. → Reframe the success criterion from
   "survives CloudKit pull" to "the app pushes the extension-written `dirty=true` record on next foreground";
   add a step: app triggers `syncNow` after foreground reload detects extension writes.
5. **Two local writers are NOT governed by `updatedAt` LWW** (High). LWW only applies to the CloudKit
   `upsertFromRemote` path (`VaultStore.swift:48`); two `ModelContainer`s (app + extension) on the same
   `SharedConfig.storeURL` (`:18`) writing concurrently is a SQLite-level last-writer/merge-conflict, not
   LWW. `VaultStore.init` `fatalError`s on container failure (`VaultStore.swift:17`) → an extension write
   while the app holds the store can crash the AutoFill UI mid-registration. → The extension write path must
   use **recoverable** error handling (no `fatalError`; abort save gracefully). Re-label the risk as
   lost-update/merge-conflict (not "LWW resolves it"). App must re-fetch on foreground (covered by #3).
6. **Orphan item on fill-cancel / failed registration** (High). Save happens at "Save & fill" tap
   (`CredentialProviderViewController.swift:144` just returns the credential — no success callback); the site
   may reject the registration or the user abandons it → vault accumulates logins with passwords never
   registered → future AutoFill fills a wrong password → lockout. iOS has no public registration-success
   hook. → **Decision V1: save normally, NO flag** (user override of the "unconfirmed marker"
   recommendation). Accept that the vault may accrue junk logins from abandoned signups; the user prunes
   them manually. No metadata marker, no badge, no special UI. The risk is acknowledged and accepted.
7. **`VaultWriter` field/column contract** (Med). Enumerate exactly: build `DynamicField`s with correct
   `FieldKind` (`.username`/`.password`/`.url`, `FieldKind.swift:6-9`) so `usernameField/passwordField/
   urlField` (`VaultItem.swift:79-84`) and `autofillHost` (`VaultReader.swift:54-57`) resolve and the item
   survives the reader's `passwordField != nil` filter. Set `passwordChangedAt = createdAt` (rotation
   baseline, `VaultRepository.swift:115`; nil is tolerated `ItemRecord.swift:35` but be explicit). Set
   favorite/pinned/archived defaults, `rotateDays = 0`. `VaultWriter` must be **independent** of
   `VaultRepository` (app-target, `@MainActor @Observable`, depends on `VaultSession`/`RotationNotification
   Service`/`CredentialIdentityService` — not available to the extension). Do NOT reuse `VaultRepository.add`.

### Added success criteria
- [ ] `VaultReader.defaultIdentity` returns the real default (no password filter; reads `isDefaultIdentity`).
- [ ] `eff_large_wordlist.txt` bundled into the extension; `DicewareWordList` loads via module bundle (not `Bundle.main`); passphrase non-empty in the extension on device.
- [ ] Saved item has `passwordField != nil` (survives reader filter) + correct `FieldKind`s.
- [ ] Extension write path has no `fatalError`; save failure aborts gracefully.
- [ ] App `reload()` on `willEnterForeground` surfaces extension-created items + triggers `syncNow`.
<!-- Updated: Validation Session 1 - V1 (no flag), V2 (bundle wordlist) -->
- [ ] Extension-created items saved normally (Decision V1 — no "unconfirmed" flag).
