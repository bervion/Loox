# Design System Standardization — Completion Report

Date: 2026-06-17 · Plan: `plans/260616-2345-design-system-standardization/`

App standardized against the new `Design System/` spec (tokens + components + iOS UI kit). Token-driven
foundation, custom floating tab bar, ~36 screens migrated, docs + CLAUDE.md updated so future sessions comply.

## Shipped

**P1 Foundation tokens** (new `Vaultify/DesignSystem/Tokens/`):
- `Spacing.swift` (`Space.s1…s10`, gutter, contentMax), `Radius.swift` (`Radius.xs…pill` + `.vaultCornerRadius`),
  `Metrics.swift` (`Metric.*` + `TabBarMetric.*`), `Elevation.swift` (`.elevation(.level1…sheet)`), `Motion.swift`
  (`Motion.spring/standard/…` + `.vault(_,reduceMotion:)`).
- `Typography.swift` extended: `VaultType` roles → Apple Dynamic Type + `.vaultType(_)`.
- `VaultifyCore/Theme/AppTheme+Tokens.swift`: computed semantic tokens (surfaceFloatingSolid/surfacePressed/
  accentSoft/accentPress/icon*/textDisabled/*Soft/onDestructive/separatorOpaque) — derived, so every builtin +
  custom theme gets them with zero constructor changes.
- `ThemeRole` extended (icon roles, disabled, accentSoft, onDestructive) + `color(role)`.

**P2 Custom floating tab bar** (`Vaultify/Features/Main/`):
- `VaultTabItem` (enum: order, outline+filled Polaris icons, localized a11y label), `VaultTabBar` (icon-only,
  sliding `accentSoft` pill via `matchedGeometryEffect` + `Motion.spring`, `Haptics.selection()`, VoiceOver
  `.isSelected`, press scale), `VaultTabBarBackground` (`.regularMaterial` + solid Reduce-Transparency fallback,
  hairline, `.elevation(.level3)`). `MainTabView` hosts a `TabView` with the native bar hidden (per-tab state
  preserved) + reserved bottom inset. `Haptics.selection()` added.

**P3 Screen migration** — shared `ThemedButtonStyles` → `Radius.sm`; 3 parallel agents migrated ~36 feature
files (~85 exact-match swaps: padding→`Space`, radius→`Radius`, icon size→`Metric`, ad-hoc font→`VaultType`).
4 non-lossless radius maps corrected (12→`Radius.md`, 16→`Radius.lg`). Non-exact orphan values (e.g. 5/7/9/11/
14-radius, odd icon sizes) intentionally left as literals.

**P4 Localization** — catalog already healthy (390 keys); only `My Theme` lacked VI → added "Chủ đề của tôi".

**P5 Docs** — `CLAUDE.md` (new "Design System (READ before ANY UI work)" section), `docs/design-guidelines.md`
(Swift Token API table, tab bar marked implemented, resolved decisions), `docs/codebase-summary.md` (tree +
theming updated).

## Decisions applied (user, 2026-06-16)
1. Full refactor now. 2. Custom icon-only floating tab bar (DS-exact). 3. Keep 10 accents + custom (WCAG-verified).
4. Type scale → Apple Dynamic Type (`VaultType`).

## Verification
- `xcodebuild` (app + embedded AutoFill extension): **BUILD SUCCEEDED**.
- `make test` (iPhone 16 sim): **TEST SUCCEEDED** — ThemeEngine, NavRedesign, OrganizationCodec, BackupFolderTags,
  RepositoryFolder suites.
- WCAG: all 10 accents + night-default pass AA-text (≥4.5:1) for derived `onAccent` (min orange 4.73:1).

## Handoff / open items
- **Commit decision (user):** changes are **uncommitted**; branch is `main` (session started on
  `fix/theme-consistency-and-app-icon`). Recommend moving to a feature branch before commit.
- **Manual visual QA on device** (can't automate here): light/dark/tinted, Reduce Transparency, Reduce Motion,
  increased contrast; floating bar look + sliding pill + haptics; confirm no content hidden behind the bar; theme
  switch shows no invisible text/icons.
- **Optional code-review** pass over the diff (foundation + tab bar are the highest-value review targets).
- **Deferred (non-blocking):** Watchtower tab badge wiring (API ready); true `glassEffect` behind
  `#available(iOS 26)` once CI Xcode supports it (material fallback shipped); `ThemedCard` left at radius 16
  (app's established card radius; DS lg=20 not applied to avoid regressing existing demo screenshots).

## Unresolved questions
- Commit target: stay on `main` or move to a branch? (No commit made — awaiting your call.)
- Apply DS card radius (lg=20) to `ThemedCard` app-wide, or keep 16 to match current screenshots?
