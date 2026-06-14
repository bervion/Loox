# Phase 04 — Home Tab (personalized dashboard)

## Context Links
- Phase 2 accessors: `pinned`, `frequentlyUsed`, `recentlyCreated`, `recentlyModified`, favorites
- Existing dashboard pieces (reuse/adapt): `Vaultify/Features/Vault/QuickAccessSection.swift`
  (horizontal card group pattern + `QuickAccessCard`), `HomeDashboard.swift`, `SpacesSection.swift`
- Old Home owner being split: `Vaultify/Features/Vault/VaultListScreen.swift`
- Settings entry: `Vaultify/Features/Settings/SettingsScreen.swift`; Generator: `GeneratorScreen.swift`
- Customize Home (Phase 5) feeds section visibility from `SettingsStore`

## Overview
- **Priority:** P1
- **Status:** pending
- **Depends:** 1 (icons), 2 (accessors), 3 (tab shell).
- New `HomeScreen` replacing the old Vault-tab landing. Sections: **Pinned**, **Favorite**, **Recently
  Created**, **Frequently Used** (default ON) + optional **Recently Used**, **Recently Modified**
  (toggled in Phase 5). Header: title + **Settings gear** + **Customize** entry. A **Utilities** section
  with a Generator row (extensible).

## Key Insights
- The existing `QuickAccessSection` already implements the exact "horizontal scrolling compact cards"
  pattern with `QuickAccessCard` (`QuickAccessSection.swift:37-53`) — **reuse `QuickAccessCard`** and
  generalize the `group(title:items:)` builder into a shared section view so each Home section (Pinned,
  Favorite, etc.) is one call (DRY). Don't rebuild card styling.
- Each section is `dashboardRow`-style (full-bleed, separator-hidden, clear bg) like
  `HomeDashboard.swift:69-74` if hosted in a `List`; or use a `ScrollView` + `LazyVStack` for the new
  Home (simpler, no grouped-list chrome). **Recommend ScrollView+LazyVStack** for the personalized Home
  (it's all horizontal card groups + a Utilities list — not a grouped item browser). Items browsing now
  lives on the Items tab (Phase 6), so Home no longer needs the category-grouped List.
- Section visibility:
  - Pinned: show iff `!repository.pinned.isEmpty`.
  - Favorite: show iff any `favorite`.
  - Recently Created: show iff items exist (always has content if vault non-empty).
  - Frequently Used: show iff any item with `useCount > 0`.
  - Recently Used / Modified: optional (Phase 5 toggle) AND non-empty.
- Header gear → `SettingsScreen` (sheet or push). Settings currently wraps its own `NavigationStack`
  (`SettingsScreen.swift:19`) → present as a **sheet** to avoid nested stacks, OR push within Home's
  stack and let Settings drop its inner NavigationStack. **Recommend sheet** (least churn to Settings).

## Requirements
**Functional:**
- HomeScreen renders default-ON sections in locked order (see Open Q for exact order), each a horizontal
  card group of tappable items → `ItemDetailScreen`.
- Optional sections appear only when enabled (Phase 5) and non-empty.
- Utilities section: a row "Password Generator" → existing `GeneratorScreen` (push or sheet).
- Header: localized title ("Home"), Settings gear (→ Settings), Customize entry (→ Phase 5 screen).
- Empty vault → existing empty-state pattern (`VaultListScreen.swift:72-80`) with Add menu.

**Non-functional:** localized strings EN+VI; Polaris icons; amounts N/A; reuse `QuickAccessCard`.

## Architecture
**Data flow:** `HomeScreen` reads `env.repository.{pinned, items.filter(favorite),
recentlyCreated(limit:), frequentlyUsed(limit:), recentlyUsed(limit:), recentlyModified(limit:)}` +
`env.settings` (which optional sections are on) → renders an ordered list of `HomeSection` card groups.
Tapping a card appends `item.id` to Home's NavigationPath → `ItemDetailScreen`.

**Section model (KISS):** an enum `HomeSection { pinned, favorite, recentlyCreated, frequentlyUsed,
recentlyUsed, recentlyModified, utilities }` with `title` (localized) and an `items(from:repository)`
provider. HomeScreen iterates an ordered `[HomeSection]` (default order + optional toggles from
SettingsStore — the persisted order/visibility comes from Phase 5). For THIS phase, hardcode default
order with the 4 default-ON sections + Utilities; Phase 5 makes it data-driven from SettingsStore.

## Related Code Files
**Create:**
- `Vaultify/Features/Home/HomeScreen.swift` (≤150 LOC) — the tab body (NavigationStack lives here per
  Phase 3, or HomeScreen provides content and MainTabView wraps the stack — keep consistent with Phase 3).
- `Vaultify/Features/Home/HomeSection.swift` (≤120 LOC) — `HomeSection` enum + ordered default + a
  reusable horizontal card-group view (generalized from `QuickAccessSection.group`).
- `Vaultify/Features/Home/UtilitiesSection.swift` (≤80 LOC) — Utilities list (Generator row now).

**Modify:**
- `Vaultify/Features/Vault/QuickAccessSection.swift` — extract `QuickAccessCard` to a shared file or
  mark it accessible so HomeSection reuses it (avoid duplicate card). If QuickAccessSection is no longer
  used after the split, fold its card into `HomeSection.swift` and delete the old file.
- `Vaultify/Features/Main/MainTabView.swift` — Home tab → `HomeScreen()` (from Phase 3 stub to real).

**Delete (after migration):**
- `Vaultify/Features/Vault/HomeDashboard.swift` (category-grouped landing) — its item-browsing role
  moves to Items tab (Phase 6); confirm no other referent before deleting.
- `Vaultify/Features/Vault/VaultListScreen.swift` — superseded by HomeScreen + ItemsScreen + SearchScreen.
  Delete only after Phases 3/4/6 cover its responsibilities. Migrate its `addMenu`/`emptyState` to Home.

## Implementation Steps
1. Extract a reusable `QuickAccessCard` + horizontal card-group view (from QuickAccessSection).
2. Create `HomeSection` (enum + title + items provider + default order).
3. Create `UtilitiesSection` (Generator row → GeneratorScreen sheet/push).
4. Create `HomeScreen`: header (title + gear → Settings sheet + Customize entry), ScrollView of the 4
   default sections (Pinned/Favorite/Recently Created/Frequently Used) + Utilities; empty-state + Add menu.
5. Wire Home tab in MainTabView to `HomeScreen`.
6. Delete `HomeDashboard` + `VaultListScreen` once Items (Phase 6) + Search (Phase 3) absorb their roles;
   re-home `addMenu`/`emptyState`.
7. `tuist generate` (new files) + `make check` green.

## Todo List
- [ ] Reusable card-group view + QuickAccessCard
- [ ] HomeSection enum (title + items provider + default order)
- [ ] UtilitiesSection (Generator row)
- [ ] HomeScreen (header gear + Customize + sections + empty-state)
- [ ] MainTabView Home → HomeScreen
- [ ] Migrate addMenu/emptyState; delete HomeDashboard + VaultListScreen
- [ ] `tuist generate` + `make check` green

## Success Criteria
- Home shows the 4 default sections (when non-empty) as horizontal card groups; taps open detail.
- Settings gear opens Settings; Customize entry opens Phase 5 screen; Utilities opens Generator.
- Empty vault shows empty-state + Add menu.
- `make check` green; no orphaned references to deleted screens.

## Risk Assessment
| Risk | L×I | Mitigation |
|---|---|---|
| Deleting VaultListScreen orphans nav destinations (folder/tag/manageFolders/trash) | Med×High | Those destinations move to Items tab (Phase 6) + Home/Search stacks (Phase 3). Grep for `VaultRoute`, `FolderItemsScreen`, `TagItemsScreen`, `ManageFoldersScreen`, `TrashScreen` referents before delete; ensure each has a new home. |
| Settings nested NavigationStack when pushed | Low×Med | Present Settings as a sheet (it owns its own stack at `:19`). |
| Card-group duplication (Home vs old QuickAccess) | Med×Low | Extract one shared card-group view; delete the old one. |
| Frequently Used empty for fresh vaults (no useCount yet) | Low×Low | Section hidden when no item has `useCount > 0` — graceful. |

## Security Considerations
- Cards show title + subtitle (username/URL) only — never secrets (`VaultItem.subtitle` excludes
  passwords; verified `VaultItem.swift:56-60`). Archived/trashed already excluded via `items`.

## Next Steps
Phase 5 makes the section set data-driven (Customize Home). Phase 7 adds pin/archive context actions
that affect which items show in Pinned/Frequently-Used.
