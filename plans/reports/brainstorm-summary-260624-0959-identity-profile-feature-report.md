# Brainstorm Summary — Identity & Profile Feature

**Date:** 2026-06-24 · **Branch:** main · **Status:** design approved (pending plan)

## Problem statement
Mandatory user identity at first run. Profile page (avatar, default identity, payment cards).
Quick-use of identity data when filling info on websites. Zero-backend, on-device, iCloud-syncable.

## Decisions (confirmed)
- **Autofill (phase 1) = manual copy.** iOS `ASCredentialProviderExtension` (passwords/passkeys/OTP only)
  cannot auto-fill name/address/card into 3rd-party web forms. Profile exposes per-field copy buttons
  (clipboard auto-clear via existing `clipboardClearSeconds`). Auto web-fill deferred (future: in-app
  browser or iOS18 insert-text).
- **Data model = reuse `ItemCategory.identity` vault item** (no new entity). Extend `.identity`
  field template. Cards stay `.card` items.
- **Default identity = SYNCED item metadata, NOT local setting.** Add plaintext column
  `isDefaultIdentity: Bool` to `ItemRecord` (mirrors `pinned`/`archived` pattern). Reason:
  `SettingsStore`/UserDefaults is device-local & not in CloudSync; a local pointer breaks multi-device.
  Marker-on-item also avoids dangling pointers (delete item → marker gone). Chose Bool over
  `profileRole: String?` (YAGNI).
- **Profile entry = avatar in Home header** (`HomeHeaderBar`), opens `ProfileScreen` child.
- **Mandatory ≥1 active identity:** onboarding creates one; block trashing/archiving the last active
  identity; auto-promote a new default when the current default leaves active set.

## Verified integration points (file:line)
- `ItemRecord` columns + sync-metadata pattern: `VaultifyCore/Store/ItemRecord.swift:23,25,32`
- CloudKit push map: `Vaultify/Services/Sync/CloudSyncService.swift:108-119`
- CloudKit pull map: `Vaultify/Services/Sync/CloudSyncService.swift:123-135`
- `VaultItem` mirror + `toItem`: `VaultifyCore/Models/VaultItem.swift`; `VaultRepository.swift:212`, write-back `:67-70`
- Identity field template: `VaultifyCore/Models/ItemCategory.swift:67`
- Mutators to guard: `VaultRepository.swift` archive `:120`, moveToTrash `:147`, delete `:161`, emptyTrash `:199`
- Onboarding step insertion: `Vaultify/Features/Onboarding/OnboardingFlow.swift`
- Avatar storage reuse: `Vaultify/Services/AttachmentStore.swift` (AES-GCM blob in App Group)
- Home header: `Vaultify/Features/Home/Components/HomeHeaderBar.swift`

## Solution design

### Data
- Extend `.identity` `fieldTemplate`: Full Name, Email, Phone, Address(multiline), Date of Birth,
  ID Number(protected). (Affects new items only; legacy items unaffected — safe decode already present.)
- Add `isDefaultIdentity: Bool = false` to `ItemRecord`; mirror on `VaultItem`; map in upsert/toItem;
  add to CloudKit push+pull.

### Default-identity invariant (app-enforced, single active)
- `activeIdentities = items.filter { $0.category == .identity && !archived && !trashed }`
- Setting default: set chosen item true, clear others, mark dirty.
- Block move-to-trash / archive of the LAST active identity (`PolarisModal.info`).
- If current default leaves active set (trash/archive/delete): promote another active identity.
- Permanent delete: marker removed with the record; if it was default → promote.
- **Conflict normalize** after `reload()`: if >1 active identity is default → keep latest `updatedAt`,
  clear rest, mark dirty so next sync converges.

### Onboarding
- New step "What should we call you?" → create identity (title = display name, Full Name = display name,
  editable later), mark `isDefaultIdentity = true`. Best-effort (like "My Vault" folder seed).

### Profile UI
- Circular avatar in `HomeHeaderBar` → `ProfileScreen` (child).
- `ProfileScreen`: large avatar + change (PhotosPicker→crop→`AttachmentStore`, `Avatars/<itemId>.blob`);
  default-identity fields with per-field copy buttons; default switcher across identities;
  "Payment cards" section listing `.card` items (tap→`ItemEditorScreen`); Edit→`ItemEditorScreen`.
- Avatar shown post-unlock only (Home is unlocked) — in-memory decrypt OK.

## Phasing
1. **Data + onboarding + invariant:** new column + sync map + mirror; extend template; onboarding step;
   last-identity guards + default normalize. (Pure logic — strong TDD candidate.)
2. **Profile + avatar UI:** HomeHeaderBar avatar, `ProfileScreen`, avatar upload, copy buttons,
   default switcher, cards section.
3. *(Future)* Auto web-fill (in-app browser / iOS18 insert-text). Out of scope now.

## Risks
- Template change affects only new identities; pre-existing identity items lack new fields (acceptable).
- CloudKit conflict ping-pong if `updatedAt` ties on default normalize — last-writer-wins deterministic enough.
- New strings (onboarding step, ProfileScreen, last-identity modal) MUST be EN+VI localized.
- Avatar requires App-Group blob + Vault Key (unlocked); fine for Home/Profile (post-unlock).

## Success criteria
- First run forces creation of exactly one default identity.
- Default identity persists & converges across devices via CloudKit (single default after sync).
- Cannot trash/archive the last active identity; default auto-promotes otherwise.
- Profile shows default identity + avatar + cards; per-field copy works with clipboard auto-clear.

## Out of scope (this round)
- Automatic web form filling; per-identity card ownership/linking; multiple profile roles.

## Open questions
- None blocking. (Confirm Bool vs `profileRole`: recommended Bool.)
