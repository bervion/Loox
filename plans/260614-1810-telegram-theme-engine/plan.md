# Telegram-style Theme & Wallpaper Engine — Vaultify

Port + adapt Telegram iOS 12.8's theme/appearance + wallpaper system into Vaultify
(native SwiftUI, no chat). Strip all chat-only color groups; keep app-chrome theming,
multi-theme + accent recolor, and the wallpaper engine (incl. the signature animated
mesh gradient) rendered behind the "canvas" screens.

## Scope decisions (confirmed with user)

- **Effect**: faithful animated multi-point **mesh gradient**, rendered with **Metal**
  so it runs on the **iOS 17.6** floor (SwiftUI `MeshGradient` is iOS 18+). Static at
  rest; morphs on unlock-success / navigation — not a constant animation (battery).
- **Feature breadth**: **maximum** — built-in themes (Day / Day-Classic / Night /
  Night-Tinted) + accent picker + wallpaper picker (presets + custom) + auto-night +
  **custom theme editor** (save / export / import `.vaultheme`) + global text-size.
- **Background placement**: **canvas + lock** — behind the vault tabs (Home/Items/
  Watchtower/Search), `LockScreen`, and onboarding; content floats in cards/material.
  Settings / detail / editor keep a **solid themed** background for legibility.
- **Custom background source**: curated **presets + user photo**. Use SwiftUI
  `PhotosPicker` (PHPicker, out-of-process) → **no `NSPhotoLibraryUsageDescription`
  needed** (better for a privacy app). Photo copied into the App Group container.

## Source maps (research)

- Telegram theme architecture → `plans/reports/` exploration (PresentationTheme,
  built-ins, accent HSB recolor, `PresentationThemeSettings`, auto-night, Signal apply).
- Telegram wallpaper/mesh → `TelegramWallpaper`, `GradientBackground/
  SoftwareGradientBackground.swift` (8-point swirl + radial-basis, phase shift),
  pattern softlight, blur, `UIMotionEffect` parallax. Default mesh palette
  `0x7FA381 / 0xFFF5C5 / 0x336F55 / 0xFBE37D`.

## Phases

| # | Phase | Status | Depends |
|---|-------|--------|---------|
| 01 | [Theme model & engine core](phase-01-theme-model-and-engine.md) | ☐ todo | — |
| 02 | [Semantic color migration (app-wide)](phase-02-semantic-color-migration.md) | ☐ todo | 01 |
| 03 | [Wallpaper engine — static (solid/gradient/pattern/image)](phase-03-wallpaper-engine-static.md) | ☐ todo | 01,02 |
| 04 | [Animated mesh gradient (Metal, signature)](phase-04-animated-mesh-gradient.md) | ☐ todo | 03 |
| 05 | [Appearance Settings UI (maximum)](phase-05-appearance-settings-ui.md) | ☐ todo | 01-04 |
| 06 | [Custom theme editor + import/export](phase-06-custom-theme-editor-import-export.md) | ☐ todo | 05 |
| 07 | [Polish · perf · a11y · tests · docs](phase-07-polish-perf-tests-docs.md) | ☐ todo | 01-06 |

## Cross-cutting constraints

- **Localization (MANDATORY)**: every new user-facing string → `Localizable.xcstrings`
  with **EN + VI**. Titles use `.inAppLocalized`; runtime uses `appString()`.
- **iOS 17.6 ceiling**: no iOS 18-only API without `#available`. Metal path is unified
  (works on 17.6 + 18). `PhotosPicker` is iOS 16 — fine.
- **Concurrency**: heavy/pure compute (`MeshMath`, recolor, codecs) marked
  `nonisolated`; project default isolation is `MainActor`.
- **Tuist**: new files under `Vaultify/**` are globbed — run `tuist generate` after
  adding files. Verify `.metal` compiles into the default metallib; add patterns to
  `Assets.xcassets` (already a resource).
- **Icons**: Polaris SVG only (`PolarisIcon`), no SF Symbols.
- **Persistence**: theme settings in **App Group** defaults (`group.com.bervion.vaultify`)
  so the AutoFill extension can later read them; migrate the old `appearance_mode` key.

## Delivery

Dedicated branch `feat/telegram-theme-engine` → its own PR (per request). Each phase is
an independent, compilable increment (`make check` green) with EN+VI strings landed in
the same commit. Tests via `make test`.

## Open questions

- Theme the **AutoFill extension** UI too? (deferred — optional tail of Phase 07.)
- Ship a "Reduce battery / disable motion at <20%" auto-rule, or only honor system
  Reduce Motion + Low Power Mode? (Phase 04 default: honor system + Low Power.)
