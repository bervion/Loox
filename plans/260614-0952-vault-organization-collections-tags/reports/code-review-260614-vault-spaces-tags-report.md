# Code Review — `feat/vault-spaces-tags` (Vault Organization)

**Date:** 2026-06-14 · **Reviewer:** code-reviewer (advisory, no code changed)
**Branch:** `feat/vault-spaces-tags` vs `main` · 5 commits · 50 files · +2708/−117
**Build/test status (provided, spot-trusted):** `make check` green (app+ext); `make test` 14/14 pass.

## Scope
- Data model: `VaultItem`/`ItemSecret`(+tags), `Folder`/`FolderSecret`/`FolderColor`, `FolderRecord`(@Model, sealed name), `ItemRecord`(+`lastUsedAt`), `VaultStore`.
- Repo: `VaultRepository` (decrypt sites, `markUsed`), `VaultRepository+Folders` (CRUD/counts/recents/tags).
- UI: Home dashboard rebuild + folder/tag screens, editor Space picker + `TagChipEditor`, folder editor/picker/manage, badges/icons.
- Cross-cutting: CSV+encrypted backup (folder+tags), CloudKit `VaultFolder` sync, AutoFill `VaultReader` decrypt site, i18n, docs, tests target.

## Overall Assessment
**Strong, ship-quality branch.** Security model is correctly preserved: folder **name** and **tags** are sealed (AES-GCM under the Vault Key); only timing/order/presentation metadata is plaintext — the same trade-off as the existing `favorite` column, and explicitly documented. Both `ItemSecret` decode sites (app `VaultRepository.decrypt` + extension `VaultReader.decrypt`) are updated symmetrically, back-compat is covered by custom `init(from:)` + tests, `FolderRecord` is registered in the `ModelContainer` and wiped by `eraseAll()`, CloudKit folder mapping is zero-knowledge, and the folder-color `.tint` is correctly scoped to the pushed screen (no global bleed). Conventions clean: **no SF Symbols / Material icons** in the diff, **no VI-missing strings** (324/324 translatable have `vi`), **no iOS-26-only `TextField`/`SecureField(LocalizedStringResource:)`** trap, all files < 200 LOC, no leftover debug code or force-unwraps in production code.

No Critical or High findings. The only items worth attention are performance smells, and most of those are **pre-existing** (the branch perpetuates, doesn't introduce them).

---

## Findings

### Medium

**M1 — `deleteFolder` reassigns members one-by-one, full vault `reload()` per member**
`Vaultify/Data/Repositories/VaultRepository+Folders.swift:78-89`
```swift
for item in items where item.folderId == folder.id {
    var moved = item; moved.folderId = nil
    try update(moved)          // each update() → reload() → decrypt EVERY item+folder
}
... reload()                    // + one more
```
A folder with K members triggers K+1 full-vault decrypts. The loop itself is **memory-safe** (Swift iterates the COW snapshot of `items`; `update()` reassigns `self.items` but doesn't perturb iteration — confirmed by `testDeleteFolderReassignsMembersToUnfiled`). The cost is the per-iteration `reload()`. For typical folder sizes (tens of items) it's fine; for a large folder it's noticeably O(K·N).
*Fix (optional):* batch — re-seal all members against the live store, set the folder tombstone, then a single `reload()` at the end. Pattern: loop mutating `record.sealed` directly (like `markUsed` does for `lastUsedAt`) without calling the public `update()`, then one `try store.context.save()` + one `reload()`.

**M2 — `ImportView.performImport()` is O(M·(N+M)) decrypts (pre-existing, amplified)**
`Vaultify/Features/ImportExport/ImportView.swift:102-113` + `add()` at `VaultRepository.swift:50-61`
Each imported row calls `add()` → `reload()`, and each newly-resolved folder calls `addFolder()` → `reload()`. Importing M items into a vault of N existing items decrypts ~M·(N+M) blobs. **This loop-with-reload pattern pre-exists on `main`** (main's `performImport` already did `for item in parsed { add(item) }`); the branch only adds folder match-or-create to the same loop. So it's not a regression, but it's the highest-impact instance (user imports can be large).
*Fix (optional, and would also speed up the pre-existing path):* add a bulk-insert repository method that seals+inserts all items (resolving folders once) and calls `reload()` exactly once. Also gives you transactional semantics — see L1.

### Low

**L1 — Import is non-transactional; a mid-loop failure leaves a partial import**
`Vaultify/Features/ImportExport/ImportView.swift:108-110` — `try? env.repository.add(item)` swallows per-row errors and continues. If sealing/save fails partway (e.g. disk pressure), the user gets a silent partial import with no count of what failed. Pre-existing behavior, but worth a follow-up: collect successes/failures and surface "Imported X of Y". Low because `add` failure is rare on-device and items are additive (re-import is safe).

**L2 — `ManageFoldersScreen.move()` calls `updateFolder()` (full reload) per reordered folder**
`Vaultify/Features/Folders/ManageFoldersScreen.swift:49-57` — reordering N folders = N reloads. Folder counts are small (single digits in practice) so real-world impact is negligible. Could persist all `sortIndex` values then `reload()` once. Lowest priority.

**L3 — `markUsed` disk-writes on a trashed item skip the cache patch (benign)**
`Vaultify/Data/Repositories/VaultRepository.swift:86-93` — `store.record(id:)` finds trashed items (soft-delete), so `lastUsedAt` is written to disk, but `items.firstIndex` fails (trashed items aren't in `items`), so the cache patch is skipped. Harmless: trashed items never appear in `recentlyUsed` (which reads `items`), and the next `reload()` reconciles. In practice `markUsed` only fires from `ItemDetailScreen`, which is only reachable for live items, so the trashed path is unreachable today. No action needed; noting for completeness.

### Nit

**N1 — `allTags()` recomputed on every `TagsSection`/editor render**
`VaultRepository+Folders.swift:123-138` flat-maps + groups all item tags on each access; `TagsSection` and `allTags` consumers re-run it per render. Cheap for normal vaults; if tag-heavy vaults ever lag, memoize on `items` change. Not worth doing now (YAGNI).

**N2 — `parseRows` builds `Array(text)` (whole CSV in memory as `[Character]`)**
`VaultBackup.swift:141` — fine for password-manager export sizes; only matters for pathological multi-MB CSVs. Pre-existing. No action.

---

## Focus-Area Verdicts (all PASS)

| Focus | Result | Evidence |
|---|---|---|
| Old sealed blobs still decode | ✅ | `ItemSecret.init(from:)` `decodeIfPresent(tags) ?? []` + `folderId` optional; `OrganizationCodecTests.testLegacyItemSecretDecodesWithoutTags`. `DynamicField` unchanged (no field-codec drift). |
| Both decode sites updated | ✅ | App `VaultRepository.decrypt` (`:126-140`) **and** extension `VaultReader.decrypt` (`VaultReader.swift:37-46`) both read `secret.tags`/`folderId`. |
| `FolderRecord` in ModelContainer | ✅ | `VaultStore.swift:15`. SwiftData lightweight migration applies (new optional `lastUsedAt` + new model — both additive; main already relied on lightweight migration, no `SchemaMigrationPlan` anywhere). |
| Erase wipes folders | ✅ | `eraseAll()` deletes `FolderRecord` (`VaultStore.swift:24`); `clear()` resets `folders=[]` (`VaultRepository.swift:26`); both called in `AppEnvironment` erase path. |
| Nothing leaks that should be sealed | ✅ | Only `iconAsset`/`colorRaw`/`sortIndex`/`lastUsedAt` plaintext (presentation/timing, documented, == `favorite` trade-off). Name + tags sealed. |
| CloudKit zero-knowledge | ✅ | `ckFolderRecord` uploads `sealed` + icon/color/sortIndex/timestamps only — no plaintext name (`CloudSyncService.swift:133-144`). Tags ride inside the sealed item blob. |
| CSV plaintext caveat | ✅ acceptable | Plaintext passwords in CSV match existing behavior; ExportView shows the "not encrypted" warning (`ExportView.swift:48`). |
| reassign-on-delete loop safety | ✅ | COW snapshot iteration; items moved to Unfiled, never deleted (test-covered). See M1 for perf only. |
| counts exclude trashed | ✅ | `itemCount`/`unfiledCount`/`items(inFolder:)` operate on `items` (live; `reload` splits trashed out). `testItemCountExcludesTrashed`. |
| folder-color tint scoping | ✅ | `.tint(folder?.color.tint)` on the pushed `FolderItemsScreen` only (`:25`); Home unaffected. |
| navigation routes | ✅ | `VaultRoute` enum + `navigationDestination(for: VaultRoute.self)` and `String` (item id) both registered in `VaultListScreen` (`:34-42`). |
| cache coherence after `markUsed` | ✅ | In-place `items[idx].lastUsedAt` patch triggers `@Observable`; no re-seal/`dirty`/`reload`; `testMarkUsedDoesNotReseal`. |
| CSV/backup round-trip incl. legacy | ✅ | `PortableItem.init(from:)` back-compat + `VaultBackupFolderTagsTests` (export/import/legacy CSV/legacy portable). |
| import folder match-or-create | ✅ | `resolveFolder` case-insensitive match against live `folders`, else `addFolder`, with a local `[lowercasedName: id]` cache to dedup within one import (`ImportView.swift:116-128`). |
| SF Symbols / Material icons | ✅ none | `git diff` grep for `systemName`/`systemImage` → none. All curated folder icons + `Icons.*` symbols verified present in `Assets.xcassets`. |
| VI translations complete | ✅ | All 324 translatable catalog strings have a `vi` value (script-verified); every new key present. ("Quick Access" appears only in a doc comment, not user-facing.) |
| iOS-26 TextField trap | ✅ | New `TextField`s use string literals (→ `LocalizedStringKey`), not `LocalizedStringResource`. |
| MainActor/`nonisolated` | ✅ | Core models (`Folder`/`FolderColor`/`FolderSecret`/`VaultItem`/`ItemSecret`) `nonisolated … Sendable`; `VaultReader.decrypt` `nonisolated`; store/repo `@MainActor`. |
| file size / dead code / DRY | ✅ | All new files < 200 LOC (largest 144). `VaultRepository+Folders` extension keeps core CRUD lean. No TODO/FIXME/print left. Folder seal/open mirrors item path (intentional, readable duplication). |

## Positive Observations
- Back-compat treated as a first-class invariant: custom decoders **and** dedicated legacy-decode tests (`OrganizationCodecTests`, `VaultBackupFolderTagsTests`) — this is the right instinct for a zero-backend store where a decode regression = user data appears corrupt.
- New `VaultifyTests` target on a previously test-free repo, wired into `Project.swift` + `Makefile` with an overridable `DEST` — good infra investment beyond the feature itself.
- Security trade-offs documented inline at each plaintext column (`ItemRecord.lastUsedAt`, `FolderRecord` header) with the *reason*, not just the *what*.
- `CuratedFolderIcons` "every name verified present" comment is actually accurate (all 24 imagesets exist) — no blank-tile risk.

## Recommended Actions (priority order)
1. **(M1/M2, optional perf)** If large imports or large-folder deletes are expected, add a bulk repo method that seals all records and calls `reload()` once. This also improves the pre-existing import path and enables transactional import (L1). Not blocking — current behavior is correct, just O(n²) in decrypt count.
2. **(L1, optional UX)** Surface "Imported X of Y" instead of swallowing per-row `try?`.
3. Ship as-is otherwise.

## Unresolved Questions
1. **Expected import size?** Decides whether M2/M1 perf is worth addressing now or deferring. If users typically import < a few hundred items, current behavior is fine and the bulk-method refactor is YAGNI.
2. **Was the pre-existing `emptyTrash`/`performImport` per-iteration `reload()` already a known/accepted trade-off?** If yes, M1/L2 are consistent with house style and can be deferred; the branch didn't regress it.
