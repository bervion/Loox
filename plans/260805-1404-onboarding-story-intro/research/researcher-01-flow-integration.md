# Research 01 — First-run flow map + story-intro insertion seam

Scope: where a one-time full-screen "story intro" slots in between onboarding completion and the existing first-run Tutorial. All paths absolute-relative to repo root `/Users/pham.nhu.chinh/Developer/Personal/Vaultify`.

## 1. Onboarding flow

- Driver: `Vaultify/Features/Onboarding/OnboardingFlow.swift`
  - Step enum L29: `welcome, join, create, name, emergencyKit, theme, biometric, done`.
  - Body = `ZStack { switch step }` (L36-103) + `.animation(.vault(.smooth(duration: 0.35), reduceMotion:), value: step)` L104 — step crossfade pattern.
  - `createVault` L155-176: creates vault (session becomes UNLOCKED here), logs `.vaultCreated` L158, seeds "My Space".
  - Completion: `OnboardingDoneStep` (L207-264). Its `onFinish` closure L98-101 logs `.tutorialComplete` then sets `env.settings.onboardingCompleted = true` (L100). Done step plays the brand circle-burst flood (`LooxLaunchController.press()`), hides content `.easeOut(0.25).delay(0.35)`, calls `onFinish` after 1.5 s (L252-263); Reduce Motion path calls `onFinish` immediately (L256-259).
- Restore path also completes onboarding: `Vaultify/Features/Onboarding/JoinVaultFlow.swift` `finish()` L148-151 logs `.vaultRestored` and sets `onboardingCompleted = true`. No theme step, no done step there.
- Persistence flag: `Vaultify/App/SettingsStore.swift`
  - `var onboardingCompleted: Bool` L65, UserDefaults key `Key.onboarding = "onboarding_completed"` L314. Key enum L313-337 = snake_case naming convention (`has_chosen_appearance`, `icloud_sync_enabled`...).
  - Loaded in init around L233-237.
- Reset path: `Vaultify/Security/VaultSession+Recovery.swift:93` sets `onboardingCompleted = false` (recovery/erase re-runs onboarding).
- Test isolation: `Vaultify/App/AppEnvironment.swift:177` forces `onboardingCompleted = true` under UI-test isolation (DEBUG block L166-180).

## 2. Route after onboarding → Home

- `Vaultify/App/RootView.swift`
  - `Route` enum L19; computed L21-24: `!env.settings.onboardingCompleted → .onboarding`; else `.unlocked` iff `env.session.state == .unlocked`, else `.locked`.
  - Switch L26-51. Unlocked branch L44-50: `AdaptiveRootView().tutorialHost(env.tutorial)` — tutorial host wraps ONLY the unlocked app.
  - Route change animation L69: `.animation(reduceMotion ? nil : .smooth(duration: 0.35), value: route)` — a new route case inherits this crossfade for free.
  - L112-118: `onChange(onboardingCompleted)` releases forced-light appearance gate (`env.markAppearanceChosen()`).
- After the Done step, session is already unlocked (from `createVault`), so flipping the flag lands directly on `.unlocked` → `AdaptiveRootView`.
- `Vaultify/Features/Main/AdaptiveRootView.swift` L48-67: tabs (`VaultUINavShell` → `MainTabView`) on phone; `VaultSidebarView` on iPad both-regular; `MacRootView` on macOS.
- `Vaultify/Features/Main/MainTabView.swift` L69/L76: Home tab hosts `HomeScreen()`. Default tab = `.home` (`Vaultify/App/UIStateStore.swift:53`).

## 3. Tutorial (existing first-run tour)

- Trigger: `Vaultify/Features/Home/HomeScreen.swift:233-239` — `.task { ...; env.tutorial.startIfNeeded(.firstRun) }` on Home's first unlocked appearance. `.onDisappear { env.tutorial.cancelPendingStart() }` L242. `.analyticsScreen("home")` L240.
- Coordinator: `Vaultify/Services/Tutorial/TutorialCoordinator.swift`
  - `settleDelay` default 1200 ms (L21) between the ask and the tour appearing (L57-71).
  - Gates in `startIfNeeded` L58-59: `TutorialFeature.enabled`, no flow already active, no pending start, `store.shouldPresent(flow.id)`.
  - `skip()` L97 / `advance()` L86 → `finish` L116-123: persists state + logs `.tutorialFlowEnded`.
- Persistence: `Vaultify/Services/Tutorial/TutorialStore.swift` — plain UserDefaults, key `"tutorial_state_\(flowID)"` L22, states `notStarted/completed/skipped` L10-14; `shouldPresent` = notStarted L30-32; `resetAll` L49 backs Settings "Show tutorials again".
- Flow data: `Vaultify/Services/Tutorial/TutorialFlow.swift` — `firstRun` id `"first-run"`, 3 steps L36-50 (anchors on Home's Add button + Security card, anchorless closing beat). Catalog `all` L28.
- Presentation: NOT a sheet/fullScreenCover — a spotlight OVERLAY. `Vaultify/Features/Tutorial/TutorialHost.swift` L26-65: `overlayPreferenceValue(TutorialAnchorKey.self)` draws `TutorialSpotlightOverlay` over the unlocked app; attached at `RootView.swift:49` (root) and inside specific sheets for sheet-hosted flows (L33 of TutorialFlow).
- Master gate: `VaultifyCore/Tutorial/TutorialFeature.swift:10-12` `static let enabled = true`.
- Test isolation: `AppEnvironment.swift:208-218` marks every flow `.skipped` under isolation unless launch arg `-ui-test-tutorials` (L123-135) — full-screen scrims break unrelated UI tests otherwise. A story screen has the SAME hazard.

## 4. The seam — where the story intro goes

Timeline today: `OnboardingDoneStep.onFinish` sets flag → RootView route flips `.onboarding → .unlocked` (0.35 s crossfade) → HomeScreen mounts → `.task` asks for `.firstRun` → 1200 ms settle → spotlight tour.

Recommended insertion: **RootView's unlocked branch** (`Vaultify/App/RootView.swift:44-50`). Render `StoryIntroView` INSTEAD OF `AdaptiveRootView` while the story is unseen:

```swift
case .unlocked:
    if !env.settings.storyIntroCompleted {
        StoryIntroScreen { env.settings.storyIntroCompleted = true }  // or a .story Route case
    } else {
        AdaptiveRootView().tutorialHost(env.tutorial)
    }
```

Why instead-of, not overlay/fullScreenCover:
- If the story merely covers Home, `HomeScreen`'s `.task` (HomeScreen.swift:238) still fires → the firstRun tour begins BEHIND the story after 1200 ms, burns its `tutorial_step_shown` analytics, and `onDisappear` doesn't fire under a cover. Not mounting Home defers everything.
- Handoff to tutorial is then automatic and zero-code: flag flips → `AdaptiveRootView` mounts → Home `.task` → `startIfNeeded(.firstRun)` → settle delay → tour. No TutorialCoordinator changes needed.
- Adding an explicit `Route.story` case (RootView L19-24, condition: `session unlocked && !storyIntroCompleted`) is equivalent and gets the existing route crossfade (L69); either shape works — the decision owner is RootView + SettingsStore either way.

Lock interplay: route stays `.locked` when session locks, so a story abandoned mid-way (background + immediate auto-lock) simply replays on next unlock until the flag is set. Set the flag on BOTH finish and skip.

New flag (follow SettingsStore conventions, SettingsStore.swift L65 + L313-337):
- `var storyIntroCompleted: Bool { didSet { defaults.set(storyIntroCompleted, forKey: Key.storyIntro) } }`
- `static let storyIntro = "story_intro_completed"` in `Key`.
- Init read alongside `onboardingCompleted` (~L233-237).
- MUST default to `true` in the test-isolation DEBUG block (`AppEnvironment.swift:166-180`, next to `onboardingCompleted = true` L177) or every UI test hits a non-hittable full-screen story. Mirror the `-ui-test-tutorials` opt-in pattern (L123-135) if tests will drive the story.
- Alternative rejected: a `TutorialStore` pseudo-flow (`tutorial_state_story-intro`) — the story is not a spotlight flow and the route decision lives in RootView which already reads `env.settings`; also `TutorialFeature.enabled=false` would silently kill the story.
- Decide: should `VaultSession+Recovery.swift:93` (onboarding reset) also reset the story flag so a re-onboarded vault replays it.

## 5. Patterns to reuse (build + animation)

- Step scaffold: `OnboardingScrollingStep` (`Vaultify/Features/Onboarding/OnboardingStepHeader.swift:49-65`) — GeometryReader + ScrollView with `minHeight`, survives Dynamic Type/SE.
- Titles: `OnboardingStepHeader` (same file L7-42), `.hero`/`.compact`.
- Pinned CTA: `BrandCapsuleCTA` (`Vaultify/DesignSystem/Components/BrandCapsuleCTA.swift:11`) via `.safeAreaInset(edge: .bottom)` (see OnboardingFlow.swift:242-247).
- Multi-beat progression: `@State step` + ZStack switch + `.animation(.vault(.smooth(duration:0.35), reduceMotion:), value: step)` (OnboardingFlow.swift:36-104). Reduce Motion collapses via `.vault(_:reduceMotion:)`.
- Brand animation: `LooxCloudAnimationView(controller:)` + `LooxLaunchController` (`Vaultify/Features/Onboarding/BrandAnimation/LooxLaunchController.swift`, phases idle/launching/presented, `press()` = freeze loop → squeeze → circle-burst flood + haptics). Done-step choreography to copy: OnboardingFlow.swift:252-263. `floodDiameter` for full-screen bloom: WelcomeLandingView.swift:62-63.
- Backgrounds: `Color.platformBackground` flood hand-off (OnboardingFlow.swift:226, WelcomeLandingView.swift:52); `.themedWallpaper(...)` canvas OnboardingFlow.swift:134.
- Design contract: tokens only (Space/Radius/Metric/Motion, `.vaultType`), no "!", "—", "·" in copy, EN+VI+JA in `Localizable.xcstrings`, `appString()` runtime / `.inAppLocalized` titles (CLAUDE.md).

## 6. Analytics

- Catalog rules: `Vaultify/Analytics/AnalyticsEvents.swift:1-11` — names only from typed factories, past-tense snake_case, every factory represented in `auditSamples` (L139-144, test-enforced by `AnalyticsEventTests`/`AnalyticsPolicy`). No user content in params.
- Existing first-run events (same file): `tutorialBegin`="tutorial_begin" L26 (logged OnboardingFlow.swift:135 onAppear), `tutorialComplete` L27 (logged at done, OnboardingFlow.swift:99), `vaultCreated` L40 (OnboardingFlow.swift:158), `vaultRestored(method:)` L42 (JoinVaultFlow.swift:149), tour events `tutorialStepShown(flow:step:)` L32 + `tutorialFlowEnded(flow:outcome:)` L36 (TutorialCoordinator.swift:119,127).
- Story would add e.g. `storyIntroEnded(outcome: "completed"|"skipped")` (+ optional step event with fixed ids) + `auditSamples` entries, and `.analyticsScreen("story_intro")` (pattern: HomeScreen.swift:240).

## Unresolved questions

1. Should the story show after the RESTORE path (JoinVaultFlow) too, or only after fresh vault creation? Restore skips theme/done steps today; a returning user on a new device may not want the story. If create-only: set `storyIntroCompleted = true` inside `JoinVaultFlow.finish()` (L148-151).
2. Should `VaultSession+Recovery` reset (onboardingCompleted=false, VaultSession+Recovery.swift:93) also clear the story flag (replay on re-onboarding)?
3. Should "Show tutorials again" in Settings (TutorialStore.resetAll, TutorialStore.swift:49) also replay the story, or does the story stay strictly once-ever?
4. Story on iPad sidebar layout + macOS (`MacRootView`) — same full-screen treatment, or iPhone-only initially? Seam at RootView covers all platforms uniformly.
5. Should the story get its own feature kill-switch like `TutorialFeature.enabled` / `WallpaperFeature.decorativeEnabled` (release-train decoupling convention)?
6. Continuity choice: launch the story DURING the done-step flood (replace `onFinish` destination) vs. after the standard 0.35 s route crossfade. Current recommendation: keep OnboardingDoneStep untouched; story is first frame of `.unlocked`.
