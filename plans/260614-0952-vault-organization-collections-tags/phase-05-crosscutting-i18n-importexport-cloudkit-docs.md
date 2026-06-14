# Phase 05 — Cross-Cutting: i18n, Import/Export, CloudKit, Docs

## Context Links
- Overview: [plan.md](plan.md)
- Depends on: [Phase 01](phase-01-data-model-and-persistence.md)–[Phase 04](phase-04-home-dashboard-and-filtered-list.md)
- String catalog: `Vaultify/Localizable.xcstrings` (format verified: `sourceLanguage: en`, en + vi `stringUnit`)
- `.inAppLocalized` idiom: `VaultifyCore/Models/ItemCategory.swift:17-29`
- Import/Export: `Vaultify/Services/ImportExport/VaultBackup.swift` (full read 2026-06-14)
- CloudKit: `Vaultify/Services/Sync/CloudSyncService.swift` (full read 2026-06-14)
- Store sync helpers: `VaultifyCore/Store/VaultStore.swift:30-68`
- Docs: `docs/codebase-summary.md`

## Overview
- **Priority**: P1 (localization is MANDATORY per CLAUDE.md; CSV + CloudKit are completeness)
- **Status**: ✅ done — i18n EN+VI (22 keys), CSV+backup folder/tags columns, CloudKit `VaultFolder` (compile-only, gated), docs updated. `make check` green.
- Finalize the feature's seams: localize EVERY new string EN+VI, add folder/tags columns to CSV + extend the encrypted backup payload, give `FolderRecord` full CloudKit parity (compile-gated), and update docs.

## Key Insights
- **Localization is a release-blocker** (CLAUDE.md: "a missing VI value is a bug"). SwiftUI `Text("…")` literals auto-extract to the catalog on build, but VI must be added manually. New `LocalizedStringResource` titles must use `.inAppLocalized`; runtime strings use `appString()`.
- The "Spaces"/"Nhóm" label (Decision B) is a single catalog key reused everywhere → translators flip one entry to rename the feature.
- **CSV needs TWO new columns**: `folder` (folder name) + `tags` (delimited). `makeCSV` header is hardcoded (`VaultBackup.swift:44`) and import maps by header name (line 14-21) → additive, backward compatible (old CSVs without the columns still import: `index([...])` returns nil → empty).
- **Encrypted backup also drops folder/tags today**: `PortableItem` (line 6) = `{title, category, fields}` only, and `importEncrypted`/`exportEncrypted` (line 58-82) don't carry `folderId`/`tags`. To not regress the new data through encrypted backup, extend `PortableItem` with `tags` and a folder NAME (not id — ids aren't portable across vaults). Optional/back-compat decode.
- **CSV folder import = match-or-create by name** (Decision H). Need a folder-name→id map built from `repository.folders`; missing names → `addFolder` (default icon `ic_folder`, default color). This logic lives in the IMPORT call site (a screen/service), not in `VaultBackup` (which is `nonisolated` and key-free) — `VaultBackup.parseCSV` returns `VaultItem`s carrying a folder NAME hint; the importer resolves names→ids against the repository. **Design**: `parseCSV` can't set `folderId` (no folder context) → return items with `folderId == nil` plus a parallel folder-name list, OR add a transient field. Simplest: extend the importer (the screen that calls `parseCSV` + `repository.add`) to also read the folder column and call `assign`/`addFolder`. Locate that call site (ImportExport feature) and thread folder names there.
- **CloudKit parity** (Decision G): `FolderRecord` needs its own record type ("VaultFolder"), push/pull, ckRecord mapping (sealed + iconAsset + colorRaw + sortIndex + timestamps + tombstone), and a `VaultStore` upsert for folders. All still behind `#if VAULTIFY_ICLOUD` / `isConfigured` (off by default). Tags ride inside item `sealed` → already synced free.

## Requirements
**Functional**
- Every new user-facing string has EN source + VI translation in `Localizable.xcstrings`.
- CSV export includes `folder` + `tags` columns; CSV import reads them (match/create folders by name; split tags).
- Encrypted backup round-trips `tags` + folder name.
- With `VAULTIFY_ICLOUD` on, folders sync (push dirty, pull remote, LWW by `updatedAt`, tombstones honored). Off by default = no behavior change.
- `docs/codebase-summary.md` documents folders/tags/recents.

**Non-functional**
- No hardcoded user-facing strings remain (audit new files from Phases 03–04).
- CSV/backup changes are backward compatible (old files import without the new columns/keys).
- CloudKit changes never run when `isConfigured == false`.

## Related Code Files
**Modify**
- `Vaultify/Localizable.xcstrings` — add all new keys (list below) with en + vi. Include the "Spaces"/"Nhóm" label key.
- `Vaultify/Services/ImportExport/VaultBackup.swift`:
  - `makeCSV`: header → `name,username,password,url,notes,folder,tags`; per-row append folder name (resolved by caller? — `VaultItem` has only `folderId`). **Problem**: `VaultBackup` has no folder name lookup. **Fix**: change `makeCSV(_ items:)` → `makeCSV(_ items:, folderNames: [String: String])` (id→name map passed by the export caller from `repository.folders`). Append `folderNames[item.folderId ?? ""] ?? ""` and `item.tags.joined(separator: "; ")` (escape).
  - `parseCSV`: add `folderIdx = index(["folder","collection","space"])`, `tagsIdx = index(["tags","tag"])`. Set `item.tags = split(value(tagsIdx))`. Folder name → can't resolve to id here; expose it. **Fix**: return a richer result or add a transient folder-name. KISS option: change `parseCSV` → `parseCSVWithFolders(_:) -> [(item: VaultItem, folderName: String?)]`, keep `parseCSV` as a thin wrapper dropping folder names (back-compat for any other caller). Importer uses the rich variant.
  - `PortableItem`: add `var tags: [String]` + `var folderName: String?` (both optional-decoded for old backups). `exportEncrypted` fills them (needs id→name map param, mirror CSV). `importEncrypted` returns items + folder names for the importer to resolve.
- ImportExport feature call sites (LOCATE: `Vaultify/Features/ImportExport/*` — `ExportView.swift` referenced earlier; find the import view): pass `folderNames` map on export; on import, after building items, resolve folder names → ids (match `repository.folders` by name, else `addFolder`), then `assign`. Build the name→id map once.
- `Vaultify/Services/Sync/CloudSyncService.swift`:
  - Add `folderRecordType = "VaultFolder"`.
  - `push()`: also push dirty `FolderRecord`s (`store.allFolderRecords().filter(\.dirty)` → `ckFolderRecord(from:)` → save → `markFolderSynced`).
  - `pull()`: also query `folderRecordType`, `applyFolder(_:)`.
  - Add `ckFolderRecord(from:)` (sealed, iconAsset, colorRaw, sortIndex as Int64, createdAt, updatedAt, deletedAt) + `applyFolder(_:)` → `store.upsertFolderFromRemote(...)`.
- `VaultifyCore/Store/VaultStore.swift`:
  - Add `allFolderRecords()`, `folderRecord(id:)`, `upsertFolderFromRemote(...)` (LWW by updatedAt, mirror `upsertFromRemote` line 41-62), `markFolderSynced(_:changeTag:)`.
- `docs/codebase-summary.md` — add a "Vault Organization (Folders & Tags)" section: model (`Folder`/`FolderRecord`/`FolderSecret`/`FolderColor`, `tags` in `ItemSecret`, `lastUsedAt` column), repository API, Home dashboard, sealed-vs-plaintext boundary, CloudKit folder sync (compile-gated), CSV columns.

## Implementation Steps
1. **i18n**: collect every new literal from Phases 03–04; add to `Localizable.xcstrings` with en + vi (set vi state `translated`). Verify the "Spaces"/"Nhóm" key drives all display labels.
2. **CSV export**: extend `makeCSV` signature with `folderNames` map; update the export caller to pass `Dictionary(uniqueKeysWithValues: repository.folders.map { ($0.id, $0.name) })`.
3. **CSV import**: add folder/tags column parsing; add `parseCSVWithFolders`; update the import caller to resolve folder names → ids (match/create) and `assign` + set tags.
4. **Encrypted backup**: extend `PortableItem` (+tags +folderName, optional-decode); update export/import + caller name-resolution (reuse step 3's resolver).
5. **CloudKit**: add folder record type + push/pull/map/apply in `CloudSyncService`; add `VaultStore` folder sync helpers. Keep everything inside the existing `isConfigured`/`settings.iCloudSyncEnabled` guards (no new gating needed; `sync()` already early-returns when off).
6. **Docs**: update `docs/codebase-summary.md` (and `README.md` feature list if it enumerates features).
7. `tuist generate --no-open` if any new file added (most are edits; no new file strictly required here).
8. `make check`; if feasible, a `VAULTIFY_ICLOUD` compile smoke (optional — CI builds without the flag, so guard correctness by code review since simulator can't provision iCloud).

## Todo List
- [ ] Add all new strings to `Localizable.xcstrings` (en + vi), incl. "Spaces"/"Nhóm"
- [ ] CSV export: folder + tags columns (id→name map param)
- [ ] CSV import: parse folder/tags; match-or-create folders by name; assign + set tags
- [ ] Encrypted backup `PortableItem`: +tags +folderName (optional-decode) + caller resolution
- [ ] CloudKit: `FolderRecord` push/pull/map/apply behind existing guards
- [ ] `VaultStore` folder sync helpers (allFolderRecords/upsertFolderFromRemote/markFolderSynced)
- [ ] Update `docs/codebase-summary.md` (+ README feature list)
- [ ] `tuist generate` if needed; `make check` passes

## Success Criteria
- Build/runtime: no missing-VI warnings for new keys; toggling app language shows VI for all new UI.
- Export CSV → reopen: `folder` + `tags` columns present and correct; re-import recreates folders by name and restores tags.
- Encrypted backup export→import preserves tags + folder assignment (by name).
- With `VAULTIFY_ICLOUD` defined + iCloud signed in, a folder created on one device appears on another; delete tombstone propagates; OFF by default = zero CloudKit calls.
- `docs/codebase-summary.md` reflects the feature. `make check` green.

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Missing VI translation ships → release-blocker bug | Med | High | Step 1 audits every new literal; Phase 06 grep for new `Text(`/keys without vi. |
| `PortableItem` non-optional new field breaks old encrypted backup decode | Med | High | Optional + `decodeIfPresent`; test old-backup import in Phase 06. |
| Folder name collision on import (two folders same name) | Low | Med | Match first by name; if multiple, pick lowest sortIndex; document. CSV/backup carry name not id by design. |
| CloudKit folder schema absent in CKContainer → pull error | Low | Med | First push creates the record type lazily (CloudKit dev schema); pull tolerates empty. Off by default limits blast radius. |
| `makeCSV`/`parseCSV` signature change breaks other callers | Med | Med | Enumerate callers (grep `makeCSV`/`parseCSV` across `Vaultify/`); keep thin back-compat `parseCSV` wrapper. |
| Importer can't reach repository (VaultBackup is key-free/nonisolated) | Med | Med | Resolution lives in the @MainActor import screen, not VaultBackup; VaultBackup only returns name hints. |

## Security Considerations
- CSV export is plaintext by nature (existing behavior) — folder names + tags will be in the clear in exported CSV; this matches the existing CSV trade-off (passwords already exported plaintext). Encrypted backup keeps everything sealed.
- CloudKit folder records upload only sealed name + non-secret presentation metadata (icon/color/sortIndex) — zero-knowledge preserved (mirrors item sync uploading sealed blobs).
- Tags never leave the sealed item payload except in plaintext CSV (same caveat as above).

## Open Question (resolve during impl)
- Confirm the exact import-screen file under `Vaultify/Features/ImportExport/` (export side seen as `ExportView.swift`); the import counterpart is where folder-name resolution must live.

## Next Steps
- Phase 06: tests + verification (model round-trip incl. legacy decode, repo CRUD/reassign/counts, tag aggregation, CSV/backup round-trip), `make check`, DEBUG file-based runtime self-test.
