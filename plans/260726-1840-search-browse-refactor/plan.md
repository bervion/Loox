# Search & Browse Refactor (1Password-style split)

Status: implemented + verified on iPhone 11 sim (260726); unit tests 877/877, iOS + macOS slices compile
Owner ask: the Search filter bar feels meaningless and the "pop to Search with a filter" flow is jarring; want a pushable filtered-list screen (space / identity / keywords) other screens navigate to, and a simpler Search. Modeled on 1Password 8 (recon: workflow wf_0751d236-6a1).

## Design (decided)

Split search from browse, the 1P/Apple grammar:

- **Search tab = pure keyword.** No scope chip bar. Pool = active persona, fail-closed
  for strictAnonymous (`defaultSearchScope`). Operators + literal fallback stay.
  Empty state = "Recent" section (`recentlyUsed(limit:)`); results append a
  "Shared with Me" section when shared projections match (replaces the chip).
- **New `FilteredItemsScreen` + `ItemFilter` spec** (`spaceId`, `passkeysOnly`,
  seed `query`) — a pushed, titled item list with local `.searchable`, shared
  `VaultSort` menu + in-screen Space narrowing, `SpaceIdentityLine` header when
  space-scoped (identity context), folder-tinted. New `VaultRoute.filtered`.
- **Call-site migration** (kills all jarring jumps):
  - Home "See all" → dual-path push of `.filtered(spaceId:)` (was `.browse` + tab jump).
  - Hub category tiles → `NavigationLink` push of `VaultRoute.category` (was query + popToRoot + tab jump).
  - Hub Passkey tile → push `FilteredItemsScreen(passkeysOnly:)`.
  - iPad sidebar live `.query` entry stays (natural).
- Delete: `SearchEntry.browse`, `.vaultSwitchToSearch` notification, `SearchScopeBar`/trough, browse-mode sections.
- iPad sidebar profile stack gains `.vaultNavigationDestinations()` (hub pushes need row destinations).

## Acceptance
- No tab jump remains for filtered lists; back always returns to origin.
- Search: keyword-only, recents empty state, shared section, strictAnonymous isolation intact (INV-R03).
- EN+VI complete; make check + unit tests + macOS slice green; sim walkthrough (iPhone + iPad sidebar query).

Same branch also carries 4 detail-polish fixes (unlock button tint, unlocked-row background, native note selection, identity name on Home profile row).
