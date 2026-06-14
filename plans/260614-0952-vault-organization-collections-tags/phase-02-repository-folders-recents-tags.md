# Phase 02 — Repository: Folder CRUD, Counts, Recents, Tag Aggregation

## Context Links
- Overview: [plan.md](plan.md)
- Depends on: [Phase 01](phase-01-data-model-and-persistence.md)
- Repository: `Vaultify/Data/Repositories/VaultRepository.swift` (full file read 2026-06-14)
- Store helpers: `VaultifyCore/Store/VaultStore.swift:30-38` (`allRecords`, `record(id:)`)
- Existing seal/open: `VaultRepository.seal` (line 105-107), `VaultRepository.decrypt` (line 109-121)

## Overview
- **Priority**: P1
- **Status**: ✅ done (compiles app + extension via `make check`)
- Extend `VaultRepository` (the `@MainActor @Observable` decrypt-to-memory cache) with: a folders cache, folder CRUD (seal/open `FolderSecret`), computed item counts per folder, reassign-on-delete, `markUsed(lastUsedAt)`, and distinct-tag aggregation. No UI; this is the data API Phases 03/04 bind to.

## Key Insights
- `VaultRepository` already owns the unlock lifecycle: `reload()` decrypts records into `items`/`trashed`; `clear()` wipes on lock (line 20-24). Folders cache must follow the same lifecycle (load in `reload`, wipe in `clear`).
- Folder name is sealed → folder load needs the Vault Key, same as items. Reuse the `seal`/`open` pattern (mirror `seal(_:key:)` line 105 for `FolderSecret`).
- **Item counts must EXCLUDE trashed items** (Spaces grid shows live items only). Count over `items` (already non-trashed; `reload` splits trashed out, line 36).
- `markUsed` updates a PLAINTEXT column → MUST NOT re-seal (no `seal()` call, no `updatedAt` bump). Write `record.lastUsedAt` directly + `save()`. This is why `lastUsedAt` is a column, not in the sealed blob (Decision E).
- **Do NOT set `dirty = true` on `markUsed`.** `lastUsedAt` is in-app-only and intentionally NOT synced (Decision E says AutoFill/cross-device usage out of scope) → avoid sync churn. Recents are device-local.
- Tag aggregation = distinct tags across live `items` with counts; drives the Tags row. Compute on read (cheap; vault is small) — no separate cache to invalidate (KISS).
- Reassign-on-delete (Decision F): deleting a folder sets `folderId = nil` on each member item. That requires **re-sealing each affected item** (folderId is inside `ItemSecret`) → bump `updatedAt` + `dirty` so the reassignment syncs. Folder itself gets a `deletedAt` tombstone (mirror item soft-delete, line 91-97).

## Requirements
**Functional**
- `folders: [Folder]` published, sorted by `sortIndex` then `createdAt`.
- `addFolder`, `updateFolder` (name/icon/color/sortIndex), `deleteFolder` (reassign members → Unfiled, tombstone folder).
- `itemCount(for folderId:) -> Int` (live items only); `unfiledCount`.
- `assign(item, toFolder:)` convenience (sets `folderId`, re-seals via existing `update`).
- `markUsed(_ item:)` → set `lastUsedAt = .now` on the record WITHOUT re-seal.
- `recentlyUsed(limit:)` → live items sorted by `lastUsedAt` desc, nil last.
- `allTags() -> [(tag: String, count: Int)]` distinct, sorted by count desc then alpha; `items(withTag:)`.
- `items(inFolder folderId: String?)` filtered accessor.

**Non-functional**
- Folder ops are throwing (mirror item CRUD, throw `AuthError.locked` when no key).
- `markUsed` is best-effort `try?` at call sites (never block a copy on a write failure).

## Architecture
```
VaultRepository (existing @MainActor @Observable)
 + private(set) var folders: [Folder]
 + reload():  also fetch FolderRecord(deletedAt==nil) -> decrypt -> folders (sorted)
 + clear():   folders = []
 + sealFolder / decryptFolder  (mirror seal/decrypt for FolderSecret)
 + folderRecord(id:)           (mirror record(id:))
 + CRUD + counts + reassign + markUsed + recents + tag aggregation
```
File-size guard: `VaultRepository.swift` is 128 LOC today. Adding all of the above risks >200 LOC. **Split folder/tag/recents logic into an extension file** `Vaultify/Data/Repositories/VaultRepository+Folders.swift` (same type, `extension VaultRepository`), keeping the core CRUD file lean. New file → `tuist generate`.

## Related Code Files
**Create**
- `Vaultify/Data/Repositories/VaultRepository+Folders.swift` — `extension VaultRepository` with: `sealFolder`, `decryptFolder`, `folderRecord(id:)`, `addFolder`, `updateFolder`, `deleteFolder`, `itemCount(for:)`, `unfiledCount`, `assign(_:toFolder:)`, `markUsed`, `recentlyUsed(limit:)`, `allTags`, `items(withTag:)`, `items(inFolder:)`. Target < 180 LOC.

**Modify**
- `Vaultify/Data/Repositories/VaultRepository.swift`:
  - Add `private(set) var folders: [Folder] = []`.
  - In `reload()` (line 27-41): after building `items`/`trashed`, fetch `FolderRecord` where `deletedAt == nil`, decrypt → assign `folders` sorted by `(sortIndex, createdAt)`.
  - In `clear()` (line 20-24): add `folders = []`.
  - Expose `decrypt`/`seal` reuse: keep `seal`/`decrypt` private but add folder equivalents in the extension (extensions can access private members in the same module/file? — NO, `private` is file-scoped). **Action**: change `seal`/`decrypt` for items to `fileprivate`→ keep as-is; for folders write independent `sealFolder`/`decryptFolder` in the extension using `session.vaultKey` + `AESGCM` directly (do NOT widen item `seal`'s visibility — KISS). The extension calls `AESGCM.seal/open` itself.

## Implementation Steps
1. Add `folders` stored property + `clear()` reset in `VaultRepository.swift`.
2. In `reload()`, add a `FetchDescriptor<FolderRecord>(predicate: #Predicate { $0.deletedAt == nil })` fetch, decrypt each via `decryptFolder`, sort, assign. Guard on `session.vaultKey` (same key check already at top of `reload`).
3. Create `VaultRepository+Folders.swift`:
   - `sealFolder(_ folder:, key:) -> Data` = `AESGCM.seal(JSONEncoder().encode(folder.secret), key:)`.
   - `decryptFolder(_ record:, key:) -> Folder` = open + decode `FolderSecret`, build `Folder(id:record.id, name:secret.name, iconAsset:record.iconAsset, color: FolderColor(rawValue: record.colorRaw) ?? .gray, sortIndex:record.sortIndex, createdAt:record.createdAt, updatedAt:record.updatedAt)`.
   - `addFolder(name:icon:color:)`: guard key; build `Folder`; insert `FolderRecord(id:sealed:iconAsset:colorRaw:sortIndex:)` with `sortIndex = (folders.map(\.sortIndex).max() ?? -1) + 1`; save; `reload()`.
   - `updateFolder(_:)`: fetch record; re-seal name; update `iconAsset`/`colorRaw`/`sortIndex`/`updatedAt`/`dirty=true`; save; reload.
   - `deleteFolder(_:)`: **reassign first** — for each `item in items where folderId == folder.id`, `var u = item; u.folderId = nil; try update(u)` (re-seals, bumps dirty). Then set `folderRecord.deletedAt = .now; dirty = true`; save; reload.
   - `itemCount(for id:)` = `items.filter { $0.folderId == id }.count`; `unfiledCount` = `items.filter { $0.folderId == nil }.count`.
   - `assign(_ item:, toFolder id:)` = `var u = item; u.folderId = id; try update(u)`.
   - `markUsed(_ item:)`: fetch record; `record.lastUsedAt = .now`; `try store.context.save()`. **No re-seal, no dirty, no reload** (avoid wiping the in-memory cache on every copy — instead mutate the cached item's lastUsedAt in place if we track it on `VaultItem`; see Note). 
   - `recentlyUsed(limit:)`: requires `lastUsedAt` visible in-memory. **Decision**: surface `lastUsedAt` on `VaultItem` (read-only) so Home can sort without refetch. Add `lastUsedAt: Date?` to `VaultItem` (Phase 01 addendum) populated in both `decrypt` sites from `record.lastUsedAt`. Then `recentlyUsed` = `items.filter{ $0.lastUsedAt != nil }.sorted{ ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }.prefix(limit)`.
   - `allTags()`: flatMap `items.flatMap(\.tags)`, count via `Dictionary(grouping:)`, map to tuples, sort.
   - `items(withTag:)`, `items(inFolder:)`: simple filters.
4. **Phase 01 addendum** (do here if not already): add read-only `lastUsedAt: Date?` to `VaultItem` + thread from `record.lastUsedAt` in `VaultRepository.decrypt` (line 112-120) and `VaultReader.decrypt` (line 41-44, pass `nil` is fine for extension since AutoFill doesn't need it — or thread it). Update `markUsed` to also mutate the cached `items[idx].lastUsedAt` in place to avoid a full `reload()`.
5. `tuist generate --no-open` (1 new file).
6. `make check`.

> **Note on `markUsed` & cache coherence**: avoid `reload()` in `markUsed` (it re-decrypts the whole vault on every copy — wasteful, and would fight the toast). Instead persist `record.lastUsedAt` AND patch the in-memory `items` array element. This keeps Recents fresh without a full decrypt cycle.

## Todo List
- [x] Add `folders` property + `clear()` reset
- [x] Extend `reload()` to load + decrypt folders (sorted)
- [x] Create `VaultRepository+Folders.swift` (seal/decrypt/CRUD/counts/recents/tags)
- [x] Implement reassign-on-delete (members → Unfiled, then tombstone folder)
- [x] Implement `markUsed` WITHOUT re-seal/dirty; patch in-memory cache
- [x] Add read-only `lastUsedAt` to `VaultItem`, thread from both decode sites
- [x] Implement `allTags`/`items(withTag:)`/`items(inFolder:)` (case-insensitive tags)
- [x] `tuist generate --no-open`
- [x] `make check` passes

## Success Criteria
- Add a folder → appears in `folders` after `reload`; refetch from a fresh `VaultRepository` instance still finds it (persisted).
- Assign 3 items to a folder → `itemCount` == 3; trash one → count == 2.
- Delete folder → those items have `folderId == nil`, folder gone from `folders`, items NOT deleted.
- `markUsed` twice on different items → `recentlyUsed(limit: 5)` ordered by most-recent.
- `allTags` returns distinct tags with correct counts.
- `make check` green.

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| `markUsed` calling `reload()` → janky UI / perf on copy | Med | Med | Spec forbids reload in markUsed; patch cache in place + persist column only. |
| `private` `seal`/`decrypt` not reachable from extension file | High | Low | Don't reuse; write independent `sealFolder`/`decryptFolder` (KISS, no visibility widening). |
| Reassign-on-delete re-seals many items (perf on large folder) | Low | Med | Vault is small (personal); acceptable. Each reassign uses existing `update`. Note as future batch-optimize. |
| `VaultRepository.swift` exceeds 200 LOC | Med | Low | Split into `+Folders.swift` extension (Architecture). |
| Folder loaded but Vault Key absent (race on unlock) | Low | Med | Same guard as items: `reload` early-returns when `session.vaultKey == nil`. |

## Security Considerations
- Folder decrypt requires the Vault Key (name is sealed). Folders cache cleared on lock (`clear()`).
- `markUsed` writes only a timestamp — no plaintext content touched.
- Reassign re-seals item payloads with the current key (folderId lives in `ItemSecret`).

## Next Steps
- Phase 03 binds folder CRUD + tag input to the editor & a folder-management screen.
- Phase 04 binds counts/recents/tags to the Home dashboard.
