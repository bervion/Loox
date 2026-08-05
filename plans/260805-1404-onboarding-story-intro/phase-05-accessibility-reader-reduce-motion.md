# Phase 05 — Accessibility: Reader view, Reduce Motion, Dynamic Type, VoiceOver

Context: `concept-final.md` §4 (RM path, Dynamic Type, Reader); design-dna adversarial checklist (`docs/design-dna-standard.md`).
Priority: P1. Status: pending. Depends: phase-04.

## Requirements
- **Reduce Motion**: TimelineViews paused; per-beat static poster compositions (scatter poster beats 2–3, gathered ring 5–6) from snapped beat index; `.scrollTransition` collapses to opacity-only; sheen/hint/breathe/burst skipped; all discrete animation via `.vault(_, reduceMotion:)`; single haptic kept; hold-to-seal keeps its progress arc (functional feedback).
- **Reader path**: `StoryIntroReaderView` — same copy, CTA, Skip; plain scroll; static poster stage; no `containerRelativeFrame` locks. Activated when `dynamicTypeSize >= .accessibility1` OR VoiceOver running (also the macOS fallback).
- **VoiceOver**: stage `.accessibilityHidden(true)`; beats read as grouped text in order; Skip/CTA ordinary buttons; peek row exposed via accessibilityRepresentation.
- **Dynamic Type / small screens**: VI-first budgets at SE 375 (title ≤2 VI lines, body ≤3, single-line prompts); `Space` tokens + `Space.gutter` edges; iPad clamp `.vaultContentWidth(.form)`.

## Files
- `StoryIntroReaderView.swift` (new, <200 lines); RM branches inside stage/beat views (no separate fork of choreography — same pure functions, frozen inputs).

## Verification (design-dna device matrix)
- SE 375 + Max 430 with VI strings; accessibility XXL; light+dark live switch mid-story; Reduce Motion + Reduce Transparency; VoiceOver full pass; file the 5 written checklist answers in this phase file when done.

## Success criteria
- Story fully usable with zero motion; no clipped/truncated VI text at any size; VoiceOver completes the story end-to-end; `make check` green.

## Todo
- [ ] RM static posters per beat
- [ ] StoryIntroReaderView
- [ ] VoiceOver pass
- [ ] Dynamic Type + VI budgets verified
- [ ] Checklist answers filed here
