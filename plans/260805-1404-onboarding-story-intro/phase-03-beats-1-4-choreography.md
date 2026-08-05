# Phase 03 — Beats 1–4: hook, chaos, consequence, turn

Context: `concept-final.md` §2 Storyboard rows 1–4, §3 Copy; `research/researcher-03-reactbits-catalog.md`.
Priority: P1. Status: pending. Depends: phase-02.

## Beats
1. **Hook** — lone dot breathing (~4s sine, LooxLogoBreathe cadence); title whole-block blur-in via `.scrollTransition` (blur ≤8, hero line only); "Kéo lên" hint pulse (`phaseAnimator`, ±4pt, reduceMotion-guarded).
2. **Chaos** — dot splits into scraps as progress rises: `lerp(center, scatterSeed[i], smoothstep(beatProgress))` + drift; copy staggered opacity+offset (no per-row blur); futility line closes.
3. **Consequence** — drift freezes; one chat scrap brightens; optional "Chạm để gửi" tap (SpatialTapGesture) → concentric ripple rings (`Path` ellipse strokes, easeOutCubic radius) + ghost clones stamping outward + subtle warning tinge lerp (never full red). Non-tappers: soft auto-play as they scroll past. NO stats.
4. **Turn** — signature scrub: every scrap `lerp(scatterPos[i], ringSlot[i], easeInOut(beat4Progress))` driven directly by scroll offset; warning hue drains, accent rises, canvas cross-fades to theme. Reversible (scroll back = scatter again).

## Rules
- All durations via `Motion` tokens + `.vault(_, reduceMotion:)`; no raw literals.
- Haptics: NONE in beats 1–4 (silence is the design).
- Copy keys from `concept-final.md` §3 wired as placeholders (final l10n pass in phase-06).

## Files
- Extend `StoryStageView`/`StoryParticleField` beat choreography; `StoryBeatView.swift` (copy column composition, `OnboardingStepHeader`-style); tap handling in `StoryIntroScreen`.

## Success criteria
- Full scroll 1→4 reads as one continuous story; reverse scroll reverses it; consequence tap works and auto-plays when skipped; Reduce Motion shows per-beat static posters; `make check` green.

## Todo
- [ ] Beat 1 hook
- [ ] Beat 2 chaos scatter
- [ ] Beat 3 ripple + tap-to-send
- [ ] Beat 4 convergence scrub
- [ ] make check
