# Phase 03 — Wallpaper engine (static: solid / gradient / pattern / image)

**Priority:** P1 · **Status:** ☐ todo · **Depends:** 01, 02

The `Wallpaper` model + a SwiftUI renderer for everything except the animated mesh
(Phase 04). Place behind canvas + lock + onboarding; float content in cards/material.

## Key insights

- `TelegramWallpaper` cases we keep: solid `.color`, multi-stop `.gradient` (+rotation),
  `.pattern` (file tinted via softlight + `intensity`), `.image` (user photo, blur/dim).
  `WallpaperSettings`: blur, motion, colors, intensity, rotation, dim.
- Pattern = gradient/solid base + pattern bitmap drawn `.softLight`, alpha = intensity.
  SwiftUI `.blendMode(.softLight)` is native.
- Canvas screens use `List` with opaque bg → need `.scrollContentBackground(.hidden)`
  + translucent themed row cards so the wallpaper shows (Telegram "messages over bg").
- `MainTabView` tabs each own a `NavigationStack`; background must sit behind the
  `TabView` and each tab's scroll content must go clear.

## Requirements

- `Wallpaper` enum + `WallpaperSettings` (Codable; slots into `ThemeSettings.wallpapers`).
- `WallpaperView` renders solid / gradient(+rotation) / pattern(softlight+intensity) /
  image(blur+dim). Mesh case delegates to Phase 04 (stub → static gradient until then).
- `ThemedBackground` container: wallpaper + optional blur + dim overlay + safe-area.
- Apply behind `MainTabView`, `LockScreen`, `OnboardingFlow`; make those scroll views
  transparent and re-style vault rows as floating cards. Settings/detail/editor opt-out
  (solid themed bg).
- Bundle curated presets: ~6 gradients + ~6 patterns + each built-in theme's default
  wallpaper. Default for Day = subtle light gradient; Night = dark gradient/mesh.
- **AutoFill extension**: optional **static** themed backdrop (solid/gradient only — no
  pattern/photo/morph) behind its credential list; defaults to the themed solid
  background. Keep it light (extension memory budget).

## Architecture

```
Wallpaper (Codable): .solid(UInt32) | .gradient([UInt32], angle) |
                     .mesh([UInt32]) | .pattern(id, colors, intensity, base) |
                     .image(fileName, settings)
WallpaperView(wallpaper, settings) -> ZStack base + overlay(pattern/dim) + .blur
ThemedBackground { content }  // ZStack(WallpaperView, content)
PatternLibrary: [PatternPreset]  (asset name + thumbnail)  -> rendered via Canvas/Image
GradientPresets: [GradientPreset], [MeshPreset]
```

User photo: copied into App-Group `Wallpapers/` dir; `Wallpaper.image(fileName)`
references it; render with `.blur` + dim per settings.

## Related code files

**Create** (`Vaultify/DesignSystem/Wallpaper/`): `Wallpaper.swift`,
`WallpaperView.swift`, `ThemedBackground.swift`, `PatternLibrary.swift`,
`GradientPresets.swift`, `WallpaperStorage.swift` (App-Group image copy/load).
**Add assets**: pattern SVG/PNG imagesets under `Assets.xcassets/Wallpapers/`.
**Modify**: `MainTabView.swift`, `LockScreen.swift`, `OnboardingFlow.swift` (wrap in
`ThemedBackground`); vault list screens (`ItemsScreen.swift`, `HomeScreen.swift`,
`VaultItemRow*.swift`) for `.scrollContentBackground(.hidden)` + card rows.

## Implementation steps

1. `Wallpaper` + `WallpaperSettings` Codable; extend `ThemeStore` to resolve active
   wallpaper per theme; default presets per built-in theme.
2. `WallpaperView` (solid/gradient/pattern/image); `ThemedBackground` wrapper.
3. `WallpaperStorage` for user photos (copy on pick, load by name, delete on replace).
4. Integrate behind canvas/lock/onboarding; transparent scroll + floating card rows;
   tune card material/opacity for legibility over busy wallpapers (auto-dim scrim when
   wallpaper is "loud").
5. Bundle presets + pattern assets; `tuist generate`; `make check`; per-theme self-test.

## Todo

- [ ] `Wallpaper` model + store resolution + defaults
- [ ] `WallpaperView` (solid/gradient/pattern/image) + `ThemedBackground`
- [ ] `WallpaperStorage` (App-Group photo copy/load)
- [ ] Canvas/lock/onboarding integration + floating card rows + legibility scrim
- [ ] Preset gradients + pattern assets bundled
- [ ] `make check` green

## Success criteria

- Each built-in theme shows its default wallpaper behind the vault tabs + lock; rows
  remain readable. Switching wallpaper (debug) updates live. Pattern softlight + image
  blur/dim render correctly. Settings/detail stay solid.

## Risks

- Legibility over photos/loud gradients → mandatory adaptive scrim + card material.
- `List` transparency quirks per iOS 17/18 → verify both `modernTabs`/`classicTabs`.
- Pattern asset licensing — author original SVGs or use permissively-licensed set.

## Security

- User photo stored in App-Group container (not a secret, but private) → write with
  `.completeFileProtection`; covered by the existing privacy shield on background.

## Next

→ Phase 04 swaps the `.mesh` stub for the real animated Metal renderer.
