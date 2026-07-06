# P0-S1 — Primary-Space resolver

Context: [p0-plan.md](p0-plan.md) · canonical [proposal-v3-locked-decisions.md](proposal-v3-locked-decisions.md) D12 · audit §A gap 3

## Overview
- Priority: P1 · Status: pending · Depends on: none (foundational)
- Replace the scattered `folders.first?.id` "primary Space" heuristic with **one** resolver so P1 can back it with `Persona.primarySpaceID` by editing a single function. **Do NOT** add `isPrimary` to `FolderRecord` (D12 avoids distributed-uniqueness under sync conflict).

## Key insights
- Only **2** call sites use `folders.first` as the *primary/default* heuristic (verified):
  - `ItemEditorScreen.swift:149` — new-item default: `preselectedFolderId ?? env.repository.folders.first?.id`
  - `HomeScreen.swift:68` — `autoSelectSingleSpace()` single-Space auto-filter
- All other `folders.first(where:{ $0.id == id })` hits are **lookup-by-id**, not the heuristic — leave untouched.
- `folders` is already sorted by `(sortIndex, createdAt)` (`VaultRepository+Folders.swift:34`), so `.first` = lowest sortIndex. Resolver preserves this exact behavior in V1.

## Requirements
- Functional: single source returns the primary Space id (or `nil` when no folders exist → Unfiled world). Behavior identical to today.
- Non-functional: pure, `nonisolated`-friendly read; no new stored state; zero behavior change (regression-safe refactor).

## Architecture
Add a computed accessor on `VaultRepository` (folders extension):
```swift
/// The Space new items default into when the caller gives no context.
/// V1 = lowest-sortIndex folder (`folders.first`). P1 swaps the body to
/// return the active persona's primarySpaceID; call sites never change.
var primarySpaceId: String? { folders.first?.id }
```
Data flow: `folders` (decrypted, sorted) → `primarySpaceId` → consumed by ItemEditor default + Home auto-select. No persistence, no sync.

## Related code files
- Modify: `VaultifyCore/... ` → actually `Vaultify/Data/Repositories/VaultRepository+Folders.swift` (add `primarySpaceId`)
- Modify: `Vaultify/Features/ItemEditor/ItemEditorScreen.swift:149` → `preselectedFolderId ?? env.repository.primarySpaceId`
- Modify: `Vaultify/Features/Home/HomeScreen.swift:68` → `selectedFolderId = env.repository.primarySpaceId`
- Create: none · Delete: none

## Implementation steps
1. Add `var primarySpaceId: String? { folders.first?.id }` to `VaultRepository+Folders.swift` with the doc comment above (explain the P1 seam without naming plan artifacts).
2. Replace `env.repository.folders.first?.id` at `ItemEditorScreen.swift:149` with `env.repository.primarySpaceId`.
3. Replace `env.repository.folders.first?.id` at `HomeScreen.swift:68` with `env.repository.primarySpaceId`.
4. Leave `HomeScreen.swift:66` count check and all `folders.first(where:)` lookups untouched.
5. `make check` compile.

## Todo
- [ ] Add `primarySpaceId` accessor
- [ ] Migrate ItemEditor default (line 149)
- [ ] Migrate Home auto-select (line 68)
- [ ] Compile clean (`make check`)

## Success criteria
- Grep for `folders.first?.id` returns **0** hits outside the resolver.
- New item with no context still lands in the lowest-sortIndex Space; single-Space vault still auto-filters. No functional diff.

## Risk assessment
| Risk | L×I | Mitigation |
|------|-----|-----------|
| Accidentally rewrite a lookup-by-id site | Low×Med | Only touch the 2 enumerated lines; leave `folders.first(where:)`. |
| Empty-vault (no folders) → nil default | Low×Low | Behavior already handles nil (item stays Unfiled). Unchanged. |

## Security
None new — no secret handling, read-only over already-decrypted folders.

## Next steps
Unblocks S0 (auto-select uses resolver) and S2 (search default derives from current/primary Space). P1 will replace the resolver body with persona-backed `primarySpaceID`.
