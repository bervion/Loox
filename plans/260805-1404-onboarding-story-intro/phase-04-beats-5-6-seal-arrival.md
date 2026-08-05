# Phase 04 — Beats 5–6: sanctuary, hold-to-seal, exit burst, arrival bridge

Context: `concept-final.md` §2 rows 5–7, §4 Integration; `research/researcher-01-flow-integration.md` (tutorial handoff).
Priority: P1. Status: pending. Depends: phase-03.

## Beats
5. **Sanctuary** — 24 surviving scraps settle into a slow-rotating ring around the Loox mark; sigil arcs trim-draw (Canvas `Path.addArc`, pre-blurred stroke glow symbol); calm accent aurora; theme fully resolved. Press-to-peek demo row: fixed 6-dot mask, `Font.vaultCode`, `.onLongPressGesture(minimumDuration: 0.15, pressing:)` → `GlyphResolveText` 0.4s reveal, release → INSTANT conceal. Micro-parallax ring counter-drift via `visualEffect`.
6. **Commitment** — ring tightens above one `BrandCapsuleCTA` (`Metric.controlLarge`): hold-to-seal fills a progress sweep across the capsule (~`Motion.slow`-derived 0.9s, pure fn of press-start via TimelineView); early release springs back (`Motion.spring`); at 100%: `Haptics.tap()` (the story's ONLY haptic), ring contracts + bursts outward (LooxSwirl `.dismiss` verb ~0.8s), stage blooms, `storyIntroCompleted = true` via `withAnimation(completionCriteria:)`, route crossfade lands Home. `.accessibilityRepresentation { Button }` so VoiceOver/Switch Control complete without timed hold. Guard press-start against scenePhase suspension (reset on background — critic finding).
7. **Arrival bridge** — completing (not skipping) sets `storyIntroWantsFirstItem = true`; after the firstRun tutorial ends (TutorialCoordinator completion/skip), Home consumes the hint once and pulses/spotlights the Add button (one gentle pulse, reduceMotion-guarded), then clears it.

## Files
- Extend stage/beat views; `StorySealCTA.swift` if `BrandCapsuleCTA` cannot host the progress sweep cleanly (<200 lines); Home Add-button pulse wiring (find Add button owner view; keep change minimal, one-shot).

## Success criteria
- Peek reveals only while pressed and conceals instantly; seal requires full hold, resets on early release AND app backgrounding; exactly one haptic in the whole story; skip does NOT set the first-item hint; Add pulse fires once after tutorial, never again; `make check` green.

## Todo
- [ ] Beat 5 ring + sigil + peek row
- [ ] Beat 6 hold-to-seal + burst + handoff
- [ ] scenePhase hold guard
- [ ] Arrival bridge (hint + Add pulse post-tutorial)
- [ ] make check
