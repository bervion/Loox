# Phase 07 — Polish · perf · a11y · tests · docs

**Priority:** P2 · **Status:** ☐ todo · **Depends:** 01-06

Make it feel native + ship-ready: theme-switch crossfade, optional parallax, perf/
battery pass, accessibility, full test suite, docs, optional AutoFill theming.

## Requirements

- **Theme-switch transition**: Telegram-style crossfade when theme/wallpaper changes
  (snapshot old → fade to new) instead of an abrupt swap.
- **Parallax/motion** (optional, gated): `UIMotionEffect` tilt on wallpaper (Phase-03
  `motion` flag), off under Reduce Motion / Low Power.
- **Perf/battery**: confirm mesh idles at zero cost; cap morph rate; downscale photos;
  cache rendered gradients; instrument with a DEBUG FPS overlay.
- **Accessibility**: contrast audit all built-ins + a few custom combos; honor Reduce
  Motion + Reduce Transparency (drop blur → solid scrim); Dynamic Type / text-size
  interplay; VoiceOver labels on all new controls.
- **Tests** (`VaultifyTests`): `ThemeSettings`/`CustomTheme`/`Wallpaper` Codec round-trip;
  accent recolor determinism; auto-night resolution (time/brightness/system → expected);
  `MeshMath` (shift/gather/interp) determinism; migration from `appearance_mode`.
- **Docs**: update `docs/codebase-summary.md` (new Theme/Wallpaper subsystems) +
  `README.md` highlight; note Metal + App-Group theme settings.
- **AutoFill extension** (now core, delivered in Phase 02/03): verify it reads the
  shared theme, applies colors/accent + static background, and stays within the
  extension memory budget (no morph); fall back to the default theme if the settings
  file is missing/unreadable.

## Related code files

**Create**: `Vaultify/DesignSystem/Theme/ThemeTransition.swift` (crossfade),
`VaultifyTests/ThemeEngineTests.swift`, `VaultifyTests/WallpaperCodecTests.swift`,
`VaultifyTests/AutoNightResolutionTests.swift`, `VaultifyTests/MeshMathTests.swift`.
**Modify**: `RootView.swift` (transition host), `WallpaperView.swift` (motion + reduce-
transparency), `docs/codebase-summary.md`, `README.md`, optionally
`VaultifyAutoFill/**` + `Project.swift` (extension reads App-Group theme).

## Implementation steps

1. Theme-switch crossfade in `RootView`/`ThemedBackground`.
2. Optional parallax + Reduce-Transparency fallback.
3. Perf pass (idle cost, morph cap, photo downscale, gradient cache) + DEBUG FPS.
4. Accessibility audit + fixes (contrast, VoiceOver, Dynamic Type).
5. Write unit tests; `make test DEST=...` green.
6. Update docs/README; (optional) AutoFill theming.
7. Final `make check` + `make test`.

## Todo

- [ ] Theme/wallpaper crossfade transition
- [ ] Optional parallax + reduce-transparency fallback
- [ ] Perf/battery pass + DEBUG FPS overlay
- [ ] Accessibility audit + fixes
- [ ] Unit tests (codec / recolor / auto-night / mesh / migration)
- [ ] Docs + README updated
- [ ] (Optional) AutoFill extension theming
- [ ] `make check` + `make test` green

## Success criteria

- Smooth crossfade on theme change; mesh idles at ~0% CPU; all new tests pass; a11y
  audit clean; docs current. Feature is demo-ready on iOS 17.6 sim + a real device.

## Risks

- AutoFill theming could destabilize the extension → keep optional / behind a flag,
  ship core first.
- Crossfade snapshotting over Metal layer → verify it captures the live mesh; fallback
  to opacity-only fade.

## Security

- Re-confirm no secrets in theme settings/files; photos under file protection; privacy
  shield still covers themed canvas on background.

## Next

→ Ship: push `feat/telegram-theme-engine`, open PR, `make release` after review.
