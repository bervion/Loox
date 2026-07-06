---
title: "P0 — Space Hardening"
description: "Harden the existing Folder-as-Space UX (persistence, primary resolver, scoped search) persona-ready for P1, no backend."
status: done
priority: P1
effort: ~11h
branch: feat/persona-p0-space-hardening
tags: [spaces, folders, search, persona-readiness, ios]
created: 2026-07-06
---

# P0 — Space Hardening

Harden the already-shipped "Space" UX (UI brands `FolderRecord` as Space) so it survives launches, has a single primary-Space resolver, and scopes search — all built **persona-ready** so P1 (PersonaRecord) rebinds without schema/migration churn. **No rename migration, no backend.** Type name stays `FolderRecord` (D11).

Canonical source of truth: `proposal-v3-locked-decisions.md` (D6, D7, D10, D11, D12; INV-R01…R05).

## Guiding constraints
- Persona does NOT exist yet → key persistence by a **placeholder persona id** (nullable, single "default" bucket); P1 swaps the key, not the storage shape.
- Do **NOT** add `isPrimary` to `FolderRecord` (D12 — single-pointer `Persona.primarySpaceID` later). Centralize the `folders.first` heuristic into one resolver now.
- Sealed-content changes must bump `updatedAt` (LWW trap, `VaultStore.upsertFromRemote`). S3 adds a field but does not trigger a re-seal.
- Localization EN+VI mandatory; design tokens only; no SF Symbols.

## Phases

| # | Phase | Status | Depends on | Est |
|---|-------|--------|-----------|-----|
| S1 | [Primary-Space resolver](p0-phase-S1-primary-space-resolver.md) | ✅ done | — | 1.5h |
| S0 | [Selected-Space persistence](p0-phase-S0-selected-space-persistence.md) | ✅ done | S1 | 2h |
| S2 | [Scoped search + chip](p0-phase-S2-scoped-search.md) | ✅ done | S0, S1 | 3.5h |
| S4 | [Unfiled semantics](p0-phase-S4-unfiled-semantics.md) | ✅ done | S2 | 1h |
| S5 | [Shared-with-Me scope compat](p0-phase-S5-shared-with-me-scope.md) | ✅ done | S2 | 1.5h |
| S3 | [FolderSecret personaId readiness](p0-phase-S3-foldersecret-personaid-readiness.md) | ✅ done | — (parallel) | 1.5h |

**Implemented 2026-07-06** on `feat/persona-p0-space-hardening`. Compile clean (`make check`), 7/7 unit tests pass (`SpaceHardeningTests`). Deviation from plan: S1 migrated **2 extra** `folders.first?.id` call sites in `OnboardingFlow.swift` (:96, :118) that the audit missed — same primary-Space heuristic, now 0 residual hits.

Recommended order: **S1 → S0 → S2 → S4 → S5**, with **S3 in parallel** (disjoint files: `Folder.swift` only).

## Dependency graph
```
S1 ─┬─> S0 ─> S2 ─┬─> S4
    │             └─> S5
S3 (independent, parallel)
```

## File ownership (no two active phases share a file)
- S1: `VaultRepository+Folders.swift` (add resolver), `ItemEditorScreen.swift`, `HomeScreen.swift`
- S0: `SettingsStore.swift`, `HomeScreen.swift` (after S1), `PersonaID.swift` (new)
- S2: `SearchScreen.swift`, `VaultRepository+Folders.swift` (search fn), `SpaceScope.swift` (new)
- S4: `VaultRepository+Folders.swift` (search fn — sequential after S2), `SpaceScope.swift`
- S5: `SpaceScope.swift`, `SearchScreen.swift` (sequential after S2)
- S3: `Folder.swift` (isolated)

> HomeScreen.swift and VaultRepository+Folders.swift are shared across phases → run those phases **sequentially**, never parallel. S3 is the only safe parallel track.

## Key references
- Audit (file:line): `../reports/from-dev-team-to-proposal-author-260706-1223-persona-relay-tasks-a-e-verification-report.md` §A
- Data model / sync LWW: `../reports/proposal-review-260706-1151-persona-email-alias-architecture-report.md` Part A

## Out of scope (P1+)
PersonaRecord, `Persona.primarySpaceID` structural pointer, persona switcher, isolationPolicy/strictAnonymous logic, symbol rename Folder→Space, alias model. P0 only leaves clean seams.
