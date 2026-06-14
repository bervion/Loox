# Phase 06 — Items Tab + Archive + Category Lists

## Context Links
- Folder list pattern to reuse: `Vaultify/Features/Vault/FolderItemsScreen.swift` (sorted item List)
- Spaces grid/section: `Vaultify/Features/Vault/SpacesSection.swift`
- Folder mgmt: `Vaultify/Features/Folders/ManageFoldersScreen.swift`; add-folder UI in there
- Tag list: `Vaultify/Features/Vault/TagItemsScreen.swift`; tags source `+Folders.allTags()`
- Trash (relabel): `Vaultify/Features/Vault/TrashScreen.swift` (navTitle "Trash" → "Recently Deleted")
- Categories: `VaultifyCore/Models/ItemCategory.swift` (8 cases, `title`, `iconAsset`)
- Phase 2 accessors: `items(inFolder:)`, `items(withTag:)`, `archivedItems`, counts, `allTags()`

## Overview
- **Priority:** P1
- **Status:** pending
- **Depends:** 1 (icons), 2 (archivedItems + counts), 3 (tab shell).
- New `ItemsScreen` (organization browser, a `List`): **Spaces** (all spaces + count + a "Create Space"
  row at section end), **Categories** (each `ItemCategory` + count → category-filtered list), **Tags**
  (all tags → TagItemsScreen), plus standalone rows **Archive** → `ArchiveScreen` and **Recently
  Deleted** → relabeled `TrashScreen`. Adds `ArchiveScreen` and a generic category-filtered list.

## Key Insights
- `FolderItemsScreen` is a clean, reusable "filtered item List with sort + empty-state" (`:18-42`).
  The category-filtered list and ArchiveScreen are the same shape with a different source array →
  **generalize into one reusable `ItemListScreen(title:items:showSpace:)`** rather than 3 near-copies
  (DRY). FolderItemsScreen/TagItemsScreen can either keep their thin wrappers or fold in.
- Category counts: there's no `count(for category:)` accessor today — derive inline
  (`items.filter { $0.category == category }.count`) or add a tiny accessor. Items is archived-excluded
  (Phase 2), so counts naturally exclude archived/trashed.
- "Create Space" row: `ManageFoldersScreen` already owns folder creation. The row can present the same
  add-folder flow used there (sheet/alert) — reuse it; don't duplicate folder-create logic.
- TagItemsScreen + FolderItemsScreen pushes are currently registered in `VaultListScreen`'s
  `navigationDestination(for: VaultRoute.self)` (`VaultListScreen.swift:52-58`). The Items tab needs its
  own NavigationStack + the same `VaultRoute` destinations + a new route/destination for Archive +
  category. Extend `VaultRoute` (Phase 3 mentioned a shared destination helper).
- Archive area: archive ≠ trash. ArchiveScreen lists `repository.archivedItems` with **unarchive**
  (and optionally trash) swipe actions — mirror TrashScreen's restore/delete shape but call
  `unarchive`/`moveToTrash`. No "empty"/purge action (archive doesn't auto-purge).

## Requirements
**Functional:**
- ItemsScreen List with sections: Spaces (rows: FolderBadge + name + count → FolderItemsScreen; last
  row "Create Space"), Categories (rows: icon + title + count → category list), Tags (rows → tag list).
- Standalone rows: Archive (→ ArchiveScreen), Recently Deleted (→ TrashScreen relabeled).
- ArchiveScreen: lists archived items; unarchive (+ optionally move-to-trash) per row; empty-state.
- Category list: items of one category, sorted, with empty-state.
- TrashScreen navTitle + entry label → "Recently Deleted" (localized).

**Non-functional:** localized EN+VI; Polaris icons (`Icons.archive`, `Icons.folder`, `Icons.hashtag`,
`Icons.trash`, category `iconAsset`); files <200 LOC; reuse the generic list.

## Architecture
**Data flow:** `ItemsScreen` reads `env.repository.{folders, items (for counts), allTags()}` +
`archivedItems` count for the Archive row badge (optional). Section rows push `VaultRoute` cases into the
Items NavigationStack. Category route carries an `ItemCategory`; folder/tag reuse existing cases.
- Extend `VaultRoute` (`VaultRoutes.swift:5-9`): add `case category(ItemCategory)` and `case archive`.
  `ItemCategory` is `Hashable`/`Identifiable` (verify it conforms to Hashable for the enum assoc value;
  it's `CaseIterable, Identifiable` — add `Hashable` if missing).
- Shared `ItemListScreen` renders any `[VaultItem]` with title/sort/empty-state (generalized
  FolderItemsScreen). Category destination → `ItemListScreen(title: category.title, items:
  items(ofCategory:))`.

## Related Code Files
**Create:**
- `Vaultify/Features/Items/ItemsScreen.swift` (≤170 LOC) — the tab body (List + sections + standalone
  rows + own NavigationStack + destinations).
- `Vaultify/Features/Items/ArchiveScreen.swift` (≤90 LOC) — archived items + unarchive/trash actions.
- `Vaultify/Features/Items/ItemListScreen.swift` (≤90 LOC) — generic filtered list (title + items +
  sort + empty-state), reused by category list (and optionally folder/tag).

**Modify:**
- `Vaultify/Features/Vault/VaultRoutes.swift` — add `case category(ItemCategory)`, `case archive` to
  `VaultRoute`; ensure `ItemCategory: Hashable`.
- `VaultifyCore/Models/ItemCategory.swift` — add `Hashable` conformance if not present (for route).
- `Vaultify/Features/Vault/TrashScreen.swift` — navTitle "Trash" → "Recently Deleted" (localized); keep
  logic. (Entry label set in ItemsScreen.)
- `Vaultify/Features/Main/MainTabView.swift` — Items tab → `ItemsScreen()` (from Phase 3 stub).
- `Vaultify/Data/Repositories/VaultRepository+Folders.swift` — optional `items(ofCategory:)` +
  `count(forCategory:)` thin accessors (or inline in ItemsScreen).
- `Vaultify/Features/Folders/ManageFoldersScreen.swift` — expose its add-folder flow for the
  "Create Space" row to reuse (or ItemsScreen presents the same sheet).

**Delete:** none here (FolderItemsScreen/TagItemsScreen may be folded into ItemListScreen — optional
cleanup; keep if their per-folder tint / per-tag title differs enough to warrant thin wrappers).

## Implementation Steps
1. Add `ItemCategory: Hashable`; extend `VaultRoute` with `.category` + `.archive`.
2. Create generic `ItemListScreen` (lift FolderItemsScreen's body; param: title, items, showSpace, sort).
3. Create `ArchiveScreen` (List of `archivedItems`; swipe unarchive + move-to-trash; empty-state).
4. Create `ItemsScreen`: Spaces section (+ Create Space row), Categories section (count → category list),
   Tags section, standalone Archive + Recently Deleted rows; own NavigationStack + destinations
   (folder/tag/category/archive/trash/itemDetail).
5. Relabel TrashScreen → "Recently Deleted".
6. Wire Items tab in MainTabView.
7. `tuist generate` + `make check` green.

## Todo List
- [ ] ItemCategory: Hashable; VaultRoute: .category + .archive
- [ ] Generic ItemListScreen
- [ ] ArchiveScreen (unarchive/trash, no purge)
- [ ] ItemsScreen (Spaces+Create, Categories, Tags, Archive row, Recently Deleted row)
- [ ] TrashScreen relabel → Recently Deleted
- [ ] MainTabView Items → ItemsScreen
- [ ] `tuist generate` + `make check` green

## Success Criteria
- Items tab lists Spaces (with counts + Create Space), Categories (with counts), Tags, and the two
  standalone rows; each navigates correctly.
- Category list shows only that category's live items; Archive shows archived items with unarchive.
- Recently Deleted = existing trash, relabeled.
- `make check` green.

## Risk Assessment
| Risk | L×I | Mitigation |
|---|---|---|
| `ItemCategory` not Hashable → can't be a `VaultRoute` assoc value | Med×Med | Add `Hashable` (enum w/ String-ish cases → trivial). Verify compile. |
| Empty categories clutter the Categories section | Low×Low | Open Q (phase-09): show all vs only non-empty. Default recommend: show only categories with count > 0 (matches HomeDashboard's `visibleCategories`). |
| Create-Space flow duplicated from ManageFoldersScreen | Low×Med | Reuse ManageFoldersScreen's add sheet/flow; don't re-implement folder create. |
| FolderItemsScreen/TagItemsScreen drift if folded into ItemListScreen | Low×Low | Keep thin wrappers if their tint/title specialization matters; only fold if behavior identical. |
| Items tab nav destinations diverge from Home/Search stacks | Med×Low | Shared `navigationDestination` helper (Phase 3) used by all stacks. |

## Security Considerations
- Counts/lists read archived-excluded `items` (Phase 2). ArchiveScreen intentionally surfaces archived
  items (still encrypted at rest; decrypted in-memory like any item). Rows show no secrets.

## Next Steps
Phase 7 adds pin/archive row + detail actions (ArchiveScreen's unarchive complements them). Phase 8
localizes all new strings ("Create Space", "Archive", "Recently Deleted", category section header).
