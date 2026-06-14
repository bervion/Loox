# Phase 02 — Data Model + Repository (pinned / archived / useCount)

## Context Links
- Model: `VaultifyCore/Models/VaultItem.swift` (struct + sealed `ItemSecret`)
- Record: `VaultifyCore/Store/ItemRecord.swift:9` (`@Model`)
- Store: `VaultifyCore/Store/VaultStore.swift` (`record`, `upsertFromRemote:42`, `eraseAll:22`)
- Repo: `Vaultify/Data/Repositories/VaultRepository.swift` (`reload:31`, `decrypt:126`, `markUsed:86`)
- Repo folders/accessors: `Vaultify/Data/Repositories/VaultRepository+Folders.swift`
- AutoFill decode: `VaultifyCore/VaultReader.swift:37` (`decrypt`), `:28-35` (`logins` predicate)
- CloudKit: `Vaultify/Services/Sync/CloudSyncService.swift:108` (`ckRecord`), `:120` (`apply`)

## Overview
- **Priority:** P1 (blocks Home/Items/actions phases)
- **Status:** pending
- Add `pinned: Bool`, `archived: Bool`, `useCount: Int` as PLAINTEXT columns on `ItemRecord`; thread
  them onto `VaultItem` (read-only from the record) at BOTH decode sites; add repo mutators/accessors;
  split archived out of the live `items` cache; map the new fields through CloudKit (compile-gated).

## Key Insights
- **Codec unchanged:** new fields are columns, NOT in `ItemSecret` → `seal`/`decrypt` JSON payload and
  the legacy-tolerant `ItemSecret.init(from:)` (`VaultItem.swift:101`) are untouched. **No new
  legacy-decode risk this round.** This is the deliberate "keep it safe" trade-off (same as `favorite`).
- **Single exclusion point:** `reload()` (`VaultRepository.swift:31-46`) is where trashed is split from
  active. Adding archived-split there means **every consumer of `repository.items` automatically
  excludes archived** — no per-consumer edits for the exclusion. DRY win. (Consumers verified below.)
- **`markUsed` site:** `VaultRepository.swift:86` uses `store.record(id:)` and patches the in-memory
  cache in place (no re-seal/dirty/reload). useCount increment goes here, same no-reseal contract.
  Called from exactly one site: `ItemDetailScreen.swift:117` (`onUsed`).
- **`ItemRecord.init` does not set new fields:** like `deletedAt`/`lastUsedAt`, the new columns get
  SwiftData defaults via property initializers; `upsertFromRemote` and `add` set them post-init.
- **Backward compat:** additive columns (`Bool=false`, `Int=0`) → SwiftData lightweight migration;
  existing vaults open fine, existing sealed blobs untouched. `eraseAll` already wipes `ItemRecord`.

## Requirements
**Functional:**
- `VaultItem` exposes `pinned`, `archived`, `useCount` (read-only mirror of the record).
- Repo: `togglePin`, `archive`, `unarchive`, `markUsed` (now also `useCount += 1`).
- Repo accessors: `pinned`, `frequentlyUsed(limit:)`, `recentlyCreated(limit:)`,
  `recentlyModified(limit:)`, `archivedItems` (or `archived` array property).
- `repository.items` = live, non-archived, non-trashed. New `archived` array (mirrors `trashed`).
- AutoFill `logins` excludes archived items.
- CloudKit round-trips the 3 fields (compile-gated by `VAULTIFY_ICLOUD`).

**Non-functional:** crypto/data types stay `nonisolated`; no re-seal on pin/archive (columns only);
pin/archive DO set `dirty` + save + reload (metadata change, mirroring `toggleFavorite`/`moveToTrash`).

## Architecture
**Data flow (decode):** `ItemRecord` columns → `decrypt()` constructs `VaultItem(..., pinned:
record.pinned, archived: record.archived, useCount: record.useCount)`. Two decode sites must both set
them: `VaultRepository.decrypt` (`:126`) and `VaultReader.decrypt` (`:37`).

**Data flow (cache split):** `reload()` iterates records → route into `active` / `archived` / `trash`.
Decision (locked): an archived item is excluded from `items` **regardless of trashed state** (archived
takes precedence; archived+trashed is shown in neither normal surface). Order: check `isTrashed` first
(existing trash semantics win for already-trashed), else `archived` → `archived` array, else `active`.

**Mutators:** `togglePin`/`archive`/`unarchive` follow the `toggleFavorite` shape — mutate the flag on
a copy, call `update(_:)`. BUT `update()` re-seals (`:68`). Pin/archive don't change secret content, yet
re-sealing is harmless and keeps one code path (KISS) — **decision: reuse `update()`** (sets dirty +
updatedAt + reload). Caveat: this bumps `updatedAt`, which would reorder "Recently Modified". To avoid
polluting Recently-Modified with pin/archive toggles, add a lightweight column-only path mirroring
`markUsed`: set `record.pinned`/`archived` + `dirty` + save + reload, WITHOUT bumping `updatedAt` or
re-sealing. **Use the column-only path** (see Risk: updatedAt pollution).

## Related Code Files
**Modify:**
- `VaultifyCore/Store/ItemRecord.swift` — add `var pinned: Bool`, `var archived: Bool`,
  `var useCount: Int` with property-initializer defaults (`= false`/`= false`/`= 0`); keep `init` sig
  stable (new fields default via initializers, like `deletedAt`/`lastUsedAt`).
- `VaultifyCore/Models/VaultItem.swift` — add `var pinned`, `var archived`, `var useCount` to struct +
  `init` (defaults `false`/`false`/`0`). DO NOT add to `ItemSecret` or `secret`/`searchText`.
- `Vaultify/Data/Repositories/VaultRepository.swift` — (a) `reload()` 3-way split + new `archived`
  array property; (b) `decrypt()` pass new fields; (c) `add()` set new columns from item; (d) `markUsed`
  `record.useCount += 1` and patch cache `items[idx].useCount`; (e) add `togglePin`,
  `archive`/`unarchive` (column-only path).
- `Vaultify/Data/Repositories/VaultRepository+Folders.swift` — add `pinned`, `frequentlyUsed(limit:)`,
  `recentlyCreated(limit:)`, `recentlyModified(limit:)` accessors (all filter from `items`, which is
  already archived/trashed-excluded). `archivedItems` reads the new `archived` array.
- `VaultifyCore/VaultReader.swift` — `decrypt` (`:41`) pass new fields; `logins` predicate (`:31`) add
  `$0.archived == false`.
- `VaultifyCore/Store/VaultStore.swift` — `upsertFromRemote` add `pinned`/`archived`/`useCount` params,
  set on existing + new record (post-init for the new-record branch).
- `Vaultify/Services/Sync/CloudSyncService.swift` — `ckRecord(from:)` add 3 keys (Int 0/1 for bools,
  Int for useCount, mirror `favorite`); `apply(_:)` read them + pass to `upsertFromRemote`.

## Implementation Steps
1. Add 3 columns to `ItemRecord` (property-initializer defaults).
2. Add 3 fields to `VaultItem` struct + init.
3. `VaultRepository.decrypt` — pass `pinned/archived/useCount` from record.
4. `VaultRepository.add` — set `record.pinned/archived/useCount` from item before save.
5. `VaultRepository.reload` — 3-way split (`trash` if `isTrashed`, else `archived` array if
   `item.archived`, else `active`); add `private(set) var archived: [VaultItem]`; sort archived by
   `updatedAt desc`; clear it in `clear()`; include in `isEmpty`.
6. `VaultRepository.markUsed` — `record.useCount += 1`; patch `items[idx].useCount`.
7. `VaultRepository` — add `togglePin`, `archive`, `unarchive` (column-only: set flag + dirty + save +
   reload; no re-seal, no updatedAt bump).
8. `VaultRepository+Folders` — add `pinned`, `frequentlyUsed`, `recentlyCreated`, `recentlyModified`,
   `archivedItems` accessors.
9. `VaultReader.decrypt` + `logins` predicate — pass fields, exclude archived.
10. `VaultStore.upsertFromRemote` — extend signature + set fields.
11. `CloudSyncService.ckRecord`/`apply` — map 3 fields.
12. `tuist generate` (no new files, but keep consistent) + `make check` green.

## Consumer Audit (verified — `repository.items` readers)
All auto-exclude archived once `reload()` splits it out; **no edits needed** to these for exclusion:
- `Vaultify/Features/ImportExport/ExportView.swift:23,81` — export now excludes archived (intended:
  archived not in normal surfaces). *Open Q: should export include archived? See phase-09.*
- `Vaultify/Features/Watchtower/WatchtowerScreen.swift:54,55,82,92` — audit excludes archived (intended).
- `Vaultify/Features/ItemDetail/ItemDetailScreen.swift:13` — `items.first{...}`; an archived item won't
  be found here → detail opened from ArchiveScreen must read from `archived`. **Edit needed in Phase 7.**
- `Vaultify/Features/Vault/HomeDashboard.swift:17,34`, `VaultListScreen.swift:28,37`,
  `QuickAccessSection.swift:10` — these screens are replaced/restructured in Phases 4 & 6.
- Accessors `items(inFolder:)`, `items(withTag:)`, `allTags()`, counts (`+Folders`) — all derive from
  `items` → auto-exclude archived (intended).

## Todo List
- [ ] ItemRecord: pinned/archived/useCount columns
- [ ] VaultItem: 3 fields + init (NOT in ItemSecret)
- [ ] decrypt() both sites pass new fields
- [ ] add() sets new columns
- [ ] reload() 3-way split + `archived` array + clear()/isEmpty
- [ ] markUsed() increments useCount + patches cache
- [ ] togglePin / archive / unarchive (column-only path)
- [ ] accessors: pinned/frequentlyUsed/recentlyCreated/recentlyModified/archivedItems
- [ ] VaultReader: exclude archived from logins
- [ ] VaultStore.upsertFromRemote + CloudKit map (compile-gated)
- [ ] `make check` green

## Success Criteria
- `make check` passes (app + extension).
- Existing 14 tests still pass (additive change; run in Phase 9, but no API break here).
- New columns default safely on an existing vault (lightweight migration, no decode change).
- `repository.items` excludes archived; `repository.archived` lists archived; AutoFill skips archived.

## Risk Assessment
| Risk | L×I | Mitigation |
|---|---|---|
| `updatedAt` pollution: pin/archive via `update()` bumps updatedAt → corrupts "Recently Modified" | Med×Med | Use column-only mutator path (no updatedAt bump, no re-seal). Verified `update()` bumps at `:69`. |
| `upsertFromRemote` signature change breaks call site | Low×Med | Single caller: `CloudSyncService.apply` (`:124`). Update together. New params after existing → no positional ambush. |
| SwiftData migration fails on new non-optional columns | Low×High | Property-initializer defaults make them safe-additive (proven pattern: `favorite`/`dirty` already non-optional w/ defaults). In-memory + on-disk both covered. |
| Archived+trashed ordering ambiguity | Low×Low | Locked: `isTrashed` check first (trash wins), else archived. Documented in `reload()` comment (why, not phase #). |
| useCount lost on CloudKit pull (last-writer-wins overwrites local count) | Low×Low | Acceptable: useCount is best-effort ranking, not data. Mirror favorite's LWW. Note in CloudKit verify (Phase 8). |

## Security Considerations
- New fields are low-sensitivity metadata (a pin flag / use tally / archive flag) — same justification
  as `favorite`/`lastUsedAt` for living in plaintext columns. No secret content exposed.
- `useCount` is a usage-frequency signal; like `lastUsedAt` it's timing/behavioral metadata. Keep it
  device-local-friendly; LWW sync is acceptable (not security-relevant).

## Next Steps
Unblocks Phase 4 (Home sections use accessors), Phase 6 (ArchiveScreen uses `archivedItems`),
Phase 7 (actions call togglePin/archive). Phase 9 tests this API.
