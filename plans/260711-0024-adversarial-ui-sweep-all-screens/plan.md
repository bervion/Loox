---
title: "Adversarial UI/UX Sweep — All Screens"
description: "Challenge every Vaultify screen/sheet against the Design DNA standard until the whole app is consistent, smooth, and comfortable on SE and Pro Max."
status: done
priority: P2
effort: ~5-7d
branch: feat/design-dna-controlled-reveal
tags: [ios, swiftui, ui-ux, design-system, adversarial-review, accessibility, localization]
created: 2026-07-11
---

# Adversarial UI/UX Sweep — All Screens

Every screen in Vaultify — old or new, no exceptions — is challenged and tuned against
`docs/design-dna-standard.md` (the acceptance bar) until the app is consistent, smooth, and
comfortable on small AND large screens. Adversarial mode: for each screen the reviewer WRITES the
answers to the protocol questions, then fixes what fails. Output = "trải nghiệm sướng, tối ưu,
mượt": no broken layouts, no oversized/truncated text on SE or Pro Max, no wrong colors after
theme switch, no hard-to-tap targets, consistent haptics, consistent spacing/radius/typography.

**Scope**: 187 `View` structs across `Vaultify/Features/**`, `Vaultify/DesignSystem/Components/**`,
and `VaultifyAutoFill/**`. iOS 17.6 ceiling (18+/26+ guarded). Tokens only. Every changed string →
`Localizable.xcstrings` EN + VI (via orchestrator, see Shared-file protocol).

**Standing on the prior pass**: `plans/260710-2304-loox-design-dna-controlled-reveal/` already
reworked Home / Item Detail / Search / Unlock and shipped the primitives (`Radius.concentric`,
`GlyphResolveText`, `CopyMorphIcon`, `LooxGateShape`, recents helper). Those clusters are STILL
re-reviewed here (regression + consistency), but expect fewer findings.

## The method (every cluster phase does this)

See `phase-01-shared-primitives.md` header and `docs/design-dna-standard.md → adversarial protocol`.
Each cluster phase produces TWO deliverables before any fix:
1. A **findings table** at `reports/findings-phase-XX.md`: `screen | protocol Q(1-5) | finding | fix | severity | status`.
2. A **strings manifest** at `strings-manifest-phase-XX.md` (plan dir): every new/changed user-facing
   string as `key | EN | VI | context`. Phases NEVER edit `Localizable.xcstrings` directly.
Then the phase applies the fixes to its OWNED files only.

### In-code audit gates (run per phase over OWNED files — see each phase for the grep set)
- **SE-width / Dynamic Type**: grep `\.frame(width:` / `GeometryReader` / `minimumScaleFactor` /
  `lineLimit(1)`; flag fixed frames + single-line labels that clip the longest VI string.
- **Typography**: grep `\.font(\.` and `\.font(.system` → must be `vaultType`/`Font.vaultCode`.
- **Radius**: grep `cornerRadius(` numeric + `RoundedRectangle(cornerRadius:` → token/`concentric`.
- **Spacing**: grep numeric `\.padding(` literals → must be `Space.*`.
- **Hit target**: grep `\.frame(width:` on tappable glyphs → padded hit area ≥ `Metric.hitMin` (44).
- **Haptics**: grep `Haptics\.` call sites → cross-check the vocabulary table (copy = `success` from
  `ClipboardService`, not the view; error/warning/tap correct; never doubled).
- **Color**: grep `\.white|\.black|\.gray|\.red|\.primary|\.secondary` raw → must be semantic roles,
  except allowed exemptions (camera/QR/favicon/PDF/literal light-dark preview swatch).

## Phases

| # | Phase | Owned scope (dirs) | Screens | Parallel wave | Status |
|---|-------|--------------------|---------|--------------|--------|
| 0 | Inventory verification & registry (no code) | — reads all | 187 | W0 first | done |
| 1 | Shared primitives & components | `DesignSystem/Components/*`, `DesignSystem/PolarisIcon.swift`, `DesignSystem/Tokens/Elevation.swift`, `VaultifyCore/BrandLogoMark.swift`, `Features/Components/*`, `Capabilities/*` | 33 | W1 (blocks W2) | done |
| 2 | Onboarding + Unlock | `Onboarding/*`, `Unlock/*` | 20 | W2 | done |
| 3 | Home + Search (re-review) | `Home/*`, `Search/*` | 16 | W2 | done |
| 4 | Items + Folders + Vault | `Items/*`, `Folders/*`, `Vault/*` | 20 | W2 | done |
| 5 | Item Detail + Passkeys (re-review detail) | `ItemDetail/*`, `Passkeys/*` | 22 | W2 | done |
| 6 | Item Editor | `ItemEditor/*` | 12 | W2 | done |
| 7 | Watchtower + Generator | `Watchtower/*`, `Generator/*` | 10 | W2 | done |
| 8 | Settings core + Security + Data | `Settings/*` (excl `Appearance/`), `ImportExport/*`, `EmergencyKit/*` | 16 | W2 | done |
| 9 | Appearance + About | `Settings/Appearance/*`, `Settings/AboutView.swift`, `DesignSystem/Wallpaper/*` (flag-gated engine, review-light) | 6+ | W2 | done |
| 10 | Personas + Profile | `Personas/*`, `Profile/*` | 14 | W2 | done |
| 11 | Sharing — owner flow + approval + recipient | `Sharing/*` (excl `QuickView/`, `QuickLink*`) | 16 | W2 | done |
| 12 | Sharing — Quick Link + Quick View | `Sharing/QuickLink*`, `Sharing/QuickView/*`, `Sharing/SharedWithMeScreen.swift` | 10 | W2 | done |
| 13 | Main shell + Mac surfaces | `Main/*`, `App/RootView.swift` (router + PrivacyShield + controlledReveal), `App/VaultifyApp.swift` (review-light) | 16 | W2 | done |
| 14 | AutoFill extension UI (system material rules) | `VaultifyAutoFill/*` | 11 | W2 | done |
| 15 | Verification, xcstrings merge, consolidated report, QA checklist | — | — | W3 last | done |

Screen counts are surface counts (View structs incl. sub-rows/sheets), not file counts. Registry with
exact per-struct assignment is Phase 0's deliverable (`reports/screen-registry.md`).

## Parallelization waves
- **W0**: Phase 0 alone — validates that all 187 surfaces map to exactly one phase (unassigned = plan FAIL).
- **W1**: Phase 1 alone — reviews+fixes the SHARED primitives so W2 can treat them as frozen/read-only.
- **W2**: Phases 2–14 have **disjoint file ownership** → run in parallel. Recommend 3 sub-batches of
  ~4 agents to bound concurrency and serialize the strings-manifest merge; no code file is shared.
- **W3**: Phase 15 — after all W2 merged.

## Shared-file protocol (CRITICAL)
- `Vaultify/Resources/Localizable.xcstrings` is **orchestrator-owned**. Phases write EN+VI pairs to
  `strings-manifest-phase-XX.md`; the orchestrator merges by key (append-only, atomic). No phase edits
  the catalog.
- Shared DesignSystem/Feature components (Phase 1's scope) may be **read** by any W2 phase but edited
  **only** by Phase 1. If a W2 phase needs a shared-component change, it files a note in
  `reports/shared-component-requests.md` for the orchestrator/Phase 1 — no cross-phase component edits.
- Phase 15 owns the final `tuist generate` + compile + tests + catalog reconciliation.

## Dependencies
- P0 → all (registry must show zero unassigned surfaces before W2 starts).
- P1 → all W2 phases (shared primitives frozen first).
- P15 → P1–P14 merged.

## Success (whole sweep)
- `make check` green (app + embedded extension); `make test` green.
- Zero raw `.font(...)` / hardcoded radius / numeric padding / raw color (outside exemptions) in any
  owned file; every new/changed string EN+VI present in the catalog.
- Every surface passes the multi-device matrix: SE (375) + Pro Max (430), Dynamic Type default/XL/AX-XXL,
  light+dark, Reduce Motion + Reduce Transparency, EN+VI — recorded in per-phase findings tables.
- Consolidated findings-and-fixes report + a manual device-QA checklist handed to the user (Phase 15).
- No surface left unreviewed (Phase 0 registry ⇄ Phase 15 closeout cross-check).

Details: `phase-00 … phase-15`.
</content>
</invoke>

## Registry amendments (post phase-00, orchestrator-locked)
- Phase 0 registry: 224 surfaces total (187 View + 37 ButtonStyle/Modifier/Shape/Representable), 0 unassigned — `reports/phase-00-surface-registry.md`.
- `Vaultify/Security/UserActivityMonitor.swift`: review-EXEMPT (non-visual security monitor; no UI surface).
- Mac/iPad shell documentation gap in `docs/app-feature-map-ui-ux.md`: follow-up docs task, NOT in this sweep.

## Mid-sweep standard addition (260711, user-requested)
"Action hierarchy — no button walls" rule added to design-dna-standard.md AFTER phases 2/4/5/6/8/9
completed. Phase 15 MUST run a cross-cutting button-hierarchy audit over the WHOLE app (all phases,
including completed ones): flag any screen/sheet state with 3+ stacked buttons or rank-inconsistent
button sizes; completion screens (link created / share sent / kit generated) are priority suspects.
User-named hot spot: QuickLink post-create result surface (phase 12) — too many buttons, weak layout.
