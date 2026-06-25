---
phase: 1
title: Data Model & Sync Column
status: completed
priority: P1
effort: 1d
dependencies: []
---

# Phase 1: Data Model & Sync Column

## Overview
Add synced columns to the item store and mirror onto `VaultItem`; extend the `.identity` field
template. Foundation for the default-identity invariant, sync convergence, avatar, and Profile UI.

New `ItemRecord` columns (all synced):
- `isDefaultIdentity: Bool = false` — the default-identity marker.
- `avatarSealed: Data? = nil` — **AES-GCM-sealed downscaled avatar JPEG** (F4 = avatar must sync).
  Stored on the record so it syncs like `sealed` (zero-knowledge; iCloud sees ciphertext only) and is
  removed automatically when the record is deleted (no orphan cleanup needed).

**Sync gate note (F1 final):** `VaultStore.upsertFromRemote` reconciles whole-record LWW by `updatedAt`
(`guard updatedAt > existing.updatedAt`). So any synced mutation MUST bump `updatedAt` or it is dropped
on pull. Therefore `setDefaultIdentity`/`setAvatar` (Phases 2/4) bump `updatedAt`; the once-considered
`defaultIdentitySetAt` tie-break column is DROPPED as redundant (`updatedAt` now tracks the default
change and serves as the normalize tie-break).

## Requirements
- Functional: the two columns persist, round-trip add/update/reload, and are in the CloudKit push/pull
  map. `isDefaultIdentity` mirrors to `VaultItem`. Avatar bytes do NOT bloat `VaultItem` — exposed via a
  repo accessor (decode on demand, Phase 4). `.identity` template carries Profile fields.
- Non-functional: SwiftData lightweight migration safe (all columns defaulted/optional); marker read
  needs no re-seal; avatar JPEG sealed at rest with the Vault Key; CKRecord stays well under 1MB
  (256px JPEG sealed ≈ 20–60KB). No breakage of legacy sealed items.

## Architecture
- `isDefaultIdentity` is a low-sensitivity column (reveals only "this item is the chosen identity"),
  consistent with the existing plaintext-column model in `ItemRecord` (`sealed` holds content only).
- Mutation is column-only (no re-seal, no `updatedAt` bump) via the existing `setColumn` contract,
  EXCEPT where set-default must converge across devices — there we mark `dirty` so sync propagates.

## Related Code Files
- Modify: `VaultifyCore/Store/ItemRecord.swift` — add `isDefaultIdentity: Bool = false`,
  `avatarSealed: Data? = nil`.
- Modify: `VaultifyCore/Models/VaultItem.swift` — add `isDefaultIdentity` (init param defaulted);
  metadata, NOT part of `ItemSecret` (do not seal). Avatar bytes NOT added here.
- Modify: `Vaultify/Data/Repositories/VaultRepository.swift` — set `isDefaultIdentity` in `add`
  (write-back ~`:67`) and read in `decrypt`→`VaultItem(...)` (~`:212`). `update` re-seal path leaves
  the new columns untouched (not in `ItemSecret` → survive). Avatar accessors land in Phase 4 extension.
- Modify: `VaultifyCore/Store/VaultStore.swift` — `upsertFromRemote` signature/body: add
  `isDefaultIdentity: Bool` and `avatarSealed: Data?` params; set on both existing+new branches.
- Modify: `Vaultify/Services/Sync/CloudSyncService.swift` — push `ckRecord(from:)` (~`:108-119`):
  `ck["isDefaultIdentity"] = (record.isDefaultIdentity ? 1 : 0)`,
  `ck["avatarSealed"] = record.avatarSealed` (if non-nil; Data field, not CKAsset). Pull `apply(_:)`
  (~`:123-135`): read both and pass into `upsertFromRemote`.
- Modify: `VaultifyCore/Models/ItemCategory.swift` (~`:67`) — extend `.identity` `fieldTemplate`:
  Full Name(text), Email(email), Phone(**text** — not `.number`; numberPad can't type `+`/spaces),
  Address(multiline), Date of Birth(date), ID Number(monospace, protected).
- Create (test): `VaultifyTests/IdentityDataModelTests.swift`.

## Implementation Steps
1. **Tests first** (`IdentityDataModelTests`, XCTest, `@MainActor`, in-memory repo per
   `VaultRepositoryFolderTests.makeRepo()`):
   - `testDefaultMarkerDefaultsFalseOnAdd` — add `.identity` item → reloaded item `isDefaultIdentity == false`.
   - `testDefaultMarkerPersistsThroughReload` — set column true via repo set-default (Phase 2 API may
     not exist yet → in this phase test the raw column: fetch record, set `isDefaultIdentity = true`,
     save, `reload()`, assert mirrored on `VaultItem`).
   - `testUpdatePreservesDefaultMarker` — mark true, then `update(item)` (re-seal path) → marker still true.
   - `testAvatarSealedColumnRoundTrips` — write `avatarSealed` bytes, save, reload record → identical bytes.
   - `testIdentityTemplateHasProfileFields` — `ItemCategory.identity.fieldTemplate` contains email,
     phone, address, DOB kinds.
2. Add the two columns to `ItemRecord` (defaulted/optional).
3. Add `isDefaultIdentity` to `VaultItem` + init; map in `decrypt` and `add`.
4. Add CloudKit push/pull lines + `upsertFromRemote` params for both columns.
5. Extend `.identity` template; add any new EN+VI strings for new field default labels if surfaced.
6. Run tests + `make check` (compile app + extension).

## Success Criteria
- [ ] New tests pass (`make test DEST=...` — needs concrete sim UDID per project memory).
- [ ] `make check` green (app + AutoFill extension compile).
- [ ] Both columns round-trip add→reload and survive `update` re-seal.
- [ ] CloudKit map references both keys in push, pull, and `upsertFromRemote`.
- [ ] `.identity` template exposes Profile fields; legacy identity items still decode.

## Risk Assessment
- SwiftData migration: defaulted Bool is additive → lightweight migration safe. Mitigate by verifying
  an existing on-disk store opens (manual smoke / existing tests).
- CloudKit map is gated by `VAULTIFY_ICLOUD` + CloudKit types → not unit-testable here; verify by code
  review + the 1-line symmetry of push/pull. Note honestly in PR.
