---
title: "Loox Design DNA — Controlled Reveal"
description: "UI/UX quality pass over Vaultify iOS driven by the 10-point design-DNA audit (T1+T2+T3): protagonist reorder, typography/concentricity discipline, glyph-resolve reveal, honest copy, search superpower, ∞ gate motion."
status: completed (zoom transition deferred)
priority: P2
effort: ~3-4d
branch: feat/design-dna-controlled-reveal
tags: [ios, swiftui, ui-ux, design-system, motion, controlled-reveal]
created: 2026-07-10
---

# Loox Design DNA — Controlled Reveal

Executes the 10-DNA audit (`plans/reports/design-dna-audit-260710-2304-loox-apple-award-dna-report.md`).
Scope T1+T2+T3 all **user-approved**. Native `TabView` + floating Home header kept. Tokens only.
Every changed user-facing string → `Localizable.xcstrings` EN + VI. iOS 17.6 ceiling (18+/26+ guarded).

## Verify-first deltas from the audit (confirmed against code)
- **∞ gate motion UNBLOCKED**: `logo.imageset/logo.svg:12` is a single vector bezier of the ∞ loop
  (L/X separate at :14-15). `BrandLogoMark` uses a *different* asset (`SharedAssets/BrandLogo.imageset`).
  Audit Q3 ("no vector mark") is wrong → T3 gate is buildable, with blur-unlock fallback.
- **Clipboard interval = 30s default** (`SettingsStore.swift:122`) → honest string "Copied · clears in 30s".
- **Copy-morph icons already shipped**: `Icons.copy`=`ic_clipboard`, `Icons.copyDone`=`ic_clipboard_check`.
- Audit typo: ProfileRow padding is `Space.s4 = 16` (not 12); concentric result follows the helper.
- `TOTPCodeView` lives in `TOTPFieldRow.swift:4` (no own file). Recents needs a new `lastUsedAt` helper
  (`allItems` sorts by `updatedAt`, not use-time).

## Phases

| # | Phase | Tier | Value/Risk | Parallel? | Status |
|---|-------|------|-----------|-----------|--------|
| 0 | Primitives — `Radius.concentric`, `GlyphResolveText`, `CopyMorphIcon`, recents helper, concentric doc | — | blocking / low | first | done |
| 1 | Copy-tone + string catalog sweep (remove `!` and `—`, honest copy, EN+VI) | T1 | high / low | after P0 | done |
| 2 | Item Detail — typography, OTP object, trash→menu, card-diet, glyph reveal, copy-morph, bottom cluster | T1+T2+T3 | high / med | after P0 | done |
| 3 | Home protagonist reorder + concentric + vaultType sweep + card-diet | T2+T1 | high / med-high | after P0 | done |
| 4 | Search superpower — zero-state recents + filter chips + local operators + zoom transition | T2+T3 | high / med | after P0 | done (zoom transition deferred — shared nav files) |
| 5 | Brand gate motion — ∞ Shape, unlock/lock physics, Controlled Reveal doc | T3 | brand / med | after P0 | done |
| 6 | Tests · compile both targets · docs sync | — | gate / low | last | done |

**Parallelism:** P0 blocks all. After P0, **P2/P3/P4/P5 own disjoint code files → run in parallel.**
P1 (copy sweep) should land first as baseline; P2–P5 append their own new string keys.
P6 runs last. See each phase for file-ownership lists.

## Shared-file coordination (CRITICAL)
- `Vaultify/Resources/Localizable.xcstrings` is the **only** file multiple phases touch. It is key-scoped
  JSON: P1 owns the tone sweep on existing keys; P2–P5 **append** their own new keys. If phases run in
  parallel, serialize xcstrings writes (commit atomically) or the lead merges by key. No CODE file is
  shared across parallel phases.

## Dependencies
- P0 → everything (helper, components, recents used by P2/P3/P4).
- P1 → recommended before P2–P5 (baseline tone); not a hard code blocker.
- P4 zoom transition and P5 gate motion are iOS-18+/self-contained; both carry non-motion fallbacks.
- P6 requires P0–P5 merged.

## Success (whole pass)
- `make check` green (app + extension); `make test` green.
- No raw `.font(...)` / hardcoded radius in touched files; all new strings EN+VI.
- Reduce Motion + Reduce Transparency verified on every new motion; light+dark pass.
- Home shows a credential-first protagonist; Item Detail no longer a stack of generic stroked cards.

Details: `phase-00…phase-06`.
