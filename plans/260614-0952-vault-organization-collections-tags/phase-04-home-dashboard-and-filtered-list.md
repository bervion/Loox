# Phase 04 — Home Dashboard & Folder-Filtered List

## Context Links
- Overview: [plan.md](plan.md)
- Depends on: [Phase 02](phase-02-repository-folders-recents-tags.md), [Phase 03](phase-03-editor-and-folder-management.md)
- Screen to rebuild: `Vaultify/Features/Vault/VaultListScreen.swift` (full read 2026-06-14)
- Row: `Vaultify/Features/Vault/VaultItemRow.swift`
- Detail (copy/reveal lives here): `Vaultify/Features/ItemDetail/ItemDetailScreen.swift`
- Copy call sites: `DetailFieldRow.swift:130-132`, `ProtectedFieldRow.swift:131-132` (both `env.clipboard.copy`)
- Tab host: `Vaultify/Features/Main/MainTabView.swift`

## Overview
- **Priority**: P1
- **Status**: ✅ done (compiles app + extension via `make check`; strings localized EN+VI)
- Rebuild `VaultListScreen` into a **Home dashboard**: Quick Access (Favorites + Recently used), Spaces grid, Tags row. Add a folder-filtered list with folder-color tint. Wire recents tracking (`markUsed`) on copy/reveal. This is the user-visible payoff of Phases 01–03.

## Key Insights
- Current `VaultListScreen` (line 6) is a `NavigationStack` with grouped-by-category `List`, a `searchable`, filter/sort/add toolbar, `navigationDestination(for: String.self)` → `ItemDetailScreen`, and `.sheet` → editor. We KEEP: search, add, trash access, detail navigation. We REPLACE: the category-grouped landing body with dashboard sections.
- **Preserve existing behaviors** when not searching: empty state (line 102-110), search results (line 75-83). Search stays global over all items.
- The dashboard is scrollable sections, not a single `List`. Use `ScrollView` + `LazyVStack`/`LazyVGrid` (Spaces grid) OR a `List` with custom sections — Spaces grid argues for `ScrollView`. Keep navigation via `NavigationLink(value:)`/`navigationDestination`.
- **Folder-filtered list with tint** (Decision C): tapping a Space pushes a list of its items; the header/accent is tinted to the folder's `FolderColor`. New screen `FolderItemsScreen(folderId:)` reusing `VaultItemRow`. Tint = `VaultColors.dynamic(light:dark:)` from the folder color applied to section header / nav accent (avoid global `.tint` leaking; scope to the screen).
- **Tag-filtered list**: tapping a tag chip pushes `TagItemsScreen(tag:)` (or reuse a generic filtered list). Neutral styling (no per-tag color, Decision A).
- **Recents tracking hook** (Decision E): copy happens in leaf rows that DON'T know the item id. Cleanest minimal-coupling approach: `ItemDetailScreen` already holds `item` (line 13). Pass an `onCopy` closure down `DetailFieldRow`/`ProtectedFieldRow` that calls `env.repository.markUsed(item)`. OR: since both leaf rows call `env.clipboard.copy`, add an optional `onCopy` to `ClipboardService.copy(...)` — NO, clipboard is item-agnostic. **Chosen**: thread an `onUsed: () -> Void` from `ItemDetailScreen` → `DetailFieldRow`/`ProtectedFieldRow`, invoked in their `copy()`/reveal paths; `ItemDetailScreen` binds it to `repository.markUsed(item)`. Reveal also counts as "used" (Decision E says copy/reveal) → call in `ProtectedFieldRow`'s reveal action too.
- Long-press a Space card → "manage" (Decision C) → `ManageFoldersScreen` or a context menu (Edit/Delete). Use `.contextMenu` on the card (Edit → `FolderEditorSheet`, Delete → confirm).

## Requirements
**Functional**
- Home sections IN ORDER: (1) Quick Access — Favorites (existing favorite items) + Recently used (`recentlyUsed(limit:~8)`); (2) Spaces grid — cards (FolderBadge + name + `itemCount`), tap → `FolderItemsScreen`, long-press/context → manage; an "Unfiled" pseudo-card when `unfiledCount > 0`; an "Add Space" affordance; (3) Tags row — horizontal `#` chips from `allTags()`, tap → `TagItemsScreen`.
- Search unchanged (global, over all items, current `searchResults` logic line 18-20).
- `FolderItemsScreen(folderId:)`: tinted header, list of `items(inFolder:)`, sort (reuse updated/title), swipe actions (trash/favorite) as today.
- `TagItemsScreen(tag:)`: list of `items(withTag:)`, neutral.
- Recents: every copy AND every reveal of a protected field → `repository.markUsed(item)`.
- Entry to `ManageFoldersScreen` from Home (e.g. "Spaces" section header "Edit"/"+").

**Non-functional**
- All new strings EN+VI (Phase 05). Spaces label from catalog ("Spaces"/"Nhóm").
- Empty states: no folders yet → Spaces section shows a single "Create your first Space" card (don't hide the feature). No tags → hide Tags row. No recents → hide Recently used subsection (Favorites may still show).
- Keep `VaultListScreen` body composable; extract sections into subviews/files to stay < 200 LOC.

## Architecture
```
Vaultify/Features/Vault/
  VaultListScreen.swift (rebuild): NavigationStack; if searching -> searchList; else HomeDashboard; toolbar(add/trash/manage); destinations
  HomeDashboard.swift (new):       ScrollView { QuickAccessSection; SpacesSection; TagsSection }
  QuickAccessSection.swift (new):  Favorites + Recently used (horizontal cards or compact rows)
  SpacesSection.swift (new):       LazyVGrid of SpaceCard + Unfiled + Add; header with Edit/+
  SpaceCard.swift (new):           FolderBadge + name + count; contextMenu(Edit/Delete)
  TagsSection.swift (new):         horizontal ScrollView of TagChip (read-only) -> TagItemsScreen
  FolderItemsScreen.swift (new):   folder-tinted filtered list (reuse VaultItemRow + swipe actions)
  TagItemsScreen.swift (new):      tag filtered list (neutral)
Vaultify/Features/ItemDetail/ (modify):
  ItemDetailScreen.swift:          pass onUsed closure -> markUsed(item)
  DetailFieldRow.swift:            add onUsed; call in copy()
  ProtectedFieldRow.swift:         add onUsed; call in copyText() AND reveal action
```
Tint scoping: `FolderItemsScreen` computes `let accent = VaultColors.dynamic(light: color.light, dark: color.dark)` and applies to its section header / icons locally (NOT a global environment tint that bleeds back to Home).

## Related Code Files
**Create**: `HomeDashboard.swift`, `QuickAccessSection.swift`, `SpacesSection.swift`, `SpaceCard.swift`, `TagsSection.swift`, `FolderItemsScreen.swift`, `TagItemsScreen.swift` (all under `Vaultify/Features/Vault/`).
**Modify**:
- `Vaultify/Features/Vault/VaultListScreen.swift` — replace `groupedList` (line 57-73) usage in `body` with `HomeDashboard()`; keep `searchList`, `emptyState`, toolbar, `navigationDestination(for: String.self)`, editor/trash sheets; add destinations for folder/tag screens (e.g. `navigationDestination(for: FolderRoute.self)` / `TagRoute.self`, or push via `NavigationLink(value:)`). Decide on a small `enum`/`struct` route type (Hashable) for folder/tag navigation.
- `Vaultify/Features/ItemDetail/ItemDetailScreen.swift` — add `onUsed` wiring: where it builds `DetailFieldRow` (line 85-87), pass `onUsed: { if let item { try? env.repository.markUsed(item) } }` (item is non-nil in that scope).
- `Vaultify/Features/ItemDetail/DetailFieldRow.swift` — add `var onUsed: () -> Void = {}`; call `onUsed()` inside `copy()` (line 130).
- `Vaultify/Features/ItemDetail/ProtectedFieldRow.swift` — add `var onUsed: () -> Void = {}`; call in `copyText()` (line 131) AND in the reveal path (line 84 area). Thread `onUsed` from `DetailFieldRow` (which constructs `ProtectedFieldRow` at DetailFieldRow.swift:26).

## Implementation Steps
1. Define route types (e.g. `struct FolderRoute: Hashable { let id: String }`, `struct TagRoute: Hashable { let tag: String }`) — small, in `VaultListScreen.swift` or a `Routes.swift`.
2. Build leaf views: `SpaceCard` (FolderBadge + name + count + contextMenu), `TagChip` (reuse from Phase 03 if extracted, else inline read-only chip).
3. Build `SpacesSection` (LazyVGrid 2–3 cols; Unfiled pseudo-card when count>0; Add card/"Edit"); `QuickAccessSection` (Favorites + recents); `TagsSection` (horizontal chips; hide when empty).
4. Compose `HomeDashboard` (ScrollView + the three sections in order; respect bottom inset for tab bar).
5. Build `FolderItemsScreen(folderId:)` — title = folder name, tinted accent, list of `items(inFolder:)` with existing swipe actions (copy from `VaultListScreen.rows` line 85-100), sort menu optional.
6. Build `TagItemsScreen(tag:)` — neutral list of `items(withTag:)`.
7. Rebuild `VaultListScreen.body`: searching → `searchList`; empty vault → `emptyState`; else `HomeDashboard`. Register `navigationDestination` for `FolderRoute`/`TagRoute`/`String`(item). Keep toolbar (add/trash) + add "Manage Spaces" entry.
8. Wire recents: add `onUsed` to `DetailFieldRow`/`ProtectedFieldRow`, thread from `ItemDetailScreen`; ensure reveal + copy both call it.
9. `tuist generate --no-open` (7+ new files).
10. `make check`; manual pass: dashboard renders, tap Space → tinted list, tap tag → list, copy/reveal → item climbs to Recently used.

## Todo List
- [ ] Route types for folder/tag navigation
- [ ] `SpaceCard` + context menu (Edit/Delete)
- [ ] `SpacesSection` (grid + Unfiled + Add/Edit)
- [ ] `QuickAccessSection` (Favorites + Recently used)
- [ ] `TagsSection` (horizontal chips, hide when empty)
- [ ] `HomeDashboard` composition
- [ ] `FolderItemsScreen` (tinted filtered list + swipe actions)
- [ ] `TagItemsScreen` (neutral filtered list)
- [ ] Rebuild `VaultListScreen.body` (keep search/empty/toolbar/destinations)
- [ ] Wire `onUsed` → `markUsed` on copy AND reveal
- [ ] `tuist generate --no-open`
- [ ] `make check` + manual dashboard/recents verification

## Success Criteria
- Home shows Quick Access → Spaces grid → Tags row in that order; sections hide gracefully when empty (except Spaces always offers create).
- Tapping a Space opens a list filtered to that folder, header/accent tinted to its color; items not in the folder absent.
- Tapping a tag opens a neutral list of items with that tag.
- Copying or revealing a field bumps the item into "Recently used".
- Search still works globally and unchanged.
- Trash + add still reachable; existing swipe actions preserved. `make check` green.

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Folder tint applied as global `.tint` bleeds into Home/other tabs | Med | Med | Scope tint to `FolderItemsScreen` locally (compute Color, apply to header/icons); no env-wide tint. |
| Rebuilding `VaultListScreen` drops a current behavior (search/empty/trash) | Med | High | Checklist preserves searchList/emptyState/toolbar/destinations explicitly; manual regression pass. |
| Recents hook misses reveal (only copy tracked) | Med | Low | Decision E = copy AND reveal; wire both call sites; note in review. |
| `markUsed` reload churn re-renders dashboard on every copy | Low | Med | Phase 02 `markUsed` patches cache without full reload → `@Observable` updates the one item; dashboard recomputes cheaply. |
| Dashboard `ScrollView` vs `List` perf with many items | Low | Low | Quick Access capped (limit ~8); grids are folder-count sized (small). |
| File > 200 LOC (VaultListScreen) | Med | Low | Sections extracted to separate files. |

## Security Considerations
- Dashboard shows only non-secret metadata (titles/subtitles/favicons/counts/tags) — same exposure as today's list. Folder names shown are already decrypted in-memory (vault unlocked).
- `markUsed` writes timing only (Decision E) — no content, no secret.
- Reveal counting as "used" does not change reveal's own auth/expiry behavior.

## Next Steps
- Phase 05: localize every new string EN+VI, extend import/export + CloudKit for folders, update docs.
