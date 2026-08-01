# Vault list sort/filter/sections + Space terminology + seed icon restyle

Status: implemented + adversarial review applied (13 confirmed findings fixed, 0 refuted).
Branch `feat/vault-list-sort-filter-space-terms-260801` (from origin/main v1.48.0).
Owner request (260801): full-auto, PR -> merge main -> release.

Review fixes on top of the original scope: reversed flag gated on supportsDirection;
SF-era seed icon `sf:lock.fill` folds via `SeedSpaceIcon.dedupeKey` (dedupe-only);
`Folder.displayName` narrowed to `isUntouchedSeed` (name + glyph + blue); search
haystack includes displayName; Search chip-constrained fallback + opaque chip-row
canvas; MacRootView title renders verbatim Text; xcstrings metadata + VI/JA register
(Thường dùng, よく使う項目/最近使った項目); 3 new pin tests.

## Scope

1. **Space terminology**: seeded Space "My Vault"/"Kho của tôi" is wrong context under the
   "Nhóm" (Spaces) section. New catalog key `My Space` (vi "Nhóm của tôi", ja "マイスペース").
   Display-layer mapping: any historical seed name renders as current `appString("My Space")`.
   Stored names NEVER rewritten. Editor sheet + import/export keep raw stored name.
2. **Seed Space icon**: display remap `ic_lock_filled -> dt_lock`, `ic_folder -> dt_folder`
   inside `IconResolver.resolve()` ONLY (keeps `canonical()` consistent on both dedupe sides).
   `IconCatalog.seedSpaceIcon` stored literal unchanged. Update IconCatalogTests pin.
3. **Dedupe hardening**: `mergeDuplicateSeedFolders` name check widens from exact
   `appString("My Vault")` to the frozen historical seed-name set (also fixes the
   pre-existing cross-language / language-switch convergence gap).
4. **Create Space row** (ItemsScreen): drop leading icon; text `Create New Space`
   ("Tạo nhóm mới"); trailing chevron like navRow.
5. **VaultSort v2**: struct key+direction. Keys: Title, Date Created, Date Modified,
   Frequently Used, Recently Used. Direction: Newest/Oldest First (dates), A to Z / Z to A
   (title), none for Frequently Used. Default = Date Modified newest (matches old `.updated`).
   `VaultSort.updated` static kept for HomeScreen.
6. **Month-year sections**: when key is Date Created/Modified, group list into month-year
   `Section`s (in-app locale header via `appResourceLocale`, template yMMMM). Other keys flat.
7. **Category filter**: optional `ItemCategory?` picker in the shared toolbar menu on
   FolderItems/TagItems/FilteredItems (suppressed on ItemListScreen: fixed category).
8. **Shared components**: `VaultSortFilterMenu` (Menu: sort picker + direction picker +
   optional category picker + screen-extra content, single Haptics.tap on change) and
   `VaultItemSections` (flat or month-sectioned rows). Files under Features/Vault/.
9. **Search**: chip row (reuses `FilterChip`, first call site; 44pt hit frame) for category +
   compact sort menu, placed in content area (iOS 26 hides Search nav bar -> toolbar invisible).
   Category = independent post-filter (not injected into SearchOperators; survives the
   zero-result literal fallback). Sort applied at `results` exits + shared section.
   Empty query + active chip = browse that category. Update stale "no chips" doc comment.

## Non-goals

ArchiveScreen/TrashScreen toolbars; syncing lastUsedAt/useCount; widening markUsed capture
(AutoFill); ItemFilter Codable extension; sort persistence across pushes; AutoFill extension
display-name mapping (extension keeps stored names).

## New strings (en key = vi / ja)

My Space = Nhóm của tôi / マイスペース; Date Created = Ngày tạo / 作成日;
Date Modified = Ngày sửa đổi / 変更日; Newest First = Mới nhất trước / 新しい順;
Oldest First = Cũ nhất trước / 古い順; A to Z = A đến Z / AからZ; Z to A = Z đến A / ZからA;
All Categories = Tất cả phân loại / すべてのカテゴリ; Order = Thứ tự / 並び順.
Reused: Sort, Title, Frequently Used (Hay dùng), Recently Used (Dùng gần đây), Categories,
Create New Space, All Spaces, Spaces.

## Verification

- xcstrings edit via OrderedDict roundtrip (indent=2, separators=(',', ': '), no trailing
  newline, never sort_keys); `git diff --stat` sanity; python check new keys have vi+ja.
- `tuist generate` + compile app+extension (iOS Simulator generic) + macOS slice destination.
- Unit tests: VaultifyTests (IconCatalogTests, CloudSyncMergeTests updated for new contracts).
  Known red baseline (2 UI + 3 snapshot) is pre-existing — do not chase.
- Adversarial review workflow over the diff; fix confirmed findings.

## Ship

Conventional commits -> push -> PR -> squash-merge main -> `make release` on main
(runner disk OK: 23Gi free; both self-hosted runners online).
