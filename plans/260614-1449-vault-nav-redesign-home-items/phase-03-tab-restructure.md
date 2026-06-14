# Phase 03 — Tab Restructure (Home / Items / Watchtower / Search)

## Context Links
- Tab shell: `Vaultify/Features/Main/MainTabView.swift` (4 tabs today)
- Current Vault tab: `Vaultify/Features/Vault/VaultListScreen.swift` (NavigationStack + searchable)
- Icons: `Vaultify/DesignSystem/PolarisIcon.swift` (post Phase 1)
- Watchtower (unchanged content): `Vaultify/Features/Watchtower/WatchtowerScreen.swift`

## Overview
- **Priority:** P1
- **Status:** pending
- **Depends:** Phase 1 (tab icons `ic_plan`/`_filled`).
- Rewrite `MainTabView` to 4 tabs: **Home** (tag 0), **Items** (tag 1), **Watchtower** (tag 2),
  **Search** (tag 3, rightmost). Settings and Generator leave the tab bar. This phase wires the shell
  and a thin Search tab; Home/Items screen bodies land in Phases 4 & 6 (use placeholders first to stay
  compilable, then fill in — or sequence so 4 & 6 land their screens before flipping the tab).

## Key Insights
- Today's `MainTabView` uses `Label(_, image:)` with `Icons.*` and a `selection`-driven filled/outline
  swap (e.g. `selection == 0 ? Icons.homeFill : Icons.home`) — reuse that exact pattern for all 4 tabs.
- iOS-18 `Tab(role: .search)` is NOT available at the 17.6 target → Search is a normal tab: a screen
  with `.searchable` reusing the existing smart-search logic from `VaultListScreen.swift:23-32`.
- `VaultListScreen` currently owns BOTH the Home dashboard AND the per-tab NavigationStack +
  destinations (`ItemDetailScreen`, `FolderItemsScreen`, `TagItemsScreen`, `ManageFoldersScreen`,
  `TrashScreen`). When splitting Home/Items/Search, **each new tab needs its own NavigationStack** with
  the destinations it actually pushes (Home → detail/folder/tag/manageFolders/trash via Utilities/links;
  Items → folder/category/tag/archive/trash; Search → detail). Keep a shared `navigationDestination`
  modifier helper to avoid duplicating the switch (DRY).
- `MainTabView` overlay copy-toast + inactivity timer (`MainTabView.swift:10,27-30`) are tab-agnostic —
  keep as-is.

## Requirements
**Functional:**
- 4 tabs in order Home, Items, Watchtower, Search with correct Polaris icons + filled-on-select.
- Watchtower content unchanged (`WatchtowerScreen()` dropped in as tag 2).
- Search tab: `.searchable` field, smart-search results (token-AND over title/fields/tags + space name),
  taps push `ItemDetailScreen`. Empty query → empty-state (see Open Q in phase-09).
- Settings reachable from Home header gear (Phase 4); Generator from Home Utilities (Phase 4).

**Non-functional:** localized tab labels (EN+VI); no SF Symbols; copy-toast + auto-lock preserved.

## Architecture
- `MainTabView` → `TabView(selection:)` with 4 `.tabItem` tabs. Tags 0–3.
- New `SearchScreen` (`Vaultify/Features/Search/SearchScreen.swift`): own `NavigationStack`,
  `@State search`, computes `searchResults` (lift the logic out of `VaultListScreen` into a reusable
  spot — see Architecture note below), `List(searchResults){ VaultItemRowLink(item:) }`,
  `.navigationDestination(for: String.self){ ItemDetailScreen(itemID:$0) }`.
- **Reuse smart-search (DRY):** extract the token-AND filter into a small helper so Search tab and any
  residual search share it. Options: (a) a `VaultRepository.search(_:)` method (cleanest — repo owns
  folders + items), or (b) a free function in a `VaultSearch.swift`. **Recommend (a)**:
  `func search(_ query: String) -> [VaultItem]` on the repo, moving logic from `VaultListScreen:23-32`.
  Then Search tab calls `env.repository.search(query)`.

## Related Code Files
**Create:**
- `Vaultify/Features/Search/SearchScreen.swift` (≤120 LOC) — searchable tab.

**Modify:**
- `Vaultify/Features/Main/MainTabView.swift` — 4 new tabs (Home tag0, Items tag1, Watchtower tag2,
  Search tag3); swap labels/icons; update the doc-comment (currently says "Search is the native
  `.searchable` bar on the Vault tab" — now a tab).
- `Vaultify/Data/Repositories/VaultRepository.swift` (or `+Folders`) — add `search(_:)` helper (lifts
  `VaultListScreen` logic; uses `items` (archived-excluded) + `folders`).
- `Vaultify/Features/Vault/VaultListScreen.swift` — will be superseded by `HomeScreen` (Phase 4); in
  this phase, either keep it temporarily wired to Home tag 0 (placeholder) OR coordinate so Phase 4
  lands `HomeScreen` first. **Recommended sequence: do Phase 4 + 6 screen bodies, THEN flip MainTabView
  here** — but since this phase is "tab restructure", land MainTabView pointing at `HomeScreen`/
  `ItemsScreen`/`SearchScreen` and ensure those exist (stub acceptable to keep `make check` green).

## Implementation Steps
1. Add `VaultRepository.search(_:)` (move smart-search logic; keep `VaultListScreen` compiling by
   calling the new method or leaving its inline copy until Phase 4 removes the screen).
2. Create `SearchScreen` (NavigationStack + searchable + `repository.search` + detail destination).
3. Rewrite `MainTabView` tabs → Home/Items/Watchtower/Search with icons:
   - Home: `selection==0 ? Icons.homeFill : Icons.home`
   - Items: `selection==1 ? Icons.organizationFill : Icons.organization` (add `organization(Fill)`
     constants in Phase 1 if not already — icons exist in catalog)
   - Watchtower: `selection==2 ? Icons.planFill : Icons.plan`
   - Search: `Icons.search` (rightmost, no fill variant needed)
4. Point Home tab → `HomeScreen()` (Phase 4), Items tab → `ItemsScreen()` (Phase 6). If those screens
   aren't landed yet, add minimal stubs so this compiles; Phases 4/6 fill them.
5. Remove Generator + Settings tabs from `MainTabView`.
6. Add `Icons.organization = "ic_organization"`, `organizationFill = "ic_organization_filled"` constants.
7. `tuist generate` + `make check` green.

## Todo List
- [ ] `VaultRepository.search(_:)` helper (DRY smart-search)
- [ ] `SearchScreen` (searchable tab + detail nav)
- [ ] MainTabView → 4 tabs, correct icons + filled-on-select
- [ ] Remove Generator + Settings tabs
- [ ] Icons.organization(_Fill) constants
- [ ] Home/Items tabs point at HomeScreen/ItemsScreen (stub if needed)
- [ ] `make check` green

## Success Criteria
- App launches to a 4-tab bar in the locked order; each tab opens its screen.
- Search tab returns smart-search results and pushes detail.
- Watchtower unchanged. No Generator/Settings tab. Copy-toast + auto-lock still work.
- `make check` green.

## Risk Assessment
| Risk | L×I | Mitigation |
|---|---|---|
| Per-tab NavigationStack duplication of destinations | Med×Low | Shared `navigationDestination` view-modifier helper; each tab declares only what it pushes. |
| Splitting VaultListScreen mid-phase breaks build | Med×Med | Land Phase 4/6 screens (or stubs) before flipping MainTabView; keep `make check` green at each commit. |
| Search empty-state UX undecided | Low×Low | Ship a neutral ContentUnavailableView; flag exact copy as Open Q (phase-09). |
| Losing search-matches-space-name behavior in the move | Low×Med | `search(_:)` must keep the folder-name join (`VaultListScreen:25-31`); covered by a Phase 9 test. |

## Security Considerations
- Search reads decrypted in-memory `items` only (archived/trashed already excluded) — no secret fields
  in `searchText` (verified: `VaultItem.searchText` skips protected fields). No new exposure.

## Next Steps
Home tab body → Phase 4; Items tab body → Phase 6. Generator/Settings re-homing → Phase 4.
