# Phase 06 — Localization, tests, macOS treatment, polish

Context: `concept-final.md` §3 Copy, Decisions 5–7; `research/researcher-06-macos-arc-style-onboarding.md` (when done).
Priority: P2. Status: pending. Depends: phase-05.

## Localization
- All story keys into `Localizable.xcstrings` with EN source + VI + JA (JA = drafted values, flag native review); titles `.inAppLocalized`; runtime `appString()`. Copy rules: no "!", no em-dash, no interpunct; brand = Loox; vault = "kho".

## Tests
- Unit: progress→beat mapping, flag transitions (complete/skip/restore/recovery), arrival-hint one-shot semantics, analytics auditSamples entry.
- Existing suites must stay green (icon allowlist, IconCatalogTests, analytics audit).
- UI-test isolation verified: default-completed in DEBUG + `-ui-test-story` opt-in.

## macOS (owner decision 5)
- If researcher-06 confirms feasible: Arc/Dia-style full-screen takeover (hidden title bar, staged advancement via click/arrow keys — likely discrete steps over scroll-scrub; seal = click or spacebar-hold per research). Otherwise: `StoryIntroReaderView`.
- Keep macOS work behind the same `StoryIntroFeature` gate; do not block iOS ship on macOS.

## Polish + perf
- On-device Instruments pass (iPhone 12-class): scroll scrub with full particle field; fix any >16ms frames (particle cap ↓ from ~90, blur radius ↓, glow symbol reuse).
- Analytics screen + event verified in DebugView/console (fixed ids, no content).
- `docs/codebase-summary.md` + `docs/project-changelog.md` entries; README untouched.

## Success criteria
- `make check` green; all tests pass; VI/JA render verified at 375pt; Instruments pass recorded; docs updated. Ship gate: design-dna checklist answers from phase-05 attached to PR.

## Todo
- [ ] xcstrings EN/VI/JA
- [ ] Unit tests
- [ ] macOS treatment (per researcher-06)
- [ ] Instruments pass
- [ ] Docs sync
- [ ] PR
