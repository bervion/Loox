---
title: "P2 — Persona Context + AutoFill"
description: "Consume PersonaIsolationPolicy: strictAnonymous hard-excludes cross-persona identity data from search, ranking, and AutoFill prefill (INV-R03). Greenfield pure suggestion engine + extension persona-awareness. No backend."
status: done
priority: P2
effort: ~11h
branch: feat/persona-p2-autofill
tags: [persona, autofill, isolation, search, ios]
created: 2026-07-06
---

# P2 — Persona Context + AutoFill

P1 defined + stored `PersonaIsolationPolicy` (standard/isolated/strictAnonymous). **P2 consumes it.**
The headline invariant **INV-R03**: a `strictAnonymous` active persona MUST NOT surface, rank, search,
or prefill identity-bearing data from ANOTHER persona — candidate **EXCLUSION**, never a down-rank.

Two real leak surfaces exist today (verified): (1) search widening to All Spaces
(`allSpacesSearchAllowed == true`, `VaultRepository+Folders.swift:278`) + the `seedScope`
`.allSpaces` fallback (`SearchScreen.swift:100`); (2) the AutoFill extension prefilling a NEW login's
username from the **global** default identity (`VaultReader.defaultIdentityUsername`,
`AutoFillView.swift:125`) with **no knowledge of the active persona** (`activePersonaID` is in
`UserDefaults.standard`, not the App Group). The in-app editor has NO prefill today, so it is
greenfield (no regression risk).

Canonical source of truth: `proposal-v3-locked-decisions.md` — P2 section, **INV-R03**, **D6** (scoped
search). Builds on `p1-plan.md` (merged). DRY: the pure engine lives in `VaultifyCore` so app + extension
share one implementation.

## Phases

| # | Phase | Status | Depends on | Est |
|---|-------|--------|-----------|-----|
| P2.1 | [Pure persona suggestion + isolation engine (VaultifyCore)](p2-phase-P2.1-suggestion-isolation-engine.md) | pending | — | 2h |
| P2.2 | [In-app isolation consumption: search gate + create-login suggestion](p2-phase-P2.2-inapp-isolation-search-editor.md) | pending | P2.1 | 4h |
| P2.3 | [Extension persona-aware prefill (App Group mirror + VaultReader)](p2-phase-P2.3-extension-persona-prefill.md) | pending | P2.2 | 2.5h |
| P2.4 | [Persona management completeness + QuickType threat-model](p2-phase-P2.4-persona-management-quicktype.md) | pending | P2.2 | 2.5h |

## Dependency graph
```
P2.1 (pure engine) ─> P2.2 (in-app: search gate + resolver + editor) ─┬─> P2.3 (extension prefill)
                                                                       └─> P2.4 (management + threat-doc)
```
P2.3 and P2.4 touch disjoint files and may run in parallel AFTER P2.2 — **except** both append to
`Localizable.xcstrings`; serialize catalog edits (run P2.3 then P2.4, or a single owner merges).

## File ownership (no two phases share a code file)
- **P2.1:** `VaultifyCore/Models/PersonaSuggestion.swift` (new) · `VaultifyTests/PersonaSuggestionTests.swift` (new)
- **P2.2:** `Vaultify/Data/Repositories/VaultRepository+PersonaContext.swift` (new) · `VaultRepository+Folders.swift` · `Vaultify/Features/Search/SearchScreen.swift` · `Vaultify/Features/ItemEditor/ItemEditorScreen.swift` · `Localizable.xcstrings` · `VaultifyTests/PersonaIsolationTests.swift` (new)
- **P2.3:** `VaultifyCore/SharedConfig.swift` · `VaultifyCore/VaultReader.swift` · `VaultifyAutoFill/AutoFillView.swift` · `Vaultify/Data/Repositories/VaultRepository.swift` (reload mirror call) · `Vaultify/Data/Repositories/VaultRepository+Personas.swift` (setActivePersona mirror call) · `VaultifyTests/AutofillPrefillIsolationTests.swift` (new)
- **P2.4:** `Vaultify/Data/Repositories/VaultRepository+PersonaManagement.swift` (new) · `Vaultify/Features/Personas/PersonaSwitcherScreen.swift` · `Localizable.xcstrings` (serialized) · `docs/codebase-summary.md` (threat-model note) · `VaultifyTests/PersonaManagementTests.swift` (new)

## INV-R03 — enforced in P2.2 (search + resolver) & P2.3 (extension). Concrete "must exclude" assertions
1. `strictAnonymous` ⇒ `allSpacesSearchAllowed == false`.
2. `strictAnonymous` ⇒ default search scope resolves to the persona's primary Space, **never** `.allSpaces` (fail-closed to empty if no primary Space).
3. `strictAnonymous` ⇒ `.sharedWithMe` scope not offered.
4. `identityUsername(forPersona:)` for a `strictAnonymous` persona returns its OWN profile email or nil — never the global default / another persona's.
5. Engine: candidates whose `sourcePersonaID != active` are removed (asserted empty), not last, under `strictAnonymous`.
6. Extension `autofillPrefillUsername` under `strictAnonymous` returns own profile or "" — never falls back to `defaultIdentityUsername`.

## Constraints
Localization EN+VI mandatory; design tokens + Polaris SVG only; `nonisolated` engine (runs off-main, shared
with the memory-tight extension). Files <200 LOC; new file → `tuist generate`. Any synced write bumps
`updatedAt`. `isDefaultIdentity` / `defaultIdentityUsername` stay the non-isolated fallback — layer on top.

## Out of scope (flagged YAGNI)
Per-item/per-folder persona partitioning (P1 leaves `FolderSecret.personaId` nil → isolation here is
suggestion/search-widening exclusion, not a full data partition — P3+). QuickType per-persona index
suppression (documented acceptance, host-scoped). Persona avatars. Cloudflare-native reply, aliases (P3+).
</content>
</invoke>
