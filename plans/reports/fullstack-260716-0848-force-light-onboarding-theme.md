# Force-light onboarding theme — fix report

## Root cause (verified)

Both bugs trace to `ThemeStore` (`Vaultify/DesignSystem/Theme/ThemeStore.swift`, not
`VaultifyCore` — the task's read-first pointer was a reasonable guess but the class lives in
the app target). There was no notion of "we're pre-onboarding, force light" anywhere:

- **Active palette**: `active` is resolved by `ThemePalette.resolve(settings, systemIsDark:,
  brightness:)`. A fresh install's persisted `ThemeSettings` ends up with `autoNight = .system`
  (see below), so `active` follows the device from the very first launch.
- **`preferredColorScheme`**: returns `nil` (follow system) whenever `autoNight == .system`.
- **`systemColorSchemeChanged(_:)`**: called from `RootView.onChange(of: colorScheme)` /
  `.onAppear` on every scheme report (including background→foreground) and unconditionally
  writes into `systemIsDark`, which `recompute()` then feeds straight into `active` — no gate
  existed to say "ignore this while we haven't onboarded yet." That's bug 2.

A secondary finding, not part of the requested fix but worth recording: `ThemeSettings.init()`
already defaults fresh state to `autoNight = .off` (light) — a prior attempt at this exact
fix — but `ThemeReader.migrateIfNeeded()` (`VaultifyCore/Theme/ThemeReader.swift`) unconditionally
runs a "legacy migration" on first read. On a truly fresh install `UserDefaults.standard` has no
`appearance_mode` key, so it falls to `"system"` and `ThemeSettings.fromLegacyAppearance("system")`
sets `autoNight = .system` — silently overwriting that earlier default. That's bug 1's proximate
cause. I did **not** touch `ThemeReader`/`ThemeSettings` (shared with the AutoFill extension,
higher blast radius) — the new `forceLight` gate makes this migration behavior irrelevant during
the onboarding window, since it overrides `active`/`preferredColorScheme`/`interfaceStyle`
regardless of what `ThemeSettings` resolves to. Flagging it here in case it's worth a separate,
narrower fix later (it would still affect a joining/restoring user's *post-onboarding* appearance
today).

**Carousel confirmed themed, not a system-scheme read**: `WelcomeLandingView.swift`'s
`CapabilitySlide` uses `VaultColors.surface`/`.fill` (→ `ThemeHolder.current`, written only by
`ThemeStore`) for surfaces, and plain `Text` (`.primary`/`.secondary`) for labels — no
`@Environment(\.colorScheme)` read anywhere in the onboarding feature files (grepped). The
`.primary`/`.secondary`/`Color(.systemBackground)` reads are native SwiftUI/UIKit adaptive
colors, which is exactly why forcing `preferredColorScheme`/`interfaceStyle` (not just `active`)
matters — it's what makes those resolve light too. No fix needed there.

## Fix design

Centralized in `ThemeStore` as a new `forceLight: Bool` (private(set)):

- `forceLight` starts `true` unless `SettingsStore.hasChosenAppearance` is already `true`.
- While `true`: `active` resolves to `BuiltinThemes.day` directly (bypassing
  `ThemePalette.resolve` entirely, not just biasing its inputs — robust against any persisted
  `ThemeSettings` state), `preferredColorScheme` returns `.light`, `interfaceStyle` returns
  `.light` (fixes a sheet presented during onboarding, e.g. `RestoreMethodSheet`, that the task's
  three-item list didn't call out but shares the identical `settings.autoNight` switch), and the
  legacy `appearanceMode` bridge getter reports `.light` (so `ChooseThemeView`'s picker
  highlights what's actually on screen).
- `systemColorSchemeChanged(_:)` still records the true device scheme into `systemIsDark`
  unconditionally (comment updated to explain why that's safe) — `recompute()` is the single
  funnel that short-circuits to light while forced, so a background→foreground scheme report can
  never leak through. This is the direct fix for bug 2.
- `markAppearanceChosen()` releases the gate (one-way latch) and re-resolves immediately.

`SettingsStore.hasChosenAppearance` (new, persisted like `onboardingCompleted`) is the
source of truth for "should the gate re-arm on next launch": at init, if the key was never
written, it falls back to `onboardingCompleted` — an already-onboarded install (upgrading to
this build) always has `onboardingCompleted == true` already, so it back-fills to "already
chosen" and is never forced. A genuinely fresh install has `onboardingCompleted == false` too,
so it correctly defaults to "not chosen."

`AppEnvironment.markAppearanceChosen()` is a tiny composition-root helper that keeps the two
stores in lockstep (`theme.markAppearanceChosen()` + `settings.hasChosenAppearance = true`), so
every release call site does one call instead of remembering both. Three call sites:

1. `OnboardingFlow.swift` — `ChooseThemeView`'s binding setter (live: tapping Dark goes dark on
   that screen immediately).
2. `OnboardingFlow.swift` — the `.theme` step's `onContinue`, which **first re-assigns
   `env.theme.appearanceMode = env.theme.appearanceMode`** before releasing. This closes a gap I
   found while tracing the design: if the user never taps a card and just continues, nothing had
   committed "Light" into `settings` — releasing the gate at that point would fall through to
   whatever `ThemeSettings` naturally resolves to (`.system` per the migration bug above), which
   on a dark device would flip the app dark the instant onboarding finishes. Re-assigning the
   getter's current value (`.light`, while still forced) to itself commits it first; it's a
   no-op if the user already picked something.
3. `RootView.swift` — `.onChange(of: env.settings.onboardingCompleted)` releases the gate the
   moment onboarding completes via any path. This is the only thing that unblocks
   `JoinVaultFlow` (restore), which sets `onboardingCompleted = true` directly and never visits
   `ChooseThemeView` — restoring a vault has no "currently shown" appearance to preserve, so it
   intentionally just falls through to the device's/local install's normal resolution once
   restore completes (not forced to Light) — this is existing app behavior for that path, not a
   new flip.

Minor supporting change: `PlatformAppearance.Style` gained `Equatable` (was a bare `case
light, dark, unspecified` enum with no comparison anywhere) so `interfaceStyle` is assertable in
tests. Purely additive, zero behavior change.

## Files changed

- `Vaultify/DesignSystem/Theme/ThemeStore.swift` — `forceLight` property, `init(forceLight:)`,
  `markAppearanceChosen()`, gating added to `preferredColorScheme`/`interfaceStyle`/
  `recompute()`/`appearanceMode` getter.
- `Vaultify/App/SettingsStore.swift` — `hasChosenAppearance` property + persistence key +
  back-compat init fallback.
- `Vaultify/App/AppEnvironment.swift` — wires `forceLight:` into `ThemeStore.init`, adds
  `markAppearanceChosen()` helper.
- `Vaultify/Features/Onboarding/OnboardingFlow.swift` — `ChooseThemeView` binding + `onContinue`
  release the gate (see design above).
- `Vaultify/App/RootView.swift` — safety-net release on `onboardingCompleted` becoming true.
- `Vaultify/Platform/PlatformAppearance.swift` — `Style: Equatable` (test support).
- `VaultifyTests/ThemeEngineTests.swift` — `@MainActor` on the class (needed to construct
  `ThemeStore`/`SettingsStore`), a `tearDown()` resetting `ThemeReader`'s persisted settings, and
  5 new tests.

## Scenario walkthrough

**(a) Fresh install, device dark → app light.** `SettingsStore.init()`: `onboardingCompleted =
false`, `hasChosenAppearance` falls back to `false` (key absent). `AppEnvironment` constructs
`ThemeStore(forceLight: true)` → `active = BuiltinThemes.day` unconditionally (ignores whatever
`ThemeReader.load()` / the device trait say). `preferredColorScheme`/`interfaceStyle` both
`.light`, so `RootView.onAppear`'s `applyInterfaceStyle()` forces every window
`overrideUserInterfaceStyle = .light` too — covers splash, welcome, carousel, and any native
system chrome (alerts, the restore sheet).

**(b) Background→foreground during welcome → stays light.** Whatever triggers a reported scheme
change, `systemColorSchemeChanged` only ever updates `systemIsDark`; `recompute()` (the sole
place `active` is assigned outside `init`) checks `forceLight` first and keeps returning
`BuiltinThemes.day`. Covered by `testForceLightIgnoresSystemColorSchemeChanges`, which
constructs a forced store, calls `systemColorSchemeChanged(.dark)`, and asserts the palette
stayed light — a direct regression test for this exact bug.

**(c) ChooseTheme → pick Dark → live dark, relaunch → dark persists.** Tapping Dark: the binding
setter sets `settings.theme = .builtin(.night)` / `autoNight = .off`, then
`markAppearanceChosen()` releases the gate and re-resolves — `active` becomes dark in the same
synchronous call (no interim frame renders the stale forced state, so no flicker). `hasChosenAppearance`
persists `true` via `SettingsStore`'s existing `didSet` pattern. On relaunch, `hasChosenAppearance`
reads back `true` directly (not via the fallback) → `ThemeStore(forceLight: false)` → resolves
via the untouched `ThemePalette.resolve` path with the persisted dark settings. Covered by
`testMarkAppearanceChosenAppliesPendingChoiceAndReleasesGate`.

**(d) Existing onboarded user with System/Dark → unchanged.** `onboardingCompleted` is already
`true` (persisted before this update), so `hasChosenAppearance`'s fallback resolves to `true` at
first read → `ThemeStore(forceLight: false)`. Every gated property (`preferredColorScheme`,
`interfaceStyle`, `recompute()`, `appearanceMode` getter) short-circuits only when `forceLight`
is true, so with it permanently `false` for this user the code takes exactly the same branches
as before my change — byte-identical behavior, including continuing to follow the device on
`.system`. Covered by `testThemeStoreNotForcedRespectsAppearanceModeImmediately` (constructs
`ThemeStore(forceLight: false)`, sets `.dark` then `.system`, asserts both resolve normally) and
`testHasChosenAppearanceBackCompatDefaultsToOnboardingCompleted` (seeds `UserDefaults` to mimic
a pre-existing onboarded install with the new key absent, asserts `hasChosenAppearance == true`).

## Tests

Added to `VaultifyTests/ThemeEngineTests.swift` (5 new, all passing; class now `@MainActor` to
construct `ThemeStore`/`SettingsStore`, with a `tearDown()` resetting `ThemeReader`'s persisted
`ThemeSettings` so these tests can't leak state into others):

- `testForceLightPinsLightRegardlessOfSettings`
- `testForceLightIgnoresSystemColorSchemeChanges` (bug-2 regression test)
- `testMarkAppearanceChosenAppliesPendingChoiceAndReleasesGate`
- `testThemeStoreNotForcedRespectsAppearanceModeImmediately`
- `testHasChosenAppearanceBackCompatDefaultsToOnboardingCompleted`

`ThemeStore` is fully unit-testable via its real `init(forceLight:)` — no refactor needed, so
the plan's "stop and report" fallback didn't apply. The OnboardingFlow/RootView wiring (the
three release call sites) is SwiftUI view glue with no existing view-level test harness in this
repo (`ThemeEngineTests` deliberately tests the model/logic layer only) — verified by code
reading + the manual scenario walkthrough above instead.

## Compile

App + `VaultifyAutoFill` + `VaultifySafari` (all three targets embed in the `Vaultify` scheme):

```
$ tuist generate --no-open
✔ Success — Project generated.

$ xcodebuild -workspace Vaultify.xcworkspace -scheme Vaultify -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/vaultify-dd \
    CODE_SIGNING_ALLOWED=NO
...
** BUILD SUCCEEDED **
```

Zero errors, zero warnings in any touched file (checked explicitly). One caught-and-fixed issue
along the way: `SettingsStore.init()` reading `onboardingCompleted` back through its own
`@Observable`-generated accessor to compute `hasChosenAppearance`'s fallback failed with
`variable 'self._hasChosenAppearance' used before being initialized` — `@Observable` accessors
touch `self` as a whole (definite-initialization requires every stored property to have its
first value before that), unlike a plain stored-property read. Fixed by capturing the raw
`UserDefaults` read into a local (`let onboarded = ...`) and using that for both assignments
instead of reading back `self.onboardingCompleted`.

Test run (`ThemeEngineTests`, iPhone 16 simulator): 28/28 pass, including the 5 new ones.
Full suite: 779 tests, 778 pass / 1 pre-existing failure —
`SpaceShareMembershipReconcilerTests.testPlanUpdatesWhenCapabilitySetShrinksBecauseAFieldBecameProtected`
— confirmed via `git diff` that I never touched that file or anything it depends on; matches the
task's note about unrelated in-progress Family-sharing work already in the tree. Not fixed, per
instructions.

## Unresolved / out of scope

- The `ThemeReader.migrateIfNeeded()` legacy-migration bug (see Root cause) still means a
  restoring/joining user's *post-onboarding* appearance on a fresh device falls back to
  "follow system" rather than the intended "light, no auto-night" default. It's masked during
  onboarding by `forceLight` and isn't part of either reported bug, so I left it — flagging in
  case a future fix is wanted (would touch `VaultifyCore/Theme/ThemeReader.swift`, shared with
  the AutoFill extension).

Status: DONE
Summary: Centralized a `forceLight` gate in `ThemeStore`, released by an explicit `SettingsStore.hasChosenAppearance` flag (back-compat via `onboardingCompleted`), pinning active palette/preferredColorScheme/interfaceStyle to light until the user picks or onboarding completes by any path.
Files changed: Vaultify/DesignSystem/Theme/ThemeStore.swift, Vaultify/App/SettingsStore.swift, Vaultify/App/AppEnvironment.swift, Vaultify/Features/Onboarding/OnboardingFlow.swift, Vaultify/App/RootView.swift, Vaultify/Platform/PlatformAppearance.swift, VaultifyTests/ThemeEngineTests.swift
Compile: PASS (app + VaultifyAutoFill + VaultifySafari, 0 errors/warnings in touched files)
Concerns: One pre-existing, unrelated test failure in the tree (SpaceShareMembershipReconcilerTests) — not touched, not caused by this change. `ThemeReader` migration bug noted but intentionally left out of scope (see Unresolved).
