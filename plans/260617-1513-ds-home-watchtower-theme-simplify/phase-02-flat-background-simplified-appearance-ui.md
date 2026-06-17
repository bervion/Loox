---
phase: 2
title: Flat background & simplified Appearance UI
status: completed
priority: P1
effort: 3-5h
dependencies:
  - 1
---

# Phase 2: Flat background & simplified Appearance UI

## Overview

Force **flat themed backgrounds** app-wide and strip the wallpaper/gradient/pattern surface from the
Appearance settings — "làm đơn giản như design, nâng cao telegram sau". The Telegram wallpaper/mesh/
pattern engine is **gated off (kept in code)**, re-enabled later by flipping one flag.

## Requirements

- Functional: every screen renders the theme's solid background (no gradient/pattern/mesh/photo);
  Appearance shows mode + accent (7) + builtin theme grid + auto-night + text size; no wallpaper UI,
  no custom RGB ColorPicker.
- Non-functional: engine files compile but are unreachable from UI; old persisted wallpaper settings
  load silently and render flat.

## Key Insights

- `Vaultify/DesignSystem/Wallpaper/WallpaperView.swift` is the **single renderer** — one guard there
  flattens the whole app. Hosts: Home, Items, Watchtower, Search, Lock, Onboarding.
- Accent ColorPicker + custom-RGB writes live at `AppearanceSettingsView.swift:143-145,169` and
  `ThemeEditorView.swift:103` — remove the picker; iterate the 7 `AccentPreset.allCases` (now 7).
- Custom-theme editor's main value (wallpaper + custom RGB) is removed → **hide the editor + import/export** (Session 1).

## Architecture

Single feature gate `WallpaperFeature.decorativeEnabled = false` (new, in `VaultifyCore/Theme/`).
`WallpaperView` returns the themed fallback for all non-`.solid`/`.none` kinds when disabled.
Settings hide the wallpaper entry behind the same flag.

## Related Code Files

- Create: `VaultifyCore/Theme/WallpaperFeature.swift` — `enum WallpaperFeature { static let decorativeEnabled = false }`.
- Modify: `Vaultify/DesignSystem/Wallpaper/WallpaperView.swift` — when disabled, render `fallbackColor` for `.gradient/.mesh/.pattern/.image` (keep `.solid`/`.none`).
- Modify: `Vaultify/Features/Settings/Appearance/AppearanceSettingsView.swift` — remove `backgroundSection` (wallpaper nav) + the accent `ColorPicker`; keep theme grid, accent swatches (7), auto-night, text size.
- Modify: `Vaultify/Features/Settings/Appearance/AppearanceSettingsView.swift` — also remove the `customThemesSection` ("Create Theme" / "Import Theme"). `ThemeEditorView.swift` becomes unreachable (file kept, not deleted).
- Read/verify: `WallpaperGalleryView.swift` (no longer reachable — leave file, drop nav), all WallpaperView host screens still show themed bg.

## Validation Session 1 updates
<!-- Updated: Validation Session 1 - hide custom theme editor + import/export -->

- **Hide the custom theme editor + `.vaultheme` import/export** (keep code). Remove the
  `customThemesSection` ("Create Theme" / "Import Theme") from `AppearanceSettingsView`; the
  `ThemeEditorView` entry is no longer reachable (file kept). Resolves prior Open Q1.
- Builtin grid is now **Day + Night** only (see Phase 1) — the theme section shows 2 cards.

## Implementation Steps

1. Add `WallpaperFeature.decorativeEnabled` flag.
2. Guard `WallpaperView` body: if `!decorativeEnabled`, map any decorative kind → `fallbackColor`
   (themed solid). Keep mesh-phase env reads harmless.
3. `AppearanceSettingsView`: delete `backgroundSection` + its nav link; delete the accent `ColorPicker`
   row; ensure accent grid iterates the 7 presets and the selection check no longer references
   `customRGB`.
4. Hide the custom-theme editor entirely: remove the `customThemesSection` (Create/Import) from
   `AppearanceSettingsView`; leave `ThemeEditorView.swift` in the repo but unreferenced (Telegram-later).
5. Confirm `ChooseThemeView` (onboarding) already mode-only → no change needed; verify it shows flat bg.
6. `tuist generate --no-open` → compile workspace. Manually confirm Home/Lock render flat themed bg.

## Todo List

- [ ] WallpaperFeature flag added
- [ ] WallpaperView flattens decorative kinds when disabled
- [ ] AppearanceSettingsView: wallpaper section + ColorPicker removed; 7-accent grid
- [ ] ThemeEditorView: wallpaper grid + custom RGB removed
- [ ] All host screens verified flat (no gradient/pattern/mesh)
- [ ] `make check` passes

## Success Criteria

- [ ] No gradient/pattern/mesh/photo visible anywhere; backgrounds are flat themed surfaces.
- [ ] Appearance matches DS intent: mode + 7 accents + theme grid + auto-night + text size only.
- [ ] Re-enabling the flag later restores wallpaper UI without code rewrite (engine intact).

## Risk Assessment

- **Dead-code warnings** for now-unreachable wallpaper UI → acceptable; do not delete (Telegram-later).
- **Persisted decorative wallpaper** for a custom theme → renders flat via the guard; no migration.

## Security Considerations

None new.
