# Phase 02 — UI filtering: Home / Items / Search

**Context:** `partition-plan.md` · Phase 01 (filters live in repo).
**Priority:** P2 · **Status:** pending · **Deps:** Phase 01.

## Overview
Reflect the repo-level partition in the three browse surfaces: the Space pickers list only the
active persona's Spaces, Unfiled shows only under the default persona, Shared-with-Me shows
regardless but suppressed under strictAnonymous. Item pools are already persona-scoped by Phase 01
(F5), so most changes are picker/visibility, not filtering logic.

## Key insights (verified)
- **Home** `HomeScreen.swift`: `selectedFolderId` (:20); item sections call `allItems/favorites/totpItems(folder:)` (:33-49) — already persona-scoped after Phase 01. `autoSelectSingleSpace` (:66) checks `env.repository.folders.count == 1`; `applyRememberedSpace` (:94) validates saved id against `env.repository.folders`. Both must use `activePersonaSpaces`. `.onChange(of: activePersona?.id)` already re-drives filter (:138).
- **Items** `ItemsScreen.swift`: `ForEach(env.repository.folders)` (:83) → active-persona spaces; `unfiledCount > 0` (:89) already 0 for non-default after Phase 01 (no extra guard needed but verify); `Shared with Me` row (:99).
- **Search** `SearchScreen.swift`: `currentSpaceId` validated against `env.repository.folders` (:46); `availableScopes` (:57) already honors `allSpacesSearchAllowed`/`showsSharedScope`; `folderName` (:169). Point folder lookups at `activePersonaSpaces`.

## Requirements
- **F1 Home picker:** Space filter lists `activePersonaSpaces` only. `autoSelectSingleSpace`/`applyRememberedSpace` count/validate against `activePersonaSpaces` (a remembered Space not owned by the active persona → "All Spaces", not empty).
- **F2 Items list:** Spaces section = `activePersonaSpaces`. Unfiled row gated by `unfiledCount` (already default-only). Shared-with-Me row unchanged (cross-persona) but hidden under strictAnonymous via existing `showsSharedScope`.
- **F3 Search:** `currentSpaceId` + `folderName` resolve over `activePersonaSpaces`. Scope chips already gated. Empty-state widen already respects `allSpacesSearchAllowed`.
- **F4 Localization:** no new strings expected; if an "empty persona" state is added, add EN+VI to `Localizable.xcstrings`.

## Architecture / data flow
```
active persona switch → HomeScreen .onChange(activePersona.id) → applyRememberedSpace
  → selectedFolderId validated vs activePersonaSpaces → sections read activePersonaItems (Phase 01)
Items/Search pickers → activePersonaSpaces (owned only) ; Shared-with-Me → cross-persona, strictAnon-suppressed
```
"All Spaces" now means "all of THIS persona's Spaces" (decision 6).

## Related code files
- **Modify:** `Vaultify/Features/Home/HomeScreen.swift` (`autoSelectSingleSpace`, `applyRememberedSpace`, Space-picker source, `.onChange(of: folders.count)` → persona spaces count).
- **Modify:** `Vaultify/Features/Items/ItemsScreen.swift` (Spaces `ForEach` source).
- **Modify:** `Vaultify/Features/Search/SearchScreen.swift` (`currentSpaceId`, `folderName` sources).
- No new files; no `tuist generate` needed.

## Implementation steps
1. Add `activePersonaSpaces` reads (Phase 01) in place of `env.repository.folders` in the three screens' Space listings/validations.
2. Home: swap `folders.count`→`activePersonaSpaces.count` in `autoSelectSingleSpace` + `.onChange`; validate remembered id against `activePersonaSpaces`.
3. Items: `ForEach(env.repository.activePersonaSpaces)`. Confirm Unfiled/Shared rows behave (Unfiled auto-0 for non-default; Shared unchanged).
4. Search: `currentSpaceId` + `folderName` over `activePersonaSpaces`.
5. `make check`; manual QA on sim (switch persona → Home/Items/Search all refilter; light+dark, Reduce Motion).

## Todo
- [ ] Home picker + auto/remember over persona spaces
- [ ] Items Spaces list over persona spaces
- [ ] Search space lookups over persona spaces
- [ ] `make check` + manual persona-switch QA

## Success criteria
- Switching active persona A→B live-refilters Home feed, Items Spaces list, and Search scope to B's Spaces+items (no restart).
- A strictAnonymous persona with no owned Space shows empty Home/Items and no All-Spaces/Shared chips.
- Unfiled row appears only when the default persona is active.
- A remembered Space owned by another persona resolves to "All Spaces" (never an empty/leaking filter).
- Existing Home/Items/Search behavior unchanged when only the default persona exists.

## Risk assessment
- **Stale remembered Space leak (M×H):** validate against `activePersonaSpaces` (owned) — a foreign id falls back to All Spaces (of the current persona), never cross-persona. Add manual check.
- **Empty-persona confusion (L×L):** acceptable; create-path (Phase 03) seeds a starter Space for new personas so this is rare.

## Security
- All item pools sourced from Phase 01 fail-closed filters; UI cannot widen past the active persona. Shared-with-Me remains read-only + strictAnonymous-suppressed.

## Next steps
Independent of Phase 03/04. Ship after Phase 01 merges.
