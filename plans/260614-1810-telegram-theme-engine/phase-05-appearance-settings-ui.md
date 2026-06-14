# Phase 05 — Appearance Settings UI (maximum)

**Priority:** P1 · **Status:** ☐ todo · **Depends:** 01-04

The user-facing control center: live preview + theme/accent/wallpaper/auto-night/
text-size/reduce-motion. Replaces the small Settings → Appearance section. Upgrade the
onboarding theme step. Full EN+VI localization.

## Key insights

- Telegram's `ThemeSettingsController` is one screen with: live preview, theme carousel,
  accent picker (presets + custom), brightness/auto-night, text size, reduce motion.
  We mirror that minus chat preview → use a **vault** preview card.
- Everything edits `ThemeStore` (Phase 01) and renders live (Observable).

## Requirements

- `AppearanceSettingsView` hub: live `ThemePreviewCard` (mini vault list over current
  wallpaper) + sections (Theme, Accent, Wallpaper, Auto-Night, Text size, Reduce motion).
- `ThemePickerView` (built-in carousel; custom themes appear here in Phase 06).
- `AccentColorEditorView` (preset swatches + custom `ColorPicker`).
- `WallpaperGalleryView`: preset grid + "Choose photo" (`PhotosPicker`) + "Color"
  (`WallpaperColorEditorView` for solid/gradient/mesh palette + blur/dim/intensity).
- `AutoNightSettingsView`: off / system / time-based (from–to) / brightness (slider).
- `TextSizeSettingsView`: `FontScale` slider feeding a global Dynamic-Type-like scale.
- Reduce-Motion toggle (also disables mesh animation).
- Onboarding `.theme` step → preview real themes + a "surprise me" wallpaper.

## Architecture

```
Features/Settings/Appearance/
  AppearanceSettingsView.swift   // hub, sections, live preview
  ThemePreviewCard.swift         // mock vault rows over WallpaperView
  ThemePickerView.swift
  AccentColorEditorView.swift
  WallpaperGalleryView.swift     // presets + PhotosPicker + Color editor entry
  WallpaperColorEditorView.swift // solid/gradient/mesh + blur/dim/intensity sliders
  AutoNightSettingsView.swift
  TextSizeSettingsView.swift
```

`FontScale` applied app-wide via `.environment(\.dynamicTypeSize, …)` or a custom
scale on `Font` tokens (decide in impl; prefer `dynamicTypeSize` clamp + multiplier).

## Related code files

**Create**: the eight files above.
**Modify**: `SettingsScreen.swift` (Appearance section → `NavigationLink` to
`AppearanceSettingsView`; drop old `appearance` picker), `ChooseThemeView.swift`
(richer onboarding preview), `OnboardingFlow.swift` (bind to `ThemeStore`),
`Localizable.xcstrings` (EN+VI for all new strings).

## Implementation steps

1. `AppearanceSettingsView` shell + `ThemePreviewCard`.
2. `ThemePickerView` + `AccentColorEditorView` (live edits to `ThemeStore`).
3. `WallpaperGalleryView` (+ `PhotosPicker`, no Photos permission) +
   `WallpaperColorEditorView`.
4. `AutoNightSettingsView` (wire `AutoNight` resolution → `ThemeStore`).
5. `TextSizeSettingsView` + global scale application; Reduce-Motion toggle.
6. Rework onboarding theme step; localize EN+VI; `make check`.

## Todo

- [ ] Appearance hub + live preview card
- [ ] Theme picker + accent editor
- [ ] Wallpaper gallery + PhotosPicker + color/mesh editor
- [ ] Auto-night settings (system/time/brightness)
- [ ] Text size + reduce motion
- [ ] Onboarding theme step upgrade
- [ ] EN+VI strings for everything
- [ ] `make check` green

## Success criteria

- From Settings, a user picks theme + accent + wallpaper (preset / photo / custom
  gradient / mesh palette) + auto-night + text size, sees it live, and it persists.
  Onboarding lets them pick a look. All strings EN+VI (no missing VI).

## Risks

- Scope creep in editors — keep sliders minimal (blur, dim, intensity, rotation).
- `PhotosPicker` returns large images → downscale before storing.
- Text-size scaling interacting with `AmountTextStyle`/mono fields — verify no clipping.

## Security

- `PhotosPicker` (PHPicker) needs no Photos permission. Downscale + strip metadata on
  import. Store under file protection (Phase 03 storage).

## Next

→ Phase 06 adds custom theme creation + `.vaultheme` import/export.
