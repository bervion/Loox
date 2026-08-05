# Phase 02 — Stage engine: scroll progress, particle field, dark canvas

Context: `concept-final.md` §1 Shape, §4 (offset plumbing, snap guarantee); `research/researcher-05-swiftui-feasibility.md`.
Priority: P0. Status: pending. Depends: phase-01.

## Requirements
- One scalar `journeyProgress` (0…1) drives the whole stage; scroll writes must NOT re-evaluate the beat column.
- Stage: committed near-black canvas (both modes) → cross-fades to `theme.color(.background)` across beat 4.
- No Metal shader: `MeshGradientView`-style baked mesh veil + `TimelineView(.animation)` + `Canvas` symbol-stamped particles (cap ~90, pre-blurred glow symbols, no per-draw filters). Pure functions of (t, progress, seeds) — LooxAnimationEngine pattern.

## Files
Create in `Vaultify/Features/StoryIntro/` (each <200 lines):
- `StoryScrollProgressModel.swift` — `@Observable` model; 17.3 GeometryReader+PreferenceKey path (quantize 1–2pt), iOS 18+ `.onScrollGeometryChange` behind availability.
- `StoryStageView.swift` — pinned full-bleed layer: veil/mesh + Canvas particle field + dark→theme crossfade; `paused = reduceMotion || scenePhase != .active`; `.accessibilityHidden(true)`.
- `StoryParticleField.swift` — seeded scrap structs (note card, chat bubble, browser pill, key dot symbols via `Image(vaultIcon:)` Polaris glyphs), Lissajous drift, position = fn(t, progress).

## Gate task (do FIRST)
Verify `.viewAligned` snapping with full-height `containerRelativeFrame` pages on an iOS 17.3 simulator. If it misbehaves: free scroll + on-gesture-end settle animation of stage progress to nearest beat (design survives unchanged).

## Steps
1. 17.3 snap verification spike.
2. Progress model + wire into skeleton scroll.
3. Stage veil + crossfade; particle field with static scatter first, then drift.
4. Instruments sanity pass in Simulator (real-device pass deferred to phase-06).

## Success criteria
- Scrubbing the scroll drives stage state with no hitching in Simulator; beat column unaffected by offset writes; Reduce Motion freezes the stage; `make check` green.

## Todo
- [ ] 17.3 `.viewAligned` spike (decision recorded here)
- [ ] StoryScrollProgressModel
- [ ] StoryStageView veil + crossfade
- [ ] StoryParticleField
- [ ] make check
