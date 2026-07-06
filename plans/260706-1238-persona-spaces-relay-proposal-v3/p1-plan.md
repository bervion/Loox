---
title: "P1 — Persona Core"
description: "First-class PersonaRecord (@Model + new CloudKit type), seed/migrate from default Identity, invariants, and rebind of P0 seams to the active persona — no backend, local-first."
status: done
priority: P1
effort: ~12h
branch: develop
tags: [persona, spaces, sync, migration, ios]
created: 2026-07-06
---

# P1 — Persona Core

Promote Persona to a first-class, synced entity. A `PersonaRecord` (@Model, mirror `FolderRecord`) carries a sealed `PersonaSecret` (`displayName`, `kind`, `isolationPolicy`, `primaryProfileItemID`, `primarySpaceID`) and syncs via a **new CloudKit record type `VaultPersona`** (mirror `VaultFolder` — NOT columns on `ItemRecord`, which would hit the whole-record LWW trap). On first unlock, an idempotent seed creates one `.personal` persona from the existing default Identity item; existing installs migrate the same way. P0's persona-ready seams rebind to the **active** persona.

Canonical source of truth: `proposal-v3-locked-decisions.md` — P1 section, **D12** (`Persona.primarySpaceID` single pointer, no `isPrimary` flag), **D7** (per-persona selection is local, not synced), **D10** (Persona → Space → Items), **INV-R03** (isolationPolicy defined+stored in P1, *consumed* in P2). Builds on `p0-plan.md` (merged).

## Guiding constraints
- **Persona is additive.** `isDefaultIdentity` stays — the AutoFill extension reads it (`VaultReader.defaultIdentityUsername`). Persona `primaryProfileItemID` is a soft link to that identity item.
- **Two invariants** (mirror `normalizeDefaultIdentity`): ≥1 persona always; exactly 1 *default* persona. **Default** (synced, converged) ≠ **active** (device-local UI selection, like `selectedPaymentCardId`).
- **Multi-device seed convergence via a fixed bootstrap id** (`Persona.bootstrapPersonalID`) so two devices that each first-run-seed produce the *same* record id → CloudKit LWW merges to one. No duplicate-merge pass needed (contrast the folder seed which needs `mergeDuplicateSeedFolders`).
- **LWW discipline:** every write to a persona's sealed payload MUST bump `updatedAt` or the pull gate drops it (mirror `FolderRecord`/`updateFolder`).
- **Local-first:** works fully when `iCloudSyncEnabled` is OFF. Never gate persona on iCloud.
- Localization EN+VI mandatory; design tokens only; Polaris SVG icons; `nonisolated` crypto/data types. Files <200 LOC.

## Phases

| # | Phase | Status | Depends on | Est |
|---|-------|--------|-----------|-----|
| P1.1 | [Persona model + store + CloudKit sync](p1-phase-P1.1-persona-model-store-sync.md) | pending | — | 4.5h |
| P1.2 | [Repository: load, seed/migrate, invariants, resolver, rebind](p1-phase-P1.2-repository-seed-invariants-rebind.md) | pending | P1.1 | 5h |
| P1.3 | [Active-persona selection + switcher UI](p1-phase-P1.3-active-persona-switcher-ui.md) | pending | P1.2 | 2.5h |

Sequential: **P1.1 → P1.2 → P1.3** (each phase's files are consumed by the next). No safe parallel track — the model must exist before the repository can load it, and the switcher before it can drive selection.

## Dependency graph
```
P1.1 (model/store/sync) ─> P1.2 (repo: seed + invariants + resolver + rebind) ─> P1.3 (settings + switcher UI)
```

## File ownership (no two phases share a file)
- **P1.1:** `VaultifyCore/Models/Persona.swift` (new) · `VaultifyCore/Store/PersonaRecord.swift` (new) · `VaultifyCore/Store/VaultStore.swift` · `Vaultify/Services/Sync/CloudSyncService.swift`
- **P1.2:** `Vaultify/Data/Repositories/VaultRepository+Personas.swift` (new) · `Vaultify/Data/Repositories/VaultRepository.swift` · `Vaultify/Data/Repositories/VaultRepository+Folders.swift` · `VaultifyCore/Models/Folder.swift` · `Vaultify/App/SettingsStore.swift`
- **P1.3:** `Vaultify/Features/Personas/PersonaSwitcherSheet.swift` (new) · `Vaultify/Features/Home/HomeScreen.swift` · `Vaultify/Features/Search/SearchScreen.swift` · `Vaultify/Features/Settings/SettingsScreen.swift` · `Vaultify/Resources/Localizable.xcstrings`

> `PersonaID.swift` (P0) is retained: its `placeholder` constant is *replaced at call sites* by `activePersona.id` in P1.3; the storage shape (`[personaID: value]`) is unchanged, so no migration of `lastSelectedSpaceByPersona`.

## Migration / rollback
- **Migrate:** existing installs have `isDefaultIdentity` but no persona → `ensurePersonaExists()` (in `reload()`) seeds the Personal persona on first unlock, linking the default identity + primary Space. New vaults hit the same path after onboarding seeds identity/folder (DRY — one seed path, `OnboardingFlow` untouched).
- **Rollback:** P1 is additive and non-destructive. Reverting the code leaves orphan `PersonaRecord` rows (ignored) and `activePersonaID` in defaults (ignored). No existing item/folder is mutated by the seed (`FolderSecret.personaId` stays nil), so no re-seal/LWW churn to unwind.

## Key references
- Sync LWW + record-type pattern: `VaultFolder` in `CloudSyncService.swift:110,199-225`; `upsertFolderFromRemote` `VaultStore.swift:169-201`.
- Convergence pattern to mirror: `normalizeDefaultIdentity` `VaultRepository.swift:147-168`.
- P0 seams: `PersonaID.swift`; `primarySpaceId` `VaultRepository+Folders.swift:48`; `FolderSecret.personaId` `Folder.swift:40-49`; `allSpacesSearchAllowed` `VaultRepository+Folders.swift:277`.
- Test harness: `VaultifyTests/IdentityInvariantTests.swift:9-17` (in-memory store + `adoptUnlocked` fixed key).

## Out of scope (P2+)
`PersonaIsolationMode` *consumption* (search/AutoFill hard-exclusion INV-R03; `allSpacesSearchAllowed` wired to policy), ranking engine, Create-Login context, per-site alias model, persona avatars, persona edit/delete UI + delete guard, isolationPolicy editor. P1 stores `isolationPolicy` but nothing reads it for gating yet.
