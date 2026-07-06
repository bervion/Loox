# Phase 04 — Persona-delete space+item reassign

**Context:** `partition-plan.md` · Phase 01 (resolver + filters).
**Priority:** P2 · **Status:** pending · **Deps:** Phase 01. Sequential after Phase 03 (shared file).

## Overview
Deleting a persona must not orphan or destroy its Spaces/items. Reassign every Space owned by the
deleted persona (and thereby its items, via derivation) to the default persona. Keep the existing
alias cascade. Fail-closed: after delete, no Space carries a dangling `personaId`.

## Key insights (verified)
- `deletePersona(_:)` — `VaultRepository+PersonaManagement.swift:63` — currently tombstones the persona + cascades aliases only (`deleteAliases(forPersona:)` :70). Comment at :61 explicitly says "Personas don't own items yet" — now they do (via Spaces). Update.
- Removal gate `personaRemovalGate` (:18) blocks deleting the last persona and the **default** persona → the reassign target (default) can never itself be the one deleted. Safe.
- Re-stamp writer exists: `assignSpace(_:toPersona:)` (`+Personas.swift:92`) re-seals folder via `updateFolder` (bump `updatedAt`, LWW-safe). Reuse it.
- Items follow their Space automatically (Phase 01 resolver) — no per-item write needed; reassigning the Space moves the items' persona.

## Requirements
- **F1 Reassign Spaces:** before tombstoning, for every folder with `personaId == persona.id`, `assignSpace(folder, toPersona: defaultPersona.id)`. Re-seals + bumps `updatedAt`.
- **F2 Items:** none — derived from the reassigned Spaces. (Unfiled items already resolve to default.)
- **F3 Keep alias cascade** (:70) unchanged.
- **F4 Order:** reassign (F1) → alias cascade → tombstone persona → single `save()` + `reload()`. Avoid intra-loop `reload()` churn (batch, mirror `deleteFolder`).

## Architecture / data flow
```
deletePersona(P): gate ok (P ≠ default, ≠ last)
  → for folder where personaId == P.id: assignSpace(folder, default.id)   // re-seal, updatedAt++
  → deleteAliases(forPersona: P.id)
  → tombstone PersonaRecord(P) (deletedAt, updatedAt++, dirty)
  → save + reload → default now owns P's former Spaces+items
```
Sync: each reassigned folder re-seals with fresh `updatedAt` → converges under whole-record LWW.

## Related code files
- **Modify:** `Vaultify/Data/Repositories/VaultRepository+PersonaManagement.swift` (`deletePersona` reassign loop; update the stale :61 comment).
- **Modify:** `VaultifyTests/PersonaPartitionTests.swift` (delete-reassign cases).
- No new files.

## Implementation steps
1. In `deletePersona`, after the gate, iterate `folders.filter { $0.personaId == persona.id }` and `assignSpace(_, toPersona: defaultPersona?.id)`.
2. Keep `deleteAliases`; tombstone; single `save()` + `reload()`.
3. Note `assignSpace` calls `updateFolder` which itself `save()`+`reload()`s per call — for KISS accept the extra reloads (delete is rare, folder count small), OR inline a batch re-seal like `deleteFolder`. Default: accept per-call reload (simpler); revisit only if a persona owns many Spaces.
4. Update the "don't own items yet" comment.
5. `make check` + tests + full suite.

## Todo
- [ ] Reassign owned Spaces → default in `deletePersona`
- [ ] Keep alias cascade; batch save/reload
- [ ] Update stale comment
- [ ] Tests + `make check` green

## Success criteria (concrete INV-R03 assertions)
- `testDeletePersonaReassignsSpacesToDefault`: persona X owns Space S with item I → `deletePersona(X)` → `folder(S).personaId == defaultPersona.id`; I preserved and visible in `items(for: default)`; X gone.
- `testDeletePersonaPreservesItemsNoDataLoss`: item count before == after (nothing trashed/deleted).
- `testDeleteDefaultBlocked` / `testDeleteLastBlocked`: gate still returns `.defaultPersona` / `.lastPersona` (reassign never runs).
- `testAfterDeleteNoDanglingPersonaId`: no folder references the deleted persona id.
- `testDeletePersonaStillCascadesAliases`: aliases of X tombstoned (existing behavior intact).

## Risk assessment
- **Per-call reload churn (L×L):** delete is rare; acceptable. Batch only if profiling shows cost.
- **Reassign misses a Space (L×H):** filter on `personaId == persona.id` before tombstone; `testAfterDeleteNoDanglingPersonaId` guards. `primarySpaceID` of X is irrelevant post-delete (persona gone).
- **Sync race (L×M):** reassigned folders + persona tombstone all bump `updatedAt`; converge under LWW.

## Security
- No data destroyed on persona delete (user-data preservation). Reassigned Spaces re-sealed under the Vault Key; default persona is a valid owner (never strictAnonymous by default). No plaintext exposure.

## Next steps
Final phase. After merge: update `docs/codebase-summary.md` persona/space section (Docs impact: minor).
