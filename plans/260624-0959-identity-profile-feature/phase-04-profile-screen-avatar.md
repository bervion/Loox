---
phase: 4
title: "Profile Screen & Avatar"
status: pending
priority: P2
effort: "1.5d"
dependencies: [1, 2, 3]
---

# Phase 4: Profile Screen & Avatar

## Overview
Surface the default identity: avatar entry in the Home header → `ProfileScreen` with avatar upload,
default-identity switch, per-field copy, and a payment-cards section. Wire the removal gate from Phase 2.

## Requirements
- Functional:
  - **Zero-identity empty state (REQUIRED):** when `defaultIdentity == nil` (existing TestFlight users
    with no identity, post-import, post-restore), Home avatar + `ProfileScreen` show a "Create your
    identity" CTA routing to the identity editor/seed. Do NOT assume a default always exists.
  - Circular avatar button in `HomeHeaderBar` opens `ProfileScreen` (child).
  - `ProfileScreen` shows default identity (large avatar + title), per-field rows with copy buttons
    (clipboard auto-clear via existing setting), a switcher to pick the default among `activeIdentities`,
    an "Edit" action opening `ItemEditorScreen`, and a "Payment cards" section listing `.card` items
    (tap → view/edit; add → new `.card`).
  - Avatar change via PhotosPicker → crop → **downscale ≤256px JPEG → seal → write `avatarSealed`
    column** (Phase 1) → syncs cross-device. Remove avatar = set column nil. Display = decode on demand.
  - Trash/archive of the last active identity is blocked with `PolarisModal.info` (uses Phase 2 gate).
- Non-functional: DS tokens only (no hardcoded constants); Polaris SVG icons; light/dark + Reduce
  Transparency/Motion verified; 44pt targets; all strings EN + VI; avatar decrypt in-memory (post-unlock).

## Architecture
- **Avatar = `ItemRecord.avatarSealed` column** (Phase 1), NOT a separate blob store. Pipeline:
  PhotosPicker → crop (optional) → downscale to ≤256px → JPEG encode → `AESGCM.seal` with Vault Key →
  write column (dirty → syncs). Reuse existing seal/unseal; do NOT invent crypto, do NOT use CKAsset.
- **Syncs cross-device** (column rides the item's CKRecord as a Data field; zero-knowledge preserved —
  iCloud sees ciphertext). **No orphan cleanup needed** — column dies with the record (F3 resolved).
- Repo accessors (in `VaultRepository+Avatar.swift`):
  `func setAvatar(_ data: Data?, for id: String)` (seal + write column + **bump `updatedAt` so it syncs**
  + dirty + reload) and `func avatarImage(for id: String) -> UIImage?` (unseal+decode; cache in the
  view). Keep file <200 LoC.
- Fallback = existing letter-avatar from title when `avatarSealed == nil`.
- `ProfileScreen` is a child screen — follow existing pushed-screen nav (match `ItemDetail`/Settings;
  native SwiftUI app, not Polaris-Flutter — use the app's own header/back conventions).

## Related Code Files
- Create: `Vaultify/Features/Profile/ProfileScreen.swift`
- Create: `Vaultify/Features/Profile/ProfileAvatarView.swift` (avatar + PhotosPicker + crop + downscale)
- Create: `Vaultify/Data/Repositories/VaultRepository+Avatar.swift` — `setAvatar`/`avatarImage` (seal/
  unseal the `avatarSealed` column). Keep <200 LoC.
- Modify: `Vaultify/Features/Home/Components/HomeHeaderBar.swift` — add avatar button + navigation.
- Modify: `Vaultify/Features/Home/HomeScreen.swift` — add Profile to nav destinations if needed.
- Modify item removal call sites (swipe/menu trash + archive) to consult `identityRemovalGate` and show
  `PolarisModal.info` when `.lastActiveIdentity` (likely `ItemDetail` + any list swipe actions).
- Modify: `Localizable.xcstrings` — Profile strings, last-identity modal, copy toasts (EN + VI).
- Create (test): `VaultifyTests/ProfileAvatarTests.swift`.

## Implementation Steps
1. **Tests first** (where logic allows; `@MainActor`, `makeRepo()` harness):
   - `testSetAvatarRoundTrips` — `setAvatar(data, for: id)` then `avatarImage(for: id)` decodes a
     non-nil image; `setAvatar(nil,...)` → `avatarImage == nil`.
   - `testAvatarSealedAtRest` — the persisted `avatarSealed` column bytes != the plaintext JPEG bytes
     (confirms AES-GCM seal).
   - `testAvatarMarksDirty` — `setAvatar` sets `record.dirty == true` (so it syncs).
   - `testDownscaleCapsDimension` — downscale helper caps the longest side ≤256px.
2. Implement `VaultRepository+Avatar` (`setAvatar`/`avatarImage`) + a pure downscale/JPEG helper.
3. Build `ProfileAvatarView` (PhotosPicker → crop → downscale → setAvatar; letter-avatar fallback).
4. Build `ProfileScreen` (identity fields + copy, default switcher, cards section, Edit).
5. Add avatar button to `HomeHeaderBar` + navigation to `ProfileScreen`.
6. Wire removal gate + `PolarisModal.info` at trash/archive call sites.
6b. Implement zero-identity empty state (Home avatar + ProfileScreen) → "Create identity" CTA.
6c. Hide default-switcher when only 1 active identity; per-field copy works on protected fields too
    (reuse ItemDetail reveal+copy honoring `clipboardClearSeconds`).
7. Add EN+VI strings; run `tuist generate` (new files) + `make check`; manual UI verify
   (light/dark/Reduce Transparency/Reduce Motion; theme switch leaves nothing invisible).

## Success Criteria
- [ ] Avatar tests pass; `avatarSealed` encrypted at rest; `setAvatar` marks dirty (syncs).
- [ ] Profile opens from Home header; shows default identity; switch default works and persists.
- [ ] Avatar set on one device appears on another after sync (manual / documented).
- [ ] Zero-identity empty state shows "Create identity" CTA (covers existing TestFlight users).
- [ ] Per-field copy works with clipboard auto-clear (incl. protected fields).
- [ ] Payment cards section lists `.card` items; add/edit routes to `ItemEditorScreen`.
- [ ] Trashing/archiving the last active identity is blocked with a localized modal.
- [ ] DS-compliant; EN+VI complete; `make check` green; new files added via `tuist generate`.

## Risk Assessment
- New files invisible until `tuist generate` (globbed sources) — run before building.
- CKRecord size: keep avatar ≤256px JPEG so sealed bytes stay well under the 1MB CKRecord field limit;
  reject/recompress if oversized.
- `TextField`/`SecureField` with `LocalizedStringResource` title is iOS 26+ → use `LocalizedStringKey`
  (deployment target 17.6). Watch for other 17.6 API ceilings.
- Avatar decrypt requires unlocked vault — Profile is post-unlock, fine; guard nil gracefully.
- Removal gate must be wired at ALL trash/archive entry points (detail + list swipe) or the invariant
  leaks; enumerate call sites during implementation.
- Keep `ProfileScreen` composed from existing components; do not invent new visual language.
