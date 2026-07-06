# P0-S4 — Unfiled semantics

Context: [p0-plan.md](p0-plan.md) · audit §A ("item optional-single-folder / Unfiled") · depends on S2

## Overview
- Priority: P2 · Status: pending · Depends on: S2
- Confirm and make coherent the behavior when an item has no Space (`folderId == nil` = "Unfiled") across the new persistence (S0), primary resolver (S1), and scoped search (S2). Mostly a **verification + small guard** phase, not new machinery (YAGNI).

## Key insights
- Unfiled already exists and is first-class in the sidebar: `ItemsScreen.swift:89-95` renders an "Unfiled" row (`VaultRoute.folder(nil)`) with `unfiledCount`.
- `scoped(nil)` returns **all** items today (`VaultRepository+Folders.swift:168-171`) — nil means "all folders" in the Home-filter context, NOT "only Unfiled". This ambiguity is the thing to keep coherent: on Home, `nil` = All Spaces; the Unfiled *list* is a separate route filtering `folderId == nil`.
- Deleting a folder reassigns members to Unfiled (`VaultRepository+Folders.swift:81-84`) — re-seals each item (bumps updatedAt). Correct already.
- Under S2 `.thisSpace(id)`, Unfiled items (nil folderId) are correctly excluded (no id match). Under `.allSpaces` they're included. There is **no** "search only Unfiled" scope in P0 (not requested → YAGNI).

## Requirements
- Functional: no code path treats `folderId == nil` as a crash/empty edge; Unfiled items are reachable via All Spaces search and the Unfiled route; scoped search never accidentally drops or duplicates them.
- Persistence (S0): selecting the Unfiled *route* is navigation, not a Home filter value — S0 persists only folder ids / All-Spaces sentinel, so Unfiled navigation is not persisted as a "Space". Confirm no attempt to persist `nil`-as-Unfiled ambiguously.

## Architecture
No new types. Verification matrix + at most a defensive guard in `search(_:scope:)` so `.thisSpace(id)` with an id that no longer exists returns empty (not all items) rather than falling through to a nil-scope global.

Decision table (document in code comment on `search(_:scope:)`):
| Surface | folderId == nil item | Behavior |
|---------|----------------------|----------|
| Home `.allSpaces` (nil filter) | shown | included (existing) |
| Home `.thisSpace(id)` | hidden | excluded (existing) |
| Unfiled route | shown | `items(inFolder: nil)` (`:112-114`) |
| Search `.allSpaces` | matched | included |
| Search `.thisSpace(id)` | not matched | excluded (correct) |
| Search `.sharedWithMe` (S5) | n/a | shares have no folderId; separate set |

## Related code files
- Modify: `Vaultify/Data/Repositories/VaultRepository+Folders.swift` — defensive: in `search(_:scope:)` `.thisSpace(id)`, filter strictly by `folderId == id` (already the plan in S2); add a doc comment capturing the table. No signature change.
- Verify (read-only): `ItemsScreen.swift:89-95`, `VaultRepository+Folders.swift:110-114,168-171,81-84`.

## Implementation steps
1. Confirm S2's `.thisSpace(id)` uses `folderId == id` (strict), so a stale/nonexistent id yields empty — never the global set.
2. Add the decision-table doc comment to `search(_:scope:)`.
3. Manually verify the matrix above on device/sim (Unfiled item appears in All-Spaces search, hidden in This-Space, listed in Unfiled route).
4. Add a unit test: item with `folderId == nil` → excluded from `.thisSpace`, included in `.allSpaces`.

## Todo
- [ ] Strict `folderId == id` in `.thisSpace`
- [ ] Decision-table doc comment
- [ ] Unit test for Unfiled inclusion/exclusion
- [ ] Manual matrix verification

## Success criteria
- Unfiled item never disappears from the app: reachable via Unfiled route + All-Spaces search.
- No scope combination returns the wrong set for nil-folderId items (matrix passes).

## Risk assessment
| Risk | L×I | Mitigation |
|------|-----|-----------|
| `.thisSpace(staleId)` falls through to global | Low×Med | Strict equality filter; unit test. |
| User confusion: Unfiled not a "Space" for persistence | Low×Low | S0 persists only real folder ids + All-Spaces; Unfiled stays a route. |

## Security
None — no secret handling; verification-only over decrypted items.

## Next steps
Coherent with S5 (Shared-with-Me, which likewise has no folderId but is a distinct projection set).
