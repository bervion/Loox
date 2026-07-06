# Phase 03 — Create paths: Space / item / persona

**Context:** `partition-plan.md` · Phase 01 (resolver + filters).
**Priority:** P2 · **Status:** pending · **Deps:** Phase 01. Sequential with Phase 04 (shared file).

## Overview
Make new data land in the right persona. A Space created while persona X is active is owned by X;
a new item inherits its Space's persona automatically (derivation — no code change); creating a
persona seeds a starter Space it owns (fixes the P1 `folders.first` leak that Phase 01 reconciles).

## Key insights (verified)
- `addFolder(name:icon:color:)` — `VaultRepository+Folders.swift:53` — builds `Folder(...)` with no `personaId` (defaults nil). Must stamp active persona.
- `addPersona(displayName:kind:isolationPolicy:)` — `VaultRepository+PersonaManagement.swift:26` — sets `primarySpaceID: folders.first?.id` (:31). **This is the leak**: the new persona points at the default's folder. Replace with a freshly created owned Space.
- Item create (`add`, `VaultRepository.swift:268`) needs NO change — persona is derived from `folderId`'s Space; Unfiled → default (Phase 01 F3). New items default into `primarySpaceId` (`+Folders.swift:49` = `activePersona?.primarySpaceID`), which after this phase is an owned Space.
- `assignSpace(_:toPersona:)` (`+Personas.swift:92`) already exists as the re-seal writer if a caller needs to re-own a Space.

## Requirements
- **F1 New Space owned by active persona:** `addFolder` sets `personaId = activePersona?.id` on the built `Folder` before sealing.
- **F2 Persona starter Space:** `addPersona` creates an owned Space first (`addFolder`-style, `personaId = new persona id`), sets the persona's `primarySpaceID` to it. No more `folders.first`. Order: build persona id → seal starter folder with that id → seal persona with `primarySpaceID`.
- **F3 New item:** no change; derivation + `primarySpaceId` default cover it. Add a test to lock the behavior.

## Architecture / data flow
```
addFolder(active=X)      → Folder(personaId: X) sealed → owned by X
addPersona(name,kind)    → new id N → addFolder(owned by N) → primarySpaceID = starterId
add(item, folder=F)      → persona = folder(F).personaId (Phase 01 resolver)
add(item, folder=nil)    → default persona (Unfiled)
```

## Related code files
- **Modify:** `Vaultify/Data/Repositories/VaultRepository+Folders.swift` (`addFolder` stamps `personaId`).
- **Modify:** `Vaultify/Data/Repositories/VaultRepository+PersonaManagement.swift` (`addPersona` seeds starter Space, sets `primarySpaceID`).
- **Also:** the `addPersona` overload in `VaultRepository+Personas.swift:60` delegates to the `+PersonaManagement` one — verify no second `folders.first` path.
- **Modify:** `VaultifyTests/PersonaPartitionTests.swift` (create-path cases).

## Implementation steps
1. `addFolder`: pass `personaId: activePersona?.id` into the `Folder(...)` initializer (sealed via existing `sealFolder`).
2. `addPersona`: allocate persona id, call `addFolder(...)` (now stamps that persona once active? no — persona not active yet) → instead build the starter `Folder(personaId: newPersonaID)` directly and insert its record, then set `primarySpaceID = starter.id`. Keep it one method, <200 LOC.
3. Remove `primarySpaceID: folders.first?.id` (:31) leak.
4. `make check`; add tests; full suite.

## Todo
- [ ] `addFolder` stamps active persona
- [ ] `addPersona` seeds owned starter Space, sets `primarySpaceID`
- [ ] Remove `folders.first` leak
- [ ] Tests + `make check` green

## Success criteria (concrete INV-R03 assertions)
- `testNewSpaceOwnedByActivePersona`: `setActivePersona(X)` → `addFolder(...)` → the folder's `personaId == X`; visible in `spaces(for: X)`, absent from `spaces(for: default)`.
- `testNewPersonaGetsOwnedStarterSpace`: `addPersona(...)` → returned persona has non-nil `primarySpaceID`; that folder's `personaId == new id`; `spaces(for: newPersona).count == 1`; default persona's spaces unchanged.
- `testNewItemInheritsSpacePersona`: `setActivePersona(X)` (owns starter S) → `add(login)` → `personaID(forItem: created) == X`.
- `testNewItemUnfiledResolvesDefault`: item with `folderId == nil` → resolver returns default id; not visible under a non-default persona.
- No persona ever shares another persona's Space (grep-proof: no `folders.first` in create paths).

## Risk assessment
- **Starter-Space proliferation (L×L):** one Space per persona is intended; acceptable.
- **`addPersona` ordering (M×M):** starter folder must be sealed/inserted before persona seals `primarySpaceID`; cover with the starter-space test. `reload()` at the tail rebuilds caches.
- **Sync:** starter folder + persona both re-seal with fresh `updatedAt` → LWW-safe.

## Security
- Ownership stamped at creation; no cross-persona pointer possible. Starter Space name localized EN+VI if a literal is introduced (reuse existing "My Vault"/"Personal" strings — no new secret).

## Next steps
Sequential with Phase 04 (both edit `+PersonaManagement.swift`). Land 03 then 04.
