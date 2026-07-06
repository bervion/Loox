# P0-S5 — Shared-with-Me pseudo-space scope compatibility

Context: [p0-plan.md](p0-plan.md) · D6 · audit §A ("Shared with Me render như pseudo-space") · depends on S2

## Overview
- Priority: P2 · Status: pending · Depends on: S2
- "Shared with Me" is a **projection over accepted shares** (`ItemsScreen.swift:96-105`, `env.sharedItems.items`), NOT a `FolderRecord` — it has no `folderId`, is never synced/backed-up, read-only. Ensure the scope chip + scoped search treat it as a first-class selectable scope without breaking. No new persistence for it.

## Key insights
- Shared items already join search today via a separate union in the view (`SearchScreen.swift:38-41`), matching item text only (they have no Space name). S2 moved that union under `scope == .sharedWithMe`; S5 finalizes the chip + gating.
- Shared-with-Me visibility gate already exists: `ItemsScreen.swift:98` → `env.settings.approvalModeEnabled || !env.sharedItems.items.isEmpty`. Reuse verbatim for the chip.
- Shared items are not persisted as a selected Space (S0 stores folder ids / All-Spaces only). Selecting the `.sharedWithMe` scope is an ephemeral search-session choice, not a Home filter. Do NOT add it to S0 persistence (YAGNI + it isn't a Space).
- No `folderId` → `.thisSpace`/`.allSpaces` repo search must never accidentally include shares; only `.sharedWithMe` does.

## Requirements
- Functional: chip offers "Shared with Me" only when the gate is satisfied; selecting it searches **only** `env.sharedItems.items` (all-tokens over `item.searchText`); other scopes exclude shares.
- Non-functional: read-only projection; nothing synced; no secret leaves owner boundary (shares are already read-only projections).

## Architecture
`SpaceScope.sharedWithMe` (added in S2). Repo `search(_:scope:)` returns `[]` for `.sharedWithMe` (repo owns only vault items); the **view** supplies shared results for that scope:
```swift
// SearchScreen results (finalized):
switch scope {
case .sharedWithMe: return sharedMatches(query)      // env.sharedItems only
case .thisSpace, .allSpaces: return repository.search(query, scope: scope)  // no shares
}
```
Data flow: shares projection (`env.sharedItems.items`) → token filter → results, only under `.sharedWithMe`. Chip gated by the approval/shares condition.

## Related code files
- Modify: `Vaultify/Features/Search/SpaceScope.swift` — (case already added in S2; confirm `.sharedWithMe` present)
- Modify: `Vaultify/Features/Search/SearchScreen.swift` — finalize per-scope result switch; chip gating (reuse `ItemsScreen.swift:98` condition); localize label
- Verify (read-only): `ItemsScreen.swift:96-105`, `env.sharedItems` source

## Implementation steps
1. Ensure `SpaceScope.sharedWithMe` exists (from S2).
2. In `SearchResultsList`, replace the unconditional shared union with a per-scope switch: `.sharedWithMe` → shared-only matches; `.thisSpace`/`.allSpaces` → repo results with no shares.
3. Chip: show "Shared with Me" option only when `env.settings.approvalModeEnabled || !env.sharedItems.items.isEmpty`.
4. Empty-in-`.sharedWithMe` uses the same escape-hatch pattern (offer All Spaces if `allSpacesSearchAllowed`).
5. Localize the chip label EN+VI (reuse existing "Shared with Me" catalog string if present — grep first to avoid a dupe key).
6. `make check`; test: a shared item matches only under `.sharedWithMe`, never under `.thisSpace`/`.allSpaces`.

## Todo
- [ ] `.sharedWithMe` case confirmed
- [ ] Per-scope result switch (shares only in `.sharedWithMe`)
- [ ] Chip gating reuses approval/shares condition
- [ ] Reuse/verify "Shared with Me" localized string (EN+VI)
- [ ] Compile + test isolation of shares

## Success criteria
- Shared item appears in search **only** when scope = Shared with Me.
- Chip hidden when no shares and approval mode off.
- No shared item leaks into This Space / All Spaces results.

## Risk assessment
| Risk | L×I | Mitigation |
|------|-----|-----------|
| Shares leak into vault scopes | Med×Med | Repo `search(_:scope:)` never returns shares; view supplies them only for `.sharedWithMe`. |
| Duplicate localization key for "Shared with Me" | Low×Low | Grep catalog before adding; reuse existing key. |
| Treating shares as a persistable Space | Low×Med | Explicitly excluded from S0; scope is ephemeral. |

## Security
Shared projections are read-only, never synced/backed-up, and stay within the recipient's session. Search over them adds no new exposure. They must never be mixed into `.allSpaces` results in a way that implies they are owned vault items.

## Next steps
P5 (Shared Space Persona Representation) builds real space-membership; P0 only ensures the pseudo-space is a coherent search scope today.
