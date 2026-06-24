---
phase: 2
title: "Default-Identity Invariant"
status: pending
priority: P1
effort: "1d"
dependencies: [1]
---

# Phase 2: Default-Identity Invariant

## Overview
Pure-logic core: maintain exactly one active default identity, enforce ≥1 active identity at mutation
gates, auto-promote on removal, and normalize sync conflicts. Strongest TDD target.

## Requirements
- Functional:
  - `defaultIdentity` resolves to the single active `.identity` item marked default (nil if none).
  - `setDefaultIdentity(_:)` sets chosen true, clears all other identities, marks `dirty`, reloads.
  - Trash/archive of the LAST active identity is blocked (gate returns a blocking result for UI).
  - When the current default leaves the active set (trash/archive/delete), another active identity is
    promoted to default.
  - `normalizeDefaultIdentity()` after `reload()`: if >1 active default → keep tie-break winner (rule
    below), clear the rest (set their `isDefaultIdentity=false`, leave their `defaultIdentitySetAt` as-is),
    mark dirty; if 0 active default but ≥1 active identity → promote the tie-break winner (bump its
    `updatedAt=.now` so the choice propagates). **If 0 active identities → leave
    `defaultIdentity == nil`; NEVER fabricate an identity** (UI shows a zero-identity empty state — Phase 4).
  - `setDefaultIdentity(_:)` sets `isDefaultIdentity = true` on the chosen item and `false` on all other
    identities, **bumps `updatedAt = .now` on every identity whose flag changed** (required so the change
    syncs — see F1), marks them dirty, reloads. **Asserts/guards `item.category == .identity`**.
- Non-functional: no reload recursion (normalize patches in-memory + saves columns, **must NOT call
  `reload()`**); writes are column + `updatedAt` only (no re-seal).

### F1 — sync tie-break (FINAL = updatedAt)
`VaultStore.upsertFromRemote` is whole-record LWW by `updatedAt`, so a synced change MUST bump
`updatedAt` or it is dropped on pull. `setDefaultIdentity`/`setAvatar` bump `updatedAt`; thus `updatedAt`
DOES track the default change and is the tie-break key. **Winner rule** wherever normalize/promote picks
among active identities: `max(updatedAt)`; final tie → `max(createdAt)`. (The separate
`defaultIdentitySetAt` column was dropped as redundant.) Cost: changing default/avatar floats the
identity up "Recently Modified" — accepted (rare action).

## Architecture
- New extension file keeps `VaultRepository.swift` lean (<200 LoC guidance).
- `items` already excludes trashed AND archived (see `reload()`), so
  `activeIdentities = items.filter { $0.category == .identity }`.
- Removal gate is UI-facing (the only realistic mutation paths are trash/archive actions). A defensive
  check also lives in the repo. Backup/import bulk paths are not gated (acceptable per YAGNI; normalize
  still keeps a consistent default).
- Promotion/conflict winner = tie-break rule (`max(updatedAt)` → `max(createdAt)`), applied consistently
  in `setDefaultIdentity` and in `normalizeDefaultIdentity`.

## Related Code Files
- Create: `Vaultify/Data/Repositories/VaultRepository+Identity.swift`
  - `var activeIdentities: [VaultItem]`
  - `var defaultIdentity: VaultItem?`
  - `func setDefaultIdentity(_ item: VaultItem)` (column-only + dirty, then reload)
  - `func isLastActiveIdentity(_ item: VaultItem) -> Bool`
  - `enum IdentityRemovalGate { case ok, lastActiveIdentity }` + `func identityRemovalGate(_:) -> IdentityRemovalGate`
  - `func normalizeDefaultIdentity()` (in-memory patch + column save, no reload)
- Modify: `Vaultify/Data/Repositories/VaultRepository.swift`
  - call `normalizeDefaultIdentity()` at the end of `reload()` (after `items`/`archived`/`trashed` set).
  - in `moveToTrash` / `delete`: if the removed item was default → promotion handled by the
    `normalize` call inside the subsequent `reload()` (set-default happens via normalize's 0-default
    promotion branch). Keep promotion in normalize to avoid duplicate logic (DRY).
- Modify (UI gate wiring done in Phase 4, but define the API here): expose `identityRemovalGate`.

## Implementation Steps
1. **Tests first** (`VaultifyTests/IdentityInvariantTests.swift`, `@MainActor`, `makeRepo()` harness):
   - `testNoDefaultWhenNoIdentities` — empty repo → `defaultIdentity == nil`.
   - `testSetDefaultMarksOneClearsOthers` — add 2 identities, setDefault(A) then setDefault(B) →
     only B default.
   - `testNormalizePromotesWhenNoDefault` — add 2 identities (none default) → after `reload()`, exactly
     one default; winner = latest `updatedAt`.
   - `testNormalizeCollapsesDoubleDefault` — force 2 active defaults with distinct `updatedAt` (raw
     column writes), `reload()` → survivor = the one with the LATER `updatedAt`.
   - `testSetDefaultBumpsUpdatedAt` — `setDefaultIdentity(B)` → B.updatedAt increased (so it syncs).
   - `testLastActiveIdentityGateBlocks` — single identity → `identityRemovalGate == .lastActiveIdentity`.
   - `testGateOkWithTwoIdentities` — 2 identities → `.ok` for either.
   - `testTrashingDefaultPromotesAnother` — A default, B active; `moveToTrash(A)` → B becomes default.
   - `testArchivingDefaultPromotesAnother` — A default, B active; `archive(A)` → B becomes default.
   - `testDeletingDefaultPromotesAnother` — A default, B active; `delete(A)` → B becomes default.
2. Implement extension methods to green the tests.
3. Wire `normalizeDefaultIdentity()` into `reload()`; ensure no recursion.
4. Run tests + `make check`.

## Success Criteria
- [ ] All invariant tests pass.
- [ ] After any active-identity removal with ≥1 remaining, exactly one default exists.
- [ ] Never >1 active default after `reload()`.
- [ ] Gate reports `.lastActiveIdentity` only when exactly one active identity remains.
- [ ] `make check` green.

## Risk Assessment
- Reentrancy: normalize must NOT call `reload()`. Mitigate: normalize mutates records + saves + patches
  `items` array in place; covered by tests calling `reload()` once.
- Conflict ping-pong if `updatedAt` ties on normalize — last-writer-wins is deterministic; ties are
  astronomically unlikely (sub-ms). Acceptable.
- Bulk import could create 0/again-multiple identities → normalize on next reload fixes the default;
  the ≥1 guarantee is UI-gated, not enforced at import (documented).
