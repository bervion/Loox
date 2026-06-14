# Telegram-style Theme & Wallpaper Engine — Vaultify

Port + adapt Telegram iOS 12.8's theme/appearance + wallpaper system into Vaultify
(native SwiftUI, no chat). Strip all chat-only color groups; keep app-chrome theming,
multi-theme + accent recolor, and the wallpaper engine (incl. the signature animated
mesh gradient) rendered behind the "canvas" screens — and themed into the AutoFill
extension too.

## Scope decisions (confirmed with user)

- **Effect**: faithful animated multi-point **mesh gradient**, using **Telegram's exact
  technique** — CPU-rasterize the morph frames (80×80, swirl + radial-basis) once per
  event, then play them via a `CAKeyframeAnimation` on the layer's `contents`. **Static
  image at rest (zero cost)**; **event-driven morph** on unlock / wrong-password / tab /
  preview (mirrors Telegram's passcode screen + on-send). **No Metal** → runs on the
  **iOS 17.6** floor and sidesteps the metallib-in-CI risk. (Metal = future-only opt.)
- **Feature breadth**: **maximum** — built-in themes (Day / Day-Classic / Night /
  Night-Tinted) + accent picker + wallpaper picker (presets + custom) + auto-night +
  **custom theme editor** (save / export / import `.vaultheme`) + global text-size.
- **Background placement**: **canvas + lock** — behind the vault tabs (Home/Items/
  Watchtower/Search), `LockScreen`, and onboarding; content floats in cards/material.
  Settings / detail / editor keep a **solid themed** background for legibility.
- **Custom background source**: curated **presets + user photo**. Use SwiftUI
  `PhotosPicker` (PHPicker, out-of-process) → **no `NSPhotoLibraryUsageDescription`
  needed** (better for a privacy app). Photo copied into the App Group container.
- **AutoFill extension is themed too**: the theme **core** (model + resolution +
  App-Group read) lives in **`VaultifyCore`** (compiled into both targets); the
  extension applies themed **colors + accent + a static background** (no live morph —
  extensions have a tight memory budget + no events to drive it).
- **Motion**: faithful to Telegram — morph is short + event-driven (no continuous
  animation, **no battery rule**). Honor Reduce Motion by jumping to the final frame.

## Source maps (research)

- Telegram theme architecture → exploration (PresentationTheme, built-ins, accent HSB
  recolor, `PresentationThemeSettings`, auto-night, Signal apply).
- Telegram wallpaper/mesh → `TelegramWallpaper`, `GradientBackground/
  SoftwareGradientBackground.swift`: 8-point swirl + radial-basis; `phase = (phase==0 ?
  7 : phase-1)` per event; frames baked → `CAKeyframeAnimation(keyPath:"contents")`,
  `fps = extendAnimation ? 60 : 30`. Triggers: `PasscodeUI` (lock), `ChatControllerNode`
  (send), theme/wallpaper preview. Default mesh palette
  `0x7FA381 / 0xFFF5C5 / 0x336F55 / 0xFBE37D`. Pattern = softlight overlay; blur; motion
  via `UIMotionEffect`.

## Phases

| # | Phase | Status | Depends |
|---|-------|--------|---------|
| 01 | [Theme model & engine core (shared in VaultifyCore)](phase-01-theme-model-and-engine.md) | ☐ todo | — |
| 02 | [Semantic color migration (app + extension)](phase-02-semantic-color-migration.md) | ☐ todo | 01 |
| 03 | [Wallpaper engine — static (solid/gradient/pattern/image)](phase-03-wallpaper-engine-static.md) | ☐ todo | 01,02 |
| 04 | [Animated mesh gradient (CPU + CAKeyframeAnimation)](phase-04-animated-mesh-gradient.md) | ☐ todo | 03 |
| 05 | [Appearance Settings UI (maximum)](phase-05-appearance-settings-ui.md) | ☐ todo | 01-04 |
| 06 | [Custom theme editor + import/export](phase-06-custom-theme-editor-import-export.md) | ☐ todo | 05 |
| 07 | [Polish · perf · a11y · tests · docs](phase-07-polish-perf-tests-docs.md) | ☐ todo | 01-06 |

## Cross-cutting constraints

- **Localization (MANDATORY)**: every new user-facing string → `Localizable.xcstrings`
  with **EN + VI**. Titles use `.inAppLocalized`; runtime uses `appString()`.
- **iOS 17.6 ceiling**: no iOS 18-only API without `#available`. Mesh is CPU + Core
  Animation (works on 17.6 + 18). `PhotosPicker` is iOS 16 — fine.
- **Concurrency**: heavy/pure compute (mesh `generateGradient`, recolor, codecs) marked
  `nonisolated` + run off-main; project default isolation is `MainActor`.
- **Tuist**: new files under `Vaultify/**` / `VaultifyCore/**` are globbed — run
  `tuist generate` after adding files. Add patterns to `Assets.xcassets` (already a
  resource). No `.metal` (mesh is CPU + Core Animation).
- **Icons**: Polaris SVG only (`PolarisIcon`), no SF Symbols.
- **Persistence**: theme settings in **App Group** defaults (`group.com.bervion.vaultify`)
  so the AutoFill extension reads them; migrate the old `appearance_mode` key.

## Delivery

Dedicated branch `feat/telegram-theme-engine` → its own PR (per request). Each phase is
an independent, compilable increment (`make check` green) with EN+VI strings landed in
the same commit. Tests via `make test`.

## Resolved decisions

- Theme the **AutoFill extension**: **yes** — colors + accent + static background
  (shared `VaultifyCore` theme core; no live morph in the extension).
- Motion/battery: **no** special battery rule. Faithful to Telegram — brief
  event-driven morph; honor Reduce Motion by jumping to the final frame.

## Open questions

None outstanding.
