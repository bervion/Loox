---
phase: 1
title: Color & accent foundation (DS palette + 7 presets)
status: completed
priority: P1
effort: 4-6h
dependencies: []
---

# Phase 1: Color & accent foundation (DS palette + 7 presets)

## Overview

Fix the "color thấy chưa hợp lắm" complaint at the token source. Retune the builtin Day/Night
palette to **exactly** `Design System/tokens/colors.css`, and replace the 10-preset + custom-RGB
accent with the **7 DS presets** (light + dark variants from `accents.css`), removing custom RGB.
This is the critical-path foundation every screen re-tints from.

## Requirements

- Functional: builtin light + dark themes resolve to the DS semantic tokens; accent picker exposes
  the 7 DS presets with correct light/dark hue; existing persisted settings still load (no crash).
- Non-functional: `nonisolated` crypto/data types preserved; all derived tokens still computed
  (no hardcoded color in screens); WCAG `onAccent` holds for all 7 accents in light + dark.

## Key Insights

- App accent is currently a **single** `UInt32` (`AccentPreset.rgb`) — DS needs **distinct light/dark**
  per accent. Add light/dark to the preset; theme resolution picks by theme darkness.
- `onAccent`, `accentSoft`, `accentPress` are **derived** in `AppTheme+Tokens.swift` (WCAG-based) — keep
  derivation; only feed it the correct base accent. Do NOT hardcode soft/press from CSS.
- Removing enum cases breaks `Codable` for old persisted accents (`cyan/green/orange/red/yellow`) →
  add tolerant decoding (unknown → `.blue`). Keep `customRGB` field **decodable** for back-compat but
  drop it from the resolved color + all UI (Phase 2).

## Architecture

`AccentPreset` (7 cases) → `lightRGB`/`darkRGB` → `AppAccentColor` resolves base per theme →
`AppTheme` stored palette (Day/Night) retuned to colors.css → `AppTheme+Tokens` derives the rest.

## Related Code Files

- Modify: `VaultifyCore/Theme/AccentColor.swift` — 7 cases, light/dark RGB, tolerant `Codable`, drop `customRGB` from `rgb`.
- Modify: `VaultifyCore/Theme/BuiltinThemes.swift` — retune Day/Night stored palette to colors.css.
- Read/verify: `VaultifyCore/Theme/AppTheme.swift`, `AppTheme+Tokens.swift` — confirm derived tokens + accent-per-theme resolution; adjust accent resolution to use light/dark.
- Modify (if needed): `VaultifyCore/Theme/ThemeSettings.swift` — tolerant decode of `accents` / `customThemes`.

## Target tokens (from `Design System/tokens/colors.css`)

**Accents** (`accents.css`) — light / dark base (soft/press/onAccent stay derived):

| preset | light | dark |
|---|---|---|
| blue | `2563EB` | `4C8DFF` |
| indigo | `5145CD` | `8B80FF` |
| teal | `0E8A7D` | `2FD0BF` |
| purple | `7C3AED` | `B388FF` |
| pink | `D6256E` | `FF77AB` |
| graphite | `4B4B50` | `AEAEB2` |
| mono | `1C1C1E` | `FFFFFF` |

**Neutral / text / status — LIGHT:** background-base `FFFFFF`, background-grouped `F2F2F7`,
surface-base `FFFFFF`, surface-elevated `FFFFFF`, surface-pressed `rgba(60,60,67,0.10)`,
text-primary `1C1C1E`, text-secondary `4B4B50`, text-tertiary `8A8A8E`, text-disabled `B6B6BB`,
icon-primary `1C1C1E`, icon-secondary `6C6C70`, icon-disabled `C2C2C7`, separator `rgba(60,60,67,0.18)`,
separator-opaque `D8D8DE`, destructive `E5484D`, success `1A8E5F`, warning `B06F00`
(+ `*-soft`: destructive `FDEAEA`, success `E3F4EC`, warning `FBF0DB`).

**DARK:** background-base/grouped `000000`, surface-base `1C1C1E`, surface-elevated `2C2C2E`,
surface-pressed `rgba(235,235,245,0.16)`, text-primary `FFFFFF`, text-secondary `C7C7CC`,
text-tertiary `8E8E93`, text-disabled `5A5A5E`, icon-secondary `98989D`, icon-disabled `5A5A5E`,
separator `rgba(235,235,245,0.18)`, separator-opaque `38383A`, destructive `FF5C5C`,
success `30D158`, warning `FFD60A` (+ soft: `3A1D1F` / `12331F` / `33290A`).

> Reconcile names against the actual `AppTheme` field set; map 1:1 where present, leave any extra
> derived token to `AppTheme+Tokens.swift`. Do **not** invent new fields here.

## Validation Session 1 updates
<!-- Updated: Validation Session 1 - trim builtin grid to Day + Night -->

- **Trim the builtin theme grid to Day + Night only.** Keep `dayClassic`/`nightTinted` definitions in
  code, but filter them out of the user-facing grid (grid iterates `[.day, .night]`, not
  `BuiltinTheme.allCases`). Retune **Day + Night** to the colors.css table; `nightTinted`'s `.gradient`
  default (`BuiltinThemes.swift:28`) is moot under the flat-bg gate. Auto-night maps Day↔Night.

## Implementation Steps

1. Read `BuiltinThemes.swift` + `AppTheme.swift` + `AppTheme+Tokens.swift` to learn the exact field
   names and how accent + light/dark currently resolve.
2. Rewrite `AccentPreset`: cases `blue, indigo, teal, purple, pink, graphite, mono`; add
   `lightRGB`/`darkRGB` (table above). Provide `rgb(forDark:)` (or equivalent) used by resolution.
3. Add tolerant `Codable` to `AccentPreset` (custom `init(from:)` → unknown raw maps to `.blue`).
4. `AppAccentColor`: keep `customRGB` field decodable (back-compat) but make `rgb`/resolution ignore it;
   resolve `base.lightRGB`/`darkRGB` by active theme darkness.
5. Retune `BuiltinThemes` Day + Night stored palettes to the colors.css table; verify the AutoFill
   extension theme reader (`ThemeReader`) still resolves.
6. Verify `AppTheme+Tokens` still derives `onAccent`/`accentSoft`/`accentPress`/icon roles for the new
   accents; spot-check `onAccent` contrast for teal-dark, pink-dark, graphite-dark, mono (both).
7. `tuist generate --no-open` → compile workspace (app + extension). Fix errors.

## Todo List

- [ ] AccentPreset → 7 presets with light/dark RGB
- [ ] Tolerant Codable (removed cases → .blue)
- [ ] AppAccentColor resolves per-theme; customRGB ignored but decodable
- [ ] Builtin Day/Night palette retuned to colors.css
- [ ] Derived tokens + WCAG onAccent verified for all 7 (light+dark)
- [ ] `make check` passes (app + extension)

## Success Criteria

- [ ] Switching theme/accent live re-tints app to DS-accurate colors (no light/dark desync).
- [ ] Old persisted settings (e.g. accent "orange") load without crash → fall back to blue.
- [ ] No raw color literals introduced; screens unchanged (token-driven).

## Risk Assessment

- **Codable break** on enum case removal → mitigated by tolerant decode (test with a seeded old value).
- **onAccent contrast regression** for new hues → verify WCAG derivation; if a preset fails, the
  derivation (not a hardcode) must produce the readable on-color.
- Extension uses the same `VaultifyCore` theme core → retune must keep `ThemeReader` working.

## Security Considerations

None new — color tokens only. Crypto/data types stay `nonisolated`.
