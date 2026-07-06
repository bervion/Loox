---
name: vaultify-p0-space-hardening-plan
description: P0 Space Hardening plan (S0-S5) location, key decisions, and the persona-ready seams for P1
metadata:
  type: project
---

P0 "Space Hardening" plan written at `plans/260706-1238-persona-spaces-relay-proposal-v3/p0-plan.md` + `p0-phase-S0..S5-*.md`. Part of Persona/Relay Proposal V3 (see [[vaultify-persona-relay-proposal-v3]]).

**Why:** harden already-shipped Folder-as-Space UX persona-ready so P1 (PersonaRecord) rebinds without migration. No rename (keep `FolderRecord`, D11), no backend.

**How to apply (P0 seams P1 will rebind):**
- S1: `VaultRepository.primarySpaceId` centralizes the `folders.first?.id` heuristic (only 2 real callers: ItemEditorScreen.swift:149, HomeScreen.swift:68). P1 swaps body to `Persona.primarySpaceID`. NO `isPrimary` column (D12).
- S0: `SettingsStore.lastSelectedSpaceByPersona: [String:String]` keyed by `PersonaID.placeholder="__default__"`; local-only, not synced (mirrors `selectedPaymentCardId` pattern SettingsStore.swift:73). P1 swaps the key.
- S2: `SpaceScope` enum {thisSpace/allSpaces/sharedWithMe} + `search(_:scope:)` + `allSpacesSearchAllowed` bool seam (true now; P1 drives from strictAnonymous per INV-R03).
- S3: add optional `personaId: String?` to `FolderSecret` (Folder.swift:40) — sealed, nullable, never written in P0. Old blobs decode nil (Swift Codable). LWW trap: any future write MUST go via updateFolder (bumps updatedAt).

**Open decisions flagged for user:** S0 map-vs-flat storage; S2 shared-chip visibility gate; S3 land-now vs defer-to-P1 (recommend land now, option b = FolderSecret-only, no Folder-model plumbing).

Order: S1→S0→S2→S4→S5; S3 parallel (only file: Folder.swift). Shared files HomeScreen.swift + VaultRepository+Folders.swift force the vault-item phases sequential.
