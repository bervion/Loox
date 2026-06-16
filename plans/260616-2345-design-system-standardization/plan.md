# Vaultify — Design System Standardization

Standardize the whole app against the new **`Design System/`** spec (web source of truth:
tokens + components + iOS UI kit), refactor for consistency, and update `CLAUDE.md` + docs so
future sessions auto-comply.

## Source of truth
- New DS: `Design System/` (readme.md, `tokens/*.css`, `components/core/*`, `ui_kits/ios-app/*`)
- App doc: `docs/design-guidelines.md` (already describes target + migration plan)

## Confirmed decisions (user, 2026-06-16)
1. **Scope:** full refactor now (foundation → tab bar → screens → localization → docs).
2. **Tab bar:** custom **icon-only floating** bar (DS-exact): floating pill, Liquid Glass + solid
   fallback, no text labels, sliding indicator, haptics, VoiceOver. (was native `TabView` w/ labels)
3. **Accents:** keep current **10 presets + custom** (superset of DS's 6); ensure all WCAG-correct.
   Do NOT remove user options.
4. **Typography:** map DS roles → **Apple system Dynamic Type** styles (keep accessibility), not fixed px.

## Current state (audit summary)
- ✅ Semantic colors via `.themedForeground(role)` / `theme.color(role)` (~99% adoption), live theme
  switching no-restart, `onAccent` WCAG-derived. SF Symbols fully eliminated (PolarisIcon everywhere).
  Raw `Color(hex:)` gone from features.
- ❌ No spacing/radius/elevation/motion/type **token scales** (hardcoded: 33× `cornerRadius`, 17× `.padding(n)`).
- ❌ `AppTheme` missing tokens: surfaceFloating/floatingSolid/pressed, accentSoft/press, separatorOpaque,
  textDisabled, icon roles, status `*-soft`, onDestructive.
- ❌ Tab bar still native + labels. ❌ Localization: ~40–50% `Text("…")` hardcoded (SettingsScreen, AboutView worst).

## Phases
- **P1 — Foundation tokens** (`phase-01`): Spacing/Radius/Elevation/Motion/Metrics + VaultType + computed
  color tokens on `AppTheme` + extend `ThemeRole`. Critical path; build-verify. → me, serial.
- **P2 — Custom floating tab bar** (`phase-02`): VaultTabItem/TabBar/TabButton/Background + MainTabView host. → me, serial.
- **P3 — Screen migration** (`phase-03`): replace hardcoded radius/padding/font with tokens across ~60 screens. → parallel agents by folder.
- **P4 — Localization** (`phase-04`): extract hardcoded strings → `Localizable.xcstrings` (EN+VI). → agent.
- **P5 — Docs + QA** (`phase-05`): update `CLAUDE.md`, `docs/design-guidelines.md`, `docs/codebase-summary.md`,
  `docs/code-standards.md`; final `make check`. → me.

## Build / verify
`tuist generate --no-open` after adding files, then the `xcodebuild` workspace compile (see CLAUDE.md
"Build & run") or `make check`. Never put "build" in paths/log names (hook block).

## Acceptance
- All new UI metrics come from token enums (no magic radii/padding in new/changed code).
- Tab bar: icon-only, floating, glass+solid fallback, state preserved, VoiceOver labels, 44pt targets.
- 10 accents + custom all pass WCAG onAccent. Light/dark/contrast/reduce-transparency/reduce-motion safe.
- `make check` passes (app + extension). Docs + CLAUDE.md teach the token system.

## Status
- [x] P1 Foundation tokens — Space/Radius/Metric/Elevation/Motion + VaultType + AppTheme computed
  tokens + extended ThemeRole. BUILD SUCCEEDED (app+ext).
- [x] P2 Custom floating tab bar — VaultTab + VaultTabBar (sliding accent pill, matchedGeometry,
  haptics, VoiceOver, material+solid fallback) + MainTabView host (hidden native bar, per-tab bottom
  inset). BUILD SUCCEEDED. **Refined (user request): icon-only on EVERY OS** (no system labels) —
  `VaultTabBarBackground` uses real `glassEffect(.regular.interactive())` on iOS 26+ (guarded by
  `#if compiler(>=6.2)` + `#available(iOS 26, *)`, with `.regularMaterial`/solid fallback so a pre-Xcode-26
  CI runner still compiles); tab icons bumped to 29pt. Rebuilt: BUILD SUCCEEDED.
- [x] P3 Screen migration — shared button → Radius.sm; 3 parallel agents migrated ~36 feature files
  (~85 exact-match token swaps: padding→Space, radius→Radius, icon→Metric, font→VaultType). 4 non-lossless
  radius maps corrected (12→md, 16→lg). Non-exact values left as literals (documented per agent reports).
- [x] P4 Localization — catalog audited: 390 keys, only "My Theme" lacked VI (added "Chủ đề của tôi").
  New session strings (tab labels, "Copied %@") already have VI. (Earlier "40–50% hardcoded" claim was a
  false alarm — `Text("…")` literals auto-extract and already carry VI.)
- [x] P5 Docs — CLAUDE.md (Design System section), design-guidelines.md (Swift Token API + tab bar
  implemented + resolved decisions), codebase-summary.md updated.

## Verification (2026-06-17)
- `xcodebuild` app + embedded extension: **BUILD SUCCEEDED**.
- `make test` (iPhone 16 sim): **TEST SUCCEEDED** (ThemeEngine/NavRedesign/Codec/Backup/Repo suites).
- WCAG: all 10 accents + night-default pass AA-text (≥4.5:1) for the derived `onAccent` (min orange 4.73:1).
- Branch note: changes are **uncommitted** in the working tree; branch is currently `main` (session began on
  `fix/theme-consistency-and-app-icon`). Commit/branch decision left to the user.

## Remaining (handoff)
- Manual on-device visual QA: light/dark/tinted, Reduce Transparency, Reduce Motion, increased contrast;
  tab bar look + sliding pill + haptics; no content hidden behind the floating bar.
- Optional: wire a Watchtower tab badge (bar already supports `badges`).
- Liquid Glass resolved via dual-path (native bar on iOS 26+). Only adopt `glassEffect` on the custom
  fallback if the CI runner's Xcode SDK is confirmed ≥ 26.
- Verify on an **iOS 26 device/sim** that the native glass bar looks/behaves right (labels + glass + press);
  verify the custom fallback on an iOS 17–25 sim.
