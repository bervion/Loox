---
title: "Vaultify Navigation Redesign — Home + Items tabs, Pin/Archive/Frequently-Used"
description: "4-tab nav (Home/Items/Watchtower/Search), Settings+Generator off-tab, new pinned/archived/useCount metadata."
status: pending
priority: P2
effort: ~13h
branch: feat/vault-spaces-tags
tags: [navigation, swiftui, ios, vault, ux]
created: 2026-06-14
---

# Vaultify Navigation Redesign

Reshape the unlocked shell from **Vault / Generator / Watchtower / Settings** into a personalized
**Home / Items / Watchtower / Search** 4-tab layout. Settings moves to a Home header gear; Generator
moves to a Home "Utilities" section. Adds three new plaintext metadata fields on `ItemRecord`
(`pinned`, `archived`, `useCount`) powering a Pinned section, an Archive area, and Frequently-Used
sorting. Built on the open Spaces/Tags PR #1 (same branch). Each phase stays compilable via `make check`.

## Locked Decisions

| Decision | Choice |
|---|---|
| Tab bar | Home (`ic_home`/`_filled`) · Items (`ic_organization`/`_filled`) · Watchtower (`ic_plan`/`_filled`, NEW icons) · Search (`ic_search`, rightmost) |
| Settings | Off-tab → gear in Home header |
| Generator | Off-tab → "Utilities" row on Home (opens existing GeneratorScreen) |
| Search | Normal 4th tab w/ `.searchable` (iOS-18 `Tab(role:.search)` deferred — target 17.6) |
| New metadata | `pinned`/`archived`/`useCount` = PLAINTEXT columns on `ItemRecord` (NOT in sealed `ItemSecret` → codec unchanged) |
| `items` cache | Excludes archived AND trashed; new `archived` array mirrors `trashed` |
| Pinned ≠ Favorite | Separate flag + section + swipe/context action |
| Archive ≠ Recently Deleted | Separate flag; ArchiveScreen (no purge); "Recently Deleted" = existing `trashedAt` trash |
| Frequently Used | `useCount` incremented in `markUsed` (no re-seal) |
| Home sections default ON | Pinned, Favorite, Recently Created, Frequently Used |
| Home sections OPTIONAL | Recently Used, Recently Modified (via Customize Home) |
| Icon format | SVG→PDF via `rsvg-convert` to match existing PDF imagesets (verified working) |

## Phases

| # | Phase | Status | Depends |
|---|-------|--------|---------|
| 1 | [Icons import + constants](phase-01-icons-import.md) | pending | — |
| 2 | [Data model + repository](phase-02-data-model-repository.md) | pending | — |
| 3 | [Tab restructure](phase-03-tab-restructure.md) | pending | 1 |
| 4 | [Home tab](phase-04-home-tab.md) | pending | 1,2,3 |
| 5 | [Customize Home](phase-05-customize-home.md) | pending | 4 |
| 6 | [Items tab + Archive + category lists](phase-06-items-tab-archive.md) | pending | 1,2,3 |
| 7 | [Pin/Archive actions in rows + detail](phase-07-pin-archive-actions.md) | pending | 2,6 |
| 8 | [Cross-cutting: localization + docs + CloudKit verify](phase-08-localization-docs.md) | pending | 1-7 |
| 9 | [Tests + verification](phase-09-tests-verification.md) | pending | 2-7 |

## Key Dependencies

- Phases 1 & 2 are independent → can run in parallel (different files: assets+`PolarisIcon.swift` vs `VaultifyCore`+repo).
- Phase 3 needs Phase 1 (tab icons). Phases 4 & 6 need 1+2+3. Phase 7 needs 2 (actions) + 6 (ArchiveScreen).
- Phase 8 (localization sweep) runs after UI phases land strings. Phase 9 (tests) needs the repo API (2) done.
- Every phase ends green on `make check`; Phase 9 must end green on `make test`.

## Open Questions

See end of phase-09. Key ones: exact Home section order, empty-category visibility on Items tab, Search tab empty-state copy.
