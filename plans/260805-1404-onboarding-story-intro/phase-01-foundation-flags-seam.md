# Phase 01 — Foundation: flags, feature gate, RootView seam, skeleton screen

Context: `concept-final.md` §4 Integration; `research/researcher-01-flow-integration.md`.
Priority: P0 (everything else builds on this). Status: pending.

## Requirements
- One-time story screen slots between onboarding completion and first Home visit, without touching TutorialCoordinator.
- Story never appears for restore users; replays after full recovery re-onboarding; UI tests never see it.

## Files
Create:
- `VaultifyCore/Tutorial/StoryIntroFeature.swift` (or sibling location mirroring `TutorialFeature`) — `enabled` kill switch.
- `Vaultify/Features/StoryIntro/StoryIntroScreen.swift` — skeleton: 6 placeholder full-height beats in a vertical `ScrollView` (`.containerRelativeFrame(.vertical)`, `scrollTargetLayout`, `.scrollTargetBehavior(.viewAligned)`, indicators hidden), Skip top-trailing (44pt padded), placeholder CTA on beat 6 that completes the story.
Modify:
- `Vaultify/App/SettingsStore.swift` — `storyIntroCompleted` (key `story_intro_completed`), `storyIntroWantsFirstItem` (key `story_intro_wants_first_item`), Key enum entries (snake_case convention L313-337).
- `Vaultify/App/RootView.swift` `.unlocked` branch (L44-50) — render `StoryIntroScreen` INSTEAD OF `AdaptiveRootView` while `StoryIntroFeature.enabled && !settings.storyIntroCompleted`. Never fullScreenCover/overlay.
- `Vaultify/App/AppEnvironment.swift` — DEBUG test-isolation default `storyIntroCompleted = true` (next to L177) + `-ui-test-story` opt-in arg mirroring `-ui-test-tutorials` (L123-135).
- `Vaultify/Features/Onboarding/JoinVaultFlow.swift` (~L148) — restore path sets `storyIntroCompleted = true`.
- `VaultSession+Recovery` — recovery reset clears both story flags.
- `Vaultify/Analytics/AnalyticsEvents.swift` — `storyIntroEnded(outcome:furthestBeat:)` factory + `auditSamples` entry; `.analyticsScreen("story_intro")` on the screen.

## Steps
1. Flags + feature gate + seam + skeleton screen (compiles, story shows once, completes/skips into Home, tutorial fires after).
2. Restore/recovery/test-isolation wiring.
3. Analytics event + audit sample.
4. `tuist generate` then `make check`; run analytics audit test target if fast.

## Success criteria
- Fresh install path: onboarding → story skeleton → Home → firstRun tutorial (settle delay intact).
- Skip and complete both set the flag; restore path never shows story; `make check` green.

## Todo
- [ ] StoryIntroFeature gate
- [ ] SettingsStore flags
- [ ] RootView seam
- [ ] Skeleton StoryIntroScreen
- [ ] Restore + recovery wiring
- [ ] DEBUG isolation + launch arg
- [ ] Analytics event + auditSamples
- [ ] tuist generate + make check
