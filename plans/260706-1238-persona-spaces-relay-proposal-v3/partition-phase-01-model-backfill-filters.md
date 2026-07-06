# Phase 01 — Model migration, resolver, repo filters

**Context:** `partition-plan.md` · `proposal-v3-locked-decisions.md` (D10/D12, INV-R03) · seams verified below.
**Priority:** P2 · **Status:** pending · **Deps:** none (foundation).

## Overview
The fail-closed foundation. Populate `Folder.personaId` (backfill nil→default), reconcile stale
`primarySpaceID` pointers, upgrade the item→persona resolver, and add the ONE persona-scoped
filter that every surface consumes. All INV-R03 enforcement lives here at the repo source; the
UI phases only reflect it.

## Key insights (verified)
- `Folder.personaId: String?` sealed in `FolderSecret` — `VaultifyCore/Models/Folder.swift:21,54`. Always nil today.
- `assignSpace(_:toPersona:)` sets it via `updateFolder` (re-seal, bump `updatedAt`) — `VaultRepository+Personas.swift:92`.
- `personaID(forItem:)` is **private**, uses the `primarySpaceID` heuristic — `VaultRepository+PersonaContext.swift:83`. Upgrade to `folder.personaId`, make internal.
- Reload runs `ensurePersonaExists`→`normalizeDefaultPersona` at `VaultRepository.swift:78-79` (patch-in-place, never `reload()`). Backfill hooks in right after (default persona now guaranteed).
- `mergeDuplicateSeedFolders` (`VaultRepository.swift:108`) is the canonical in-place re-seal + `updatedAt`-bump + `noteLocalMutation` pattern to mirror.
- `scoped()` / `items(inFolder:)` / `unfiledCount` / `itemCount(for:)` / `search(_:scope:)` — `VaultRepository+Folders.swift:176,120,118,114,251`. These are the shared item pools to persona-scope.
- **DO NOT** touch `CredentialIdentityService.refresh(items:...)` at `VaultRepository.swift:66` — AutoFill stays cross-persona (decision 6).
- Published `folders`/`items`/`personas` are `private(set)` — `VaultRepository.swift:13,16,18`. `defaultPersona`/`activePersona` — `VaultRepository+Personas.swift:48,52`.

## Requirements
- **F1 Backfill:** on reload, every folder with `personaId == nil` → `defaultPersona.id`; re-seal record, bump `updatedAt`, `dirty=true`; patch `folders` cache in place; `noteLocalMutation()`. Idempotent (skip when non-nil). Never `reload()`.
- **F2 Reconcile primarySpaceID:** for each persona `P`, if `P.primarySpaceID` points at a folder whose `personaId != P.id`, repoint to `P`'s first owned folder ?? nil; re-seal persona (`updatePersona`-style, bump `updatedAt`). Fixes the P1 `folders.first` leak (top risk 1). Idempotent.
- **F3 Resolver:** `personaID(forItem:) -> String?` = `folder(item.folderId)?.personaId ?? defaultPersona?.id` for nil folder → default. Internal.
- **F4 Filters (defined once):**
  - `spaces(for persona: Persona) -> [Folder]` = `folders.filter { ($0.personaId ?? defaultPersona?.id) == persona.id }`.
  - `items(for persona: Persona) -> [VaultItem]` = folder-owned items ∪ (nil-folder items **iff** `persona.isDefault`).
  - `activePersonaSpaces` / `activePersonaItems` convenience over `activePersona` (pre-persona/no-active → all, preserves legacy).
- **F5 Persona-scope the shared pools:** `scoped()`, `items(inFolder:)`, `unfiledCount`, `itemCount(for:)`, and `search(_:scope:)`'s item source all draw from `activePersonaItems` first. Fail-closed by construction.

## Architecture / data flow
```
reload(): loadFolders → ensurePersonaExists → normalizeDefaultPersona
        → migratePartition(key:)   [NEW: F1 backfill + F2 reconcile, in place]
        → mirrorActivePersonaContext
Read path: view → repo.activePersonaItems (F4) → scoped(folderId) (F5) → view
Resolver:  item.folderId → folder.personaId (F3) → persona ; nil folder → default
```
Backfill writes SAME `defaultPersona.id` (normally fixed `bootstrapPersonalID`) on every device →
LWW converges. `personaId` change re-seals folder → `updatedAt` bump → survives whole-record pull.

## Related code files
- **Modify:** `Vaultify/Data/Repositories/VaultRepository.swift` (call `migratePartition` in `reload()` after line 79).
- **Modify:** `Vaultify/Data/Repositories/VaultRepository+PersonaContext.swift` (upgrade `personaID(forItem:)`, make internal).
- **Modify:** `Vaultify/Data/Repositories/VaultRepository+Folders.swift` (persona-scope `scoped`/`items(inFolder:)`/`unfiledCount`/`itemCount`/`search`).
- **Create:** `Vaultify/Data/Repositories/VaultRepository+PersonaPartition.swift` (`migratePartition(key:)`, `spaces(for:)`, `items(for:)`, `activePersonaSpaces`, `activePersonaItems`) — keep <200 LOC.
- **Create:** `VaultifyTests/PersonaPartitionTests.swift`.
- **Do NOT modify:** `CredentialIdentityService` call site (AutoFill cross-persona).
- Run `tuist generate --no-open` after adding the 2 new files.

## Implementation steps
1. New `+PersonaPartition.swift`: `spaces(for:)`, `items(for:)`, `activePersonaSpaces`, `activePersonaItems` (nil active persona → return all, legacy path).
2. Same file: `migratePartition(key:)` = F1 backfill loop (mirror `mergeDuplicateSeedFolders`: fetch `folderRecord`, re-seal via folder secret, bump `updatedAt`/`dirty`, patch `folders[idx].personaId`) + F2 reconcile loop over `personas`.
3. `VaultRepository.swift:79`: call `migratePartition(key: key)` after `normalizeDefaultPersona()`, before `mirrorActivePersonaContext()`.
4. `+PersonaContext.swift:83`: rewrite `personaID(forItem:)` per F3; drop `private`.
5. `+Folders.swift`: route `scoped`, `items(inFolder:)`, `unfiledCount`, `itemCount(for:)`, and `search`'s base collection through `activePersonaItems`.
6. `tuist generate --no-open` → `make check`.
7. Write `PersonaPartitionTests.swift` (harness = `PersonaIsolationTests.makeRepo()` pattern).

## Todo
- [ ] `+PersonaPartition.swift` filters + `migratePartition`
- [ ] Hook `migratePartition` into `reload()`
- [ ] Upgrade `personaID(forItem:)`
- [ ] Persona-scope shared pools in `+Folders`
- [ ] `tuist generate` + `make check` green
- [ ] `PersonaPartitionTests` green + full suite green

## Success criteria (concrete INV-R03 assertions)
- `testBackfillAssignsNilFoldersToDefault`: seed folder pre-persona → after reload `folder.personaId == defaultPersona.id`; second reload writes nothing (idempotent — capture `updatedAt`, assert unchanged).
- `testItemPersonaDerivation`: item in folder F (owned by A) → `personaID(forItem:) == "A"`; nil-folder item → default id.
- `testStrictAnonymousSeesNoDefaultSpacesOrItems`: default owns folder+item; add strictAnonymous persona (no owned space); `setActivePersona`. **Assert `spaces(for: active).isEmpty`, `items(for: active).isEmpty`, `unfiledCount == 0`, `search("x", scope: .allSpaces).isEmpty`.**
- `testStandardPersonaAlsoPartitioned`: standard persona B owning zero spaces → `activePersonaItems.isEmpty` even though default has items (partition is universal, not strictAnonymous-only).
- `testReconcileClearsStalePrimarySpaceID`: persona whose `primarySpaceID` points at a default-owned folder → after migrate, pointer nil (or owned); strictAnonymous `defaultSearchScope` yields no default-folder match.
- `testUnfiledOnlyUnderDefault`: nil-folder item visible in `items(for: default)`, absent in `items(for: nonDefault)`.
- Existing `PersonaIsolationTests` + `VaultRepositoryFolderTests` stay green.

## Risk assessment
- **primarySpaceID leak (H×H → mitigated):** F2 reconcile + explicit test.
- **Suite regression (M×M):** backfill-to-default keeps single-persona behavior; run full suite gate.
- **Backfill split-brain (L×M):** target converged `defaultPersona.id`; document; LWW converges.
- **Nil-folder synced from un-migrated device (L×L):** `?? defaultPersona?.id` maps nil→default defensively.

## Security
- No plaintext crosses trust boundary; `personaId` sealed in `FolderSecret`. AutoFill mirror unchanged. INV-R03 enforced at the read source (exclusion, never down-rank).

## Next steps
Unblocks Phase 02 (UI reflects filters), 03 (create paths), 04 (delete reassign).
