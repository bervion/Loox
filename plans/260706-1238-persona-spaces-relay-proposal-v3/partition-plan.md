---
title: "Persona↔Space Hard Partition"
description: "Bind each Space to exactly one persona so switching persona filters the whole app (Home/Items/Search), fail-closed for INV-R03."
status: done
priority: P2
effort: 9h
branch: feat/persona-space-partition
tags: [persona, spaces, partition, isolation, sync]
created: 2026-07-06
---

# Persona↔Space Hard Partition

Upgrade persona from a "lens" to a real partition: every Space (`Folder`) belongs to
exactly ONE persona (`Folder.personaId`). Active persona filters Home, Items, Search to
that persona's Spaces + their items. Persona stays device-local-active + synced-default.

Source of truth for decisions: `proposal-v3-locked-decisions.md` (D10/D12, **INV-R03**).

## Design decisions (AUTONOMOUS — fail-closed defaults taken)

| # | Decision | Default taken |
|---|----------|---------------|
| 1 | Backfill of `personaId == nil` folders | → **default persona** (in-place patch on reload, re-seal, bump `updatedAt`, LWW-safe, idempotent). Pre-persona vault becomes the personal persona's. |
| 2 | Unfiled items (`folderId == nil`) | Belong to **default persona only**. A non-default (incl. strictAnonymous) persona never sees Unfiled. |
| 3 | Item→persona derivation | Item belongs to its Space's `personaId`; nil folder → default persona. One resolver (`personaID(forItem:)` upgraded off the `primarySpaceID` heuristic). |
| 4 | Filter surface | Defined ONCE at repo level (`spaces(for:)`, `items(for:)`, persona-scoped `scoped()`/`search()`). UI just reflects. Partition filter is **universal** (all personas); isolation policy only gates escape hatches. |
| 5 | Create paths | New Space under active persona X → `personaId = X`; new item inherits its Space's persona; `addPersona` seeds a starter Space it owns (fixes `folders.first` leak). |
| 6 | AutoFill / extension | **Stays cross-persona by host** — NOT partitioned (credential availability). `CredentialIdentityService.refresh` item source untouched. |
| 7 | Shared-with-Me pseudo-space | Shown regardless of active persona (read-only, not owned), **suppressed under strictAnonymous** (reuses `showsSharedScope`). |
| 8 | Persona delete | Reassign owned Spaces+items → default persona (re-stamp + re-seal). Never destroy user data. |

**Needs user confirmation:** none blocking. Decision 8 (reassign vs tombstone) and decision 2
(Unfiled→default) are the two most reversible — flagged in phase files, safe defaults chosen.

## Phases (dependency-ordered)

| Phase | Title | Deps | Effort |
|-------|-------|------|--------|
| [01](partition-phase-01-model-backfill-filters.md) | Model migration, resolver, repo filters | — | 4h |
| [02](partition-phase-02-ui-filtering.md) | UI filtering: Home / Items / Search | 01 | 2.5h |
| [03](partition-phase-03-create-paths.md) | Create paths: Space / item / persona | 01 | 1.5h |
| [04](partition-phase-04-persona-delete-reassign.md) | Persona-delete space+item reassign | 01 | 1h |

Phase 01 is the fail-closed foundation (all filtering + INV-R03 enforced at the repo source).
02/03/04 all depend only on 01; 03 and 04 both touch `+PersonaManagement.swift` → run sequentially.

## Top 3 risks
1. **primarySpaceID split-brain leak (INV-R03).** P1 `addPersona` set `primarySpaceID = folders.first` → a non-default persona points at a default-owned folder; strictAnonymous `defaultSearchScope` would then search INTO the default's Space. Phase 01 reconciles (clear stale pointers) + explicit exclusion test.
2. **Regression on the 250+ suite** from persona-scoping shared `scoped()`/`search()`. Mitigated: backfill-to-default means single-persona tests keep seeing everything (active = default owns all).
3. **Multi-device backfill divergence** if two devices have different (promoted) defaults offline. Low likelihood (default is normally the fixed bootstrap persona); LWW converges to one owner; documented.

## Build & test
`tuist generate --no-open` (new files) → `make check`. Tests: sim `83B71AA8-A3FA-4095-9D05-226A6FE1FE75`,
`xcodebuild test ... -only-testing:VaultifyTests/PersonaPartitionTests` (+ existing PersonaIsolationTests, VaultRepositoryFolderTests must stay green).
