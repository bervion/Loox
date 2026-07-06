# P0-S2 — Scoped search + scope chip

Context: [p0-plan.md](p0-plan.md) · D6 · INV-R03 · audit §A gap 2 · execution note 2

## Overview
- Priority: P1 · Status: pending · Depends on: S0, S1
- Today search is **global** (`VaultRepository+Folders.swift:232-241`, `SearchScreen.swift:34`). Per D6: default search to the **current Space**; add a scope chip (This Space / All Spaces / Shared with Me); searching all Spaces must be an **explicit** user action. Empty-state escape hatch ("No results in <Space>. Search all Spaces?") in 1 tap. Leave a clean **INV-R03 gate seam** (all-Spaces search gated when a future strictAnonymous persona is active) — do NOT implement persona logic.

## Key insights
- `search(_:)` currently matches item text **OR the item's Space name** (`:236-238`). Under scoped search, matching by *another* Space's name is contradictory; scope filters by `folderId` first, then token-matches.
- `SearchResultsList.results` (`SearchScreen.swift:33-42`) already unions repo results + `env.sharedItems.items` (shared projections). Scoping must gate that union (shared items belong only to the Shared-with-Me scope) — this is where S5 plugs in.
- Default scope derives from Home's current selection: a specific folder → `.thisSpace(id)`; `nil` (All Spaces) → `.allSpaces`. Uses S0 persistence + S1 resolver.

## Requirements
- Functional: results limited to the active scope; chip switches scope live; empty-in-scope shows a 1-tap "Search all Spaces" action that flips scope to `.allSpaces`.
- INV-R03: expose a single boolean seam `allSpacesSearchAllowed` (returns `true` in P0) that P1/P2 will drive from persona isolation; when `false`, the chip's All-Spaces option + escape hatch are hidden/disabled. No persona code now.
- Localization: chip labels + empty-state copy EN+VI in `Localizable.xcstrings`.
- Non-functional: pure client-side; no new persisted state (scope is ephemeral `@State`, seeded from current Space each search session).

## Architecture
New scope type (owned here; S4/S5 extend):
```swift
// SpaceScope.swift
enum SpaceScope: Equatable {
    case thisSpace(id: String)   // a specific folder
    case allSpaces               // gated by INV-R03 seam
    case sharedWithMe            // S5 — pseudo-space projection
}
```
New scoped search entry on `VaultRepository`:
```swift
/// Scope-aware search. `.thisSpace` filters folderId==id BEFORE token match
/// and does NOT match on other Spaces' names. `.allSpaces` == legacy behavior.
func search(_ query: String, scope: SpaceScope) -> [VaultItem]
```
Data flow:
`SearchScreen` seeds `scope` from `env.repository.primarySpaceId`/current selection → user query → `repository.search(query, scope:)` (+ shared union only when `scope == .sharedWithMe`, S5) → results. Chip mutates `scope`. Empty-in-scope → button sets `scope = .allSpaces` (only if `allSpacesSearchAllowed`).

## Related code files
- Create: `Vaultify/Features/Search/SpaceScope.swift`
- Modify: `Vaultify/Data/Repositories/VaultRepository+Folders.swift` — add `search(_:scope:)`; keep `search(_:)` as `search(_, scope: .allSpaces)` shim (used by `MacHeaderBar.swift:86`) OR migrate the Mac caller. Add `var allSpacesSearchAllowed: Bool { true }` seam.
- Modify: `Vaultify/Features/Search/SearchScreen.swift` — scope `@State`, chip UI, seed default, gate shared union, empty-state escape hatch
- Localize: `Vaultify/Resources/Localizable.xcstrings` (or project catalog) — chip + empty-state strings EN+VI

## Implementation steps
1. Create `SpaceScope.swift` (3 cases).
2. `VaultRepository+Folders.swift`: implement `search(_:scope:)`:
   - `.allSpaces` → existing logic (token match over item text + own Space name).
   - `.thisSpace(id)` → `items.filter { $0.folderId == id }` then all-tokens over `item.searchText` (drop cross-Space name matching).
   - `.sharedWithMe` → return `[]` here; the shared union lives in the view (S5).
   - Keep `search(_:)` delegating to `.allSpaces` so `MacHeaderBar.swift:86` compiles unchanged.
   - Add `allSpacesSearchAllowed` seam (returns true; doc-comment the P1 persona intent).
3. `SearchScreen`: add `@State private var scope: SpaceScope`; seed on `.onAppear` from current Home selection (pass selected folder id in, or read `primarySpaceId`); render a chip row (`This Space` / `All Spaces` / `Shared with Me`) using DS tokens (`Space.*`, `.vaultType`, `.themedForeground`, Polaris icon). Hide `All Spaces` + `Shared with Me` per gates (`allSpacesSearchAllowed`; shared shown only when `approvalModeEnabled || !sharedItems.isEmpty`, mirroring `ItemsScreen.swift:98`).
4. Route results through `repository.search(query, scope:)`; move the shared-items union under `scope == .sharedWithMe` (S5 finalizes).
5. Empty-in-scope state: when `scope != .allSpaces` and results empty and `allSpacesSearchAllowed`, show `ContentUnavailableView` with a button "Search all Spaces" → `scope = .allSpaces`. Include the Space name in the message.
6. Add EN+VI strings; titles via `.inAppLocalized`, runtime via `appString()`.
7. `make check`; UI + repo unit tests (scope filters correctly; escape hatch flips scope).

## Todo
- [ ] `SpaceScope` enum
- [ ] `search(_:scope:)` + `.allSpaces` shim + `allSpacesSearchAllowed` seam
- [ ] Scope chip UI (DS tokens, Polaris icons)
- [ ] Default scope seeded from current Space
- [ ] Empty-state 1-tap "Search all Spaces"
- [ ] EN+VI strings
- [ ] Compile + tests

## Success criteria
- Default search only returns items in the current Space; switching chip to All Spaces returns the legacy global set.
- Empty-in-scope shows the named escape hatch; one tap widens to All Spaces.
- Toggling `allSpacesSearchAllowed` to `false` (temporary test) hides All-Spaces option + hatch — proves the INV-R03 seam without persona code.
- `MacHeaderBar` search still compiles/works (shim).

## Risk assessment
| Risk | L×I | Mitigation |
|------|-----|-----------|
| Behavior change surprises internal users | High×Med | Default derives from visible current Space; 1-tap escape hatch; localized copy. |
| Shared-items union leaks into scoped results | Med×Med | Gate union to `.sharedWithMe` (S5); repo `.thisSpace` never includes shares. |
| INV-R03 seam forgotten → P1 rework | Med×High | Ship `allSpacesSearchAllowed` gate now on chip + hatch even though always-true. |
| Scoped search hides Unfiled items | Med×Med | S4 defines Unfiled behavior explicitly. |

## Security
No secret exposure; search runs over already-decrypted in-memory items. INV-R03 seam is the forward-privacy contract — must exist even as a no-op so P1 cannot silently cross-surface personas.

## Open decision (confirm before coding)
- Show "Shared with Me" chip only when shares exist / approval mode on (recommended, mirrors `ItemsScreen.swift:98`) vs always show?

## Next steps
S4 (Unfiled) and S5 (Shared-with-Me) extend `SpaceScope` + the scoped search. P1 drives `allSpacesSearchAllowed` from persona isolation mode.
