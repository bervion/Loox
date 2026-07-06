---
name: vaultify-persona-space-partition-plan
description: Persona↔Space hard partition plan — Folder.personaId becomes the partition key; active persona filters whole app; fail-closed INV-R03
metadata:
  type: project
---

Plan: `plans/260706-1238-persona-spaces-relay-proposal-v3/partition-plan.md` + 4 phase files. Branch `feat/persona-space-partition`.

Upgrades persona from "lens" to real partition: each Space (`Folder.personaId`, sealed in FolderSecret, was always nil) belongs to exactly ONE persona. Active persona filters Home/Items/Search.

**Why:** answers "which vault/space belongs to which persona" with a hard binding. Extends [[vaultify-persona-relay-proposal-v3]] P1/P2. Partition filter is UNIVERSAL (all personas); isolationPolicy only gates escape hatches (All Spaces/Shared/search-widen).

**How to apply (fail-closed defaults taken):**
- Backfill nil folders → default persona on reload (in-place patch, mirror `mergeDuplicateSeedFolders`).
- Unfiled items (folderId nil) → default persona only.
- item→persona = folder.personaId; nil→default. Upgraded resolver `personaID(forItem:)` (was primarySpaceID heuristic at `+PersonaContext.swift`).
- Filters defined ONCE at repo: `spaces(for:)`/`items(for:)`, persona-scope shared `scoped()`/`search()`.
- AutoFill stays cross-persona by host — do NOT partition `CredentialIdentityService.refresh`.
- Persona delete → reassign owned Spaces+items to default (don't destroy data).

**Top risk (verified real):** P1 `addPersona` set `primarySpaceID = folders.first` → non-default persona points at default-owned folder → strictAnonymous `defaultSearchScope` would search INTO default's Space (INV-R03 leak). Phase 01 F2 reconcile clears stale pointers. Phase 03 fixes create path (starter Space per persona).

Phase order: 01 model/backfill/filters (foundation) → 02 UI → 03 create paths → 04 delete reassign. 03+04 both edit `+PersonaManagement.swift` (sequential).
