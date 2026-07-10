# Phase 9 — Appearance + About

**Status**: done · **Wave**: W2 · **Owns**: `Settings/Appearance/*`, `Settings/AboutView.swift`, `DesignSystem/Wallpaper/*` (engine is flag-gated OFF — review-light: only verify nothing leaks into current UI) (6+ surfaces).
Method = canonical protocol + 6 greps (`phase-01`).

## Protagonist
Appearance = "make it look the way I want, live". About = "understand and trust the app".

## Cluster hotspots
- **AppearanceSettingsView**: 2 theme cards (Day/Night mini-preview vault, check on select) + 7-accent swatch
  grid (ring on select, apply instantly, all pass WCAG `onAccent`) + Text Size picker + Reduce Motion toggle +
  → Automatic Dark Mode. This screen is the THEME-SWITCH crucible — verify NO invisible-after-switch text/icon
  in any preview; swatches are the ALLOWED raw-color exemption (literal light/dark preview), everything else
  semantic. Wallpaper picker is gated OFF (`WallpaperFeature.decorativeEnabled=false`) — confirm it stays
  hidden; do not resurface it.
- **WallpaperGalleryView / ThemeEditorView**: currently gated/retained code — verify they are NOT reachable in
  the simplified UI; if reachable, that's a finding. Do not delete the engine (flag-gated for future).
- **AutoNightSettingsView**: Off/System/Scheduled/Brightness rows (check); Scheduled → 2 DatePickers
  (22:00–07:00 default); Brightness → % slider (40% default); Night-theme picker when mode≠off. Pickers reflow
  at SE + Dynamic Type XL; labels EN+VI.
- **AboutView**: logo + version + 4 "How your data is protected" lines + privacy link. Copy calm/honest, no
  `!`; version string localized; links reachable; renders SE↔Pro Max.
- Accent swatch grid: 7 swatches must reflow (not squeeze) at SE and Dynamic Type — 4-per-row → fewer rows.

## Deliverables / Todo
`reports/phase-09-findings.md` · `strings-manifest-phase-09.md` · fixes.
- [x] Protocol answers (5, per adversarial protocol). [x] 6 greps (swatch exemption noted). [x] Theme-switch invisible-content audit
  across BOTH theme cards × 7 accents × light/dark. [x] Confirm wallpaper/custom-theme stay gated. [x] Fixes + manifest.

## Success / Risk
Success: audit-grep clean (preview swatches exempt); zero invisible content after any theme/accent switch;
gated surfaces stay hidden; EN+VI. Risk: this is exactly where "wrong colors after theme switch" bugs live
(High×High) — this phase MUST eyeball all theme×accent combinations, not just default.
</content>
