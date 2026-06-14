# Phase 03 — Editor & Folder Management UI

## Context Links
- Overview: [plan.md](plan.md)
- Depends on: [Phase 02](phase-02-repository-folders-recents-tags.md)
- Editor: `Vaultify/Features/ItemEditor/ItemEditorScreen.swift` (Form-based sheet, full read 2026-06-14)
- Editor field row pattern: `Vaultify/Features/ItemEditor/EditorFieldRow.swift` (referenced line 49)
- Icon constants: `Vaultify/DesignSystem/PolarisIcon.swift` (`enum Icons`)
- Colors: `Vaultify/DesignSystem/VaultColors.swift` (`dynamic(light:dark:)`)
- Category title idiom (`.inAppLocalized`): `VaultifyCore/Models/ItemCategory.swift:17-29`

## Overview
- **Priority**: P1
- **Status**: ✅ done (compiles app + extension via `make check`; strings localized EN+VI)
- Add a folder picker + tag input to `ItemEditorScreen`, build a reusable icon+color picker component, and a folder create/edit/manage screen. This is the input side; Phase 04 is the browse side.

## Key Insights
- `ItemEditorScreen` is a `Form` with `@State private var draft: VaultItem` (line 10). Since `draft.folderId` and `draft.tags` now exist (Phase 01), the picker/input just bind to `$draft` and `save()` (line 120-132) already persists via `repository.add/update` — no new save path.
- Folder selection needs the folders list → read `env.repository.folders`. A new folder can be created inline from the picker ("New Space…") → calls `repository.addFolder` then selects it.
- Tag input: keep KISS — a chip editor that splits on comma/return, dedups, trims. No autocomplete in v1 (could suggest from `repository.allTags()` as a nice-to-have, but YAGNI for v1 unless trivial).
- **iOS-26 `TextField` trap**: the tag entry `TextField` and folder-name `TextField` titles MUST use `LocalizedStringKey` (string literal is fine — SwiftUI auto-extracts), NOT `LocalizedStringResource`. Do not pass `.inAppLocalized` into a `TextField(_:text:)` title.
- The icon+color picker is reused by BOTH "create folder" and "edit folder" → one component, parameterized by bindings.
- Display label "Spaces"/"Nhóm" comes from the catalog (Decision B) — define one `LocalizedStringResource` (e.g. via a `FolderStrings` helper or inline `Text("Spaces")`) used everywhere so it's a 1-line catalog change.

## Requirements
**Functional**
- Editor: a "Space" row (shows current folder name + color dot, or "None"); tapping opens a folder picker listing Unfiled + all folders + "New Space…".
- Editor: a "Tags" section with a chip editor (add via text, remove via tap-x).
- Icon+color picker component: grid of ~24 curated Polaris icons (single-select) + row of ~10 `FolderColor` swatches (single-select). Live preview of the resulting folder badge.
- Folder management screen: list folders (badge + name + item count), reorder (sortIndex), create, edit, delete (with reassign confirmation).
- Delete folder uses `PolarisModal`? — project uses `confirmationDialog` in detail/editor (e.g. `ItemDetailScreen.swift:41`). **Match existing pattern**: use SwiftUI `confirmationDialog` for destructive confirm (the Polaris-Flutter modal rules in global CLAUDE.md do NOT apply to this native app). Confirm copy: "Delete this Space? Items move to Unfiled."

**Non-functional**
- All strings localized EN+VI (Phase 05 fills the catalog; add literals here so auto-extraction picks them up).
- Components < 200 LOC each; split picker into its own file.

## Architecture
```
Vaultify/Features/Folders/                 (new feature folder)
  FolderPickerSheet.swift        sheet: pick Unfiled | folder | "New Space…"; binds folderId
  FolderEditorSheet.swift        create/edit one folder: name TextField + IconColorPicker + save/delete
  IconColorPicker.swift          reusable: icon grid (~24) + color row (~10) + live badge preview
  FolderBadge.swift              small view: rounded tile, FolderColor bg + Polaris icon (reused in grid/rows)
  CuratedFolderIcons.swift       static [String] of ~24 curated Polaris icon names
  ManageFoldersScreen.swift      list + reorder + create + edit + delete
Vaultify/Features/ItemEditor/
  ItemEditorScreen.swift (modify): + Space row (-> FolderPickerSheet) + Tags section (chip editor)
  TagChipEditor.swift (new):      chip add/remove bound to $draft.tags
```
Data flow: editor `$draft.folderId`/`$draft.tags` ⇄ pickers; folder CRUD → `env.repository.addFolder/updateFolder/deleteFolder`. `FolderColor → Color` via `VaultColors.dynamic(light: c.light, dark: c.dark)` (app-layer resolution; core stays UI-free per Phase 01).

## Related Code Files
**Create**
- `Vaultify/Features/Folders/FolderBadge.swift` — `FolderBadge(icon: String, color: FolderColor, size: CGFloat)`; rounded-rect tile, `VaultColors.dynamic` bg at suitable opacity + `PolarisIcon(icon)` tinted. Reused in grid (P04), rows, previews.
- `Vaultify/Features/Folders/CuratedFolderIcons.swift` — `enum CuratedFolderIcons { static let all: [String] = [...] }` (~24 verified names: ic_folder, ic_work, ic_organization, ic_team, ic_bank, ic_globe, ic_home, ic_person, ic_wallet, ic_money, ic_product, ic_wrench, ic_database_connect, ic_book_open, ic_target, ic_chart_line, ic_food, ic_phone, ic_mail, ic_calendar, ic_channels, ic_key, ic_shield_check_mark, ic_hashtag-excluded — pick 24 sensible ones from the inventory).
- `Vaultify/Features/Folders/IconColorPicker.swift` — `@Binding var icon: String`, `@Binding var color: FolderColor`; `LazyVGrid` of icons (selected = ring), `HStack` of color swatches (selected = ring), top live `FolderBadge` preview.
- `Vaultify/Features/Folders/FolderEditorSheet.swift` — create OR edit: `@State name`, `@State icon`, `@State color`; `TextField` (LocalizedStringKey title) + `IconColorPicker`; Save → `addFolder`/`updateFolder`; in edit mode a Delete button → confirmationDialog → `deleteFolder`.
- `Vaultify/Features/Folders/FolderPickerSheet.swift` — `@Binding var folderId: String?`; list: "None (Unfiled)" + each folder (FolderBadge + name + check on selection) + "New Space…" row → presents `FolderEditorSheet` (create), then auto-selects the new folder id.
- `Vaultify/Features/Folders/ManageFoldersScreen.swift` — `List` of folders (FolderBadge + name + `itemCount`), `.onMove` → persist sortIndex via `updateFolder`, toolbar "+" → `FolderEditorSheet` create, row tap → `FolderEditorSheet` edit.
- `Vaultify/Features/ItemEditor/TagChipEditor.swift` — `@Binding var tags: [String]`; wrap-flow of `#tag ✕` chips + a `TextField` that on submit/comma splits, trims, lowercases?, dedups, appends.

**Modify**
- `Vaultify/Features/ItemEditor/ItemEditorScreen.swift`:
  - Add a `Section` (after Fields, ~line 71) with a Space row: `Button { showFolderPicker = true }` showing current folder badge+name or "None".
  - Add a Tags `Section` containing `TagChipEditor(tags: $draft.tags)`.
  - Add `@State private var showFolderPicker = false` + `.sheet(isPresented:)` → `FolderPickerSheet(folderId: $draft.folderId)`.
- `Vaultify/DesignSystem/PolarisIcon.swift` — add any new name constants used as chrome (e.g. `static let hashtag = "ic_hashtag"`, `static let organization = "ic_organization"` if referenced by constant rather than literal). Literals also fine; prefer constants for reused chrome.

## Implementation Steps
1. `FolderBadge` + `CuratedFolderIcons` (verify each icon exists under `Assets.xcassets/PolarisIcons/`).
2. `IconColorPicker` with live `FolderBadge` preview; selection rings via overlay.
3. `FolderEditorSheet` (create+edit modes via optional `Folder?`); wire `addFolder`/`updateFolder`/`deleteFolder`; Delete confirmation copy "Items move to Unfiled".
4. `FolderPickerSheet` binding `folderId`; include "New Space…" → on create, set `folderId` to the new folder's id (read back from `repository.folders` by matching the created id).
5. `ManageFoldersScreen` list + `.onMove` (recompute sortIndex sequentially, persist each via `updateFolder`) + create/edit entry points.
6. `TagChipEditor` (split on `,`/return, trim, dedup case-insensitively, drop empties; chips use `ic_hashtag` + neutral bg).
7. Wire editor: Space row + Tags section + sheet. Confirm `save()` persists folderId/tags (no change needed — `draft.secret` carries them).
8. Add a path to reach `ManageFoldersScreen` (toolbar/menu) — likely from Home (Phase 04) AND/or Settings; for this phase, expose it from the editor's folder picker ("Manage Spaces") at minimum.
9. `tuist generate --no-open` (7+ new files).
10. `make check`.

## Todo List
- [ ] `FolderBadge.swift` + verify curated icon names exist
- [ ] `CuratedFolderIcons.swift` (~24 names)
- [ ] `IconColorPicker.swift` (grid + swatches + live preview)
- [ ] `FolderEditorSheet.swift` (create/edit/delete + reassign confirm)
- [ ] `FolderPickerSheet.swift` (bind folderId + "New Space…")
- [ ] `ManageFoldersScreen.swift` (list + reorder + CRUD entry)
- [ ] `TagChipEditor.swift` (chip add/remove/dedup)
- [ ] Modify `ItemEditorScreen`: Space row + Tags section + sheet
- [ ] `tuist generate --no-open`
- [ ] `make check` passes; manual: create folder, assign item, add tags, edit, delete→reassign

## Success Criteria
- Create a folder from the editor's picker → it appears and the item gets assigned on save.
- Edit a folder's icon/color → reflected everywhere via `FolderBadge`.
- Add/remove tags in the editor → persisted (verify via detail in Phase 04 / reopen editor).
- Delete a folder from `ManageFoldersScreen` → confirmation shown, members become Unfiled, items intact.
- Reorder folders → order persists across relaunch.
- No SF Symbols; all icons Polaris. `make check` green.

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| `TextField` title typed as `LocalizedStringResource` → iOS-26-only API, CI build fail | Med | High | Spec: use `LocalizedStringKey`/string literal for all `TextField`/`SecureField` titles. Call out in review. |
| Curated icon name typo → blank tile at runtime (asset catalogs don't error on missing) | Med | Med | Step 1 verifies each name against `Assets.xcassets/PolarisIcons/`; Phase 06 optional asset-existence check. |
| "New Space…" race: created folder not yet in `folders` when selecting | Low | Med | `addFolder` calls `reload()` (Phase 02) before returning; select by the known new id. |
| Component files >200 LOC | Med | Low | One concern per file (badge/picker/editor/manage/chips split as listed). |
| Tag dedup inconsistent (case) vs. display | Low | Low | Decide: store as entered, dedup case-insensitively; render verbatim. Document in code. |

## Security Considerations
- Folder name typed in `FolderEditorSheet` is sealed on save (Phase 02 `addFolder`/`updateFolder`). Never logged.
- Tags entered are sealed inside the item payload on `save()`.
- No secret values pass through the new pickers.

## Next Steps
- Phase 04 surfaces folders/tags/recents on the Home dashboard and the folder-filtered list (with color tint), and wires recents tracking on copy/reveal.
