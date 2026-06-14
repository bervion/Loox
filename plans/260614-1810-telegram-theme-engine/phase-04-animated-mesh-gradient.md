# Phase 04 — Animated mesh gradient (Metal, signature effect)

**Priority:** P1 · **Status:** ☐ todo · **Depends:** 03

The faithful Telegram multi-point animated mesh, in **Metal** so it runs on iOS 17.6.
Static at rest; morphs on unlock-success / navigation. Honors Reduce Motion + Low Power.

## Key insights (ported algorithm)

- Source: `GradientBackground/Sources/SoftwareGradientBackground.swift`.
- **8 control points** in normalized space; color sampled at 4 active points
  (`gatherPositions` = every 2nd). **8 phases**; `shiftArray` rotates positions one
  step → the "shift/morph" on send.
- Per pixel: **swirl** transform (`theta = (0.35·dist)²·0.8·8`), then **radial-basis**
  weighting `w = max(0, 0.92 − dist)³` over the 4 colors, then **saturation ×1.7**.
- Telegram rasterizes 80×80 on CPU and key-frames `contents`. We instead run the same
  math in a **fragment shader** (smoother morph, GPU-cheap, one code path for 17.6/18).
- Default palette `0x7FA381 / 0xFFF5C5 / 0x336F55 / 0xFBE37D`.

## Requirements

- `Mesh.metal` fragment shader: uniforms = 4 colors (interp'd from/to during morph),
  4 positions (interp'd), phase blend `t`, resolution, saturation. Reproduce swirl +
  RBF + saturation.
- `MeshRenderer` (Metal device/pipeline/CAMetalLayer) + `MeshGradientView`
  (`UIViewRepresentable`). Draw once when static; `CADisplayLink` only during a morph.
- `MeshMath` (`nonisolated`, pure) = control points, `shiftArray`, `gatherPositions`,
  interpolation — unit-testable without Metal.
- `MeshAnimator`: trigger `morph()` on unlock-success + tab change; ease over ~0.5s;
  advance phase 0→7 cyclically. No animation at rest.
- Gating: if `reduceMotion` (settings or system) or **Low Power Mode** → render static
  final frame, skip display link.
- Wire `Wallpaper.mesh([colors])`; mesh presets + each dark theme's default mesh.

## Architecture

```
Wallpaper/Mesh/
  Mesh.metal            // swirl + radial-basis + saturation fragment shader
  MeshRenderer.swift    // MTLDevice, pipeline, CAMetalLayer draw(uniforms)
  MeshGradientView.swift// UIViewRepresentable(colors, phaseProvider)
  MeshAnimator.swift    // CADisplayLink morph driver + gating (nonisolated math calls)
  MeshMath.swift        // nonisolated points/shift/gather/interpolate
```

`MeshGradientView` slots into `WallpaperView`'s `.mesh` case (replaces Phase-03 stub).
Morph hook: `env.session.state` → unlocked fires `MeshAnimator.morph()`; `MainTabView`
selection change fires a lighter morph.

## Related code files

**Create**: the five `Wallpaper/Mesh/*` files above.
**Modify**: `WallpaperView.swift` (`.mesh` → real view), `MainTabView.swift` +
`RootView.swift`/`LockScreen.swift` (morph triggers), `ThemeStore` (reduceMotion).
**Tuist**: confirm `.metal` under `Vaultify/**` compiles into `default.metallib`
(else add to `resources`/Metal build settings); `tuist generate`.

## Implementation steps

1. `MeshMath` (port points, shift, gather, lerp) + unit tests.
2. `Mesh.metal` shader (swirl + RBF + saturation) matching CPU reference; validate
   one frame vs Telegram colors via DEBUG self-test image.
3. `MeshRenderer` + `MeshGradientView` static draw.
4. `MeshAnimator` morph (CADisplayLink, 0.5s ease, phase cycle) + Reduce-Motion/Low-Power
   gating; hook unlock + tab triggers.
5. Replace `.mesh` stub; add mesh presets; `make check`; on-device perf check.

## Todo

- [ ] `MeshMath` + tests (deterministic)
- [ ] `Mesh.metal` shader matches reference
- [ ] `MeshRenderer` + `MeshGradientView` (static draw)
- [ ] `MeshAnimator` morph + gating (reduce-motion / low-power)
- [ ] Triggers (unlock, tab) + presets + Tuist metallib verified
- [ ] `make check` green + device perf OK

## Success criteria

- Mesh renders identical palette to Telegram default at rest; morphs smoothly on
  unlock/tab; **zero CPU/GPU at rest** (no display link); disabled under Reduce Motion /
  Low Power. No regressions on 17.6 sim + a real device.

## Risks

- **Metal in Tuist/CI** (stable Xcode runner) — verify metallib builds in CI early; if
  flaky, fall back to Telegram's CPU 80×80 raster (`nonisolated`, cached) behind same
  `MeshGradientView` API.
- Battery/thermals if morph misfires into a loop → guard single in-flight morph.
- Color fidelity (sat boost, sRGB) — calibrate against reference image.

## Security

- None (GPU rendering only). No data flows.

## Next

→ Phase 05 builds the Settings UI to choose themes/accents/wallpapers/mesh palettes.
