# Phase 04 — Animated mesh gradient (CPU + CAKeyframeAnimation)

**Priority:** P1 · **Status:** ☐ todo · **Depends:** 03

The faithful Telegram multi-point animated mesh, using **Telegram's exact technique**:
CPU-rasterize the morph frames once per event, play them via `CAKeyframeAnimation`.
Static at rest; morphs on unlock / wrong-password / tab / preview. No Metal.

## Key insights (verified in Telegram source)

- Source: `GradientBackground/Sources/SoftwareGradientBackground.swift`.
- **8 control points** in normalized space; 4 active colors (`gatherPositions` = every
  2nd). **8 phases**; on each event `phase = (phase == 0) ? 7 : phase - 1`; `shiftArray`
  rotates positions by phase → the morph.
- Per pixel (`generateGradient`): **swirl** (`theta = (0.35·dist)²·0.8·8`), then
  **radial-basis** weight `w = max(0, 0.92 − dist)³` over 4 colors, then **saturation
  ×1.7**. Rasterized at **80×80**, scaled up by the layer.
- **Animation = baked frames + Core Animation** (NOT a display link, NOT Metal):
  `updateLayout` pre-generates `maxFrame = duration · fps` images
  (`fps = extendAnimation ? 60 : 30`), builds `CAKeyframeAnimation(keyPath:"contents")`
  with `animation.values = images.map{ $0.cgImage! }`, `calculationMode = .linear`
  (or `.discrete` for backwards/extend), `duration · UIView.animationDurationFactor()`.
  **At rest = one static `contentView.image`** (zero ongoing cost).
- **Triggers** in Telegram: `PasscodeUI` (lock screen, on digit/unlock/fail, 0.35–1.5s
  spring), `ChatControllerNode` (on send), theme/wallpaper **preview** (0.5–2.0s). No
  Reduce-Motion gating at this layer (morph is short + event-only).
- Default palette `0x7FA381 / 0xFFF5C5 / 0x336F55 / 0xFBE37D`.

## Requirements

- Port the algorithm faithfully: `MeshMath` (points/`shiftArray`/`gatherPositions`/
  `interpolatePoints`) + `generateGradient` (swirl + RBF + saturation) — all
  `nonisolated`, rasterize **off-main** on a background queue.
- `MeshGradientView` (`UIViewRepresentable` over a `UIView`): static image at rest;
  `animateEvent(duration, backwards, extend)` bakes frames + adds `CAKeyframeAnimation`
  to `layer` `contents` (Telegram's method). Expose imperative trigger.
- `MeshAnimator` owns `phase`, advances per event, drives `MeshGradientView`.
- **Triggers** (the Vaultify analog of Telegram's): `LockScreen` unlock attempt
  (forward), wrong password (backwards), success (extend); tab change (short);
  Settings preview (showy). Wire via a lightweight event bus / closures.
- Wire `Wallpaper.mesh([colors])` (replaces the Phase-03 static stub). Mesh presets +
  each dark theme's default mesh.
- Reduce Motion: render the **final frame instantly** (skip the keyframe animation).
  Honor `UIView.animationDurationFactor()` (system "Slow Animations") for free.
- **Extension**: never animates — the AutoFill extension shows a **static** rendered
  mesh frame only (memory/no-events). Reuse `generateGradient` for a single still.

## Architecture

```
VaultifyCore/Theme/Mesh/           (shared so the extension can render a still)
  MeshMath.swift                   // nonisolated: basePositions, shiftArray,
                                   //   gatherPositions, interpolatePoints (port)
  MeshGradientRenderer.swift       // nonisolated generateGradient(size,colors,positions,
                                   //   adjustSaturation) -> UIImage  (swirl+RBF+sat)
Vaultify/DesignSystem/Wallpaper/Mesh/   (app only — animation)
  MeshGradientView.swift           // UIViewRepresentable + UIView host; animateEvent()
                                   //   bakes frames + CAKeyframeAnimation(contents)
  MeshAnimator.swift               // phase state + event → animateEvent driver
```

`MeshGradientView` slots into `WallpaperView`'s `.mesh` case. Frame baking runs on a
background queue; result images handed to CA on main. Single in-flight morph guard.

## Related code files

**Create**: `VaultifyCore/Theme/Mesh/MeshMath.swift`,
`VaultifyCore/Theme/Mesh/MeshGradientRenderer.swift`,
`Vaultify/DesignSystem/Wallpaper/Mesh/MeshGradientView.swift`,
`Vaultify/DesignSystem/Wallpaper/Mesh/MeshAnimator.swift`.
**Modify**: `WallpaperView.swift` (`.mesh` → real view + extension still),
`LockScreen.swift` + `MainTabView.swift` (morph triggers), `ThemeStore` (reduceMotion).

## Implementation steps

1. `MeshMath` (port positions/shift/gather/interp) + unit tests (deterministic).
2. `MeshGradientRenderer.generateGradient` (swirl + RBF + saturation) matching the
   reference; DEBUG self-test: render default palette still, compare visually.
3. `MeshGradientView` static draw; then `animateEvent` (bake frames off-main +
   `CAKeyframeAnimation`), single-in-flight guard, Reduce-Motion = final frame.
4. `MeshAnimator` + wire triggers (lock unlock/fail/success, tab, preview).
5. Replace `.mesh` stub; add mesh presets; extension renders a still; `make check`;
   device perf check (idle ~0%, smooth morph).

## Todo

- [ ] `MeshMath` + tests (deterministic)
- [ ] `MeshGradientRenderer.generateGradient` matches reference (nonisolated, off-main)
- [ ] `MeshGradientView` static + `animateEvent` (CAKeyframeAnimation) + reduce-motion
- [ ] `MeshAnimator` + triggers (lock/tab/preview)
- [ ] `.mesh` wired + presets + extension still
- [ ] `make check` green + device perf OK

## Success criteria

- Renders the exact Telegram default palette at rest; morphs smoothly on lock-screen
  events / tab / preview (like Telegram); **zero cost at rest** (no display link, no
  Metal); Reduce Motion jumps to final frame; no regressions on 17.6 sim + a real
  device. Extension shows a static mesh with no animation.

## Risks

- Off-main baking → must hop to main to attach the animation; guard against overlapping
  morphs (cancel/replace). Cache the last still per (colors,phase).
- Color fidelity (sat boost, sRGB) vs reference — calibrate against a captured still.
- Frame memory: ~30 × 80×80 images per morph is tiny; release after the animation
  completes (`isRemovedOnCompletion = true`).
- (Metal-in-CI risk is **eliminated** by this CPU approach.)

## Security

- None (CPU image generation only). No data flows.

## Next

→ Phase 05 builds the Settings UI to choose themes/accents/wallpapers/mesh palettes.
