# Phase 01 — Theme model & engine core

**Priority:** P0 (foundation) · **Status:** ☐ todo · **Depends:** —

Foundation types + store. No visual change yet beyond root tint/colorScheme wiring.
Everything else builds on this. Adapt Telegram's `PresentationTheme` /
`PresentationThemeSettings` minus chat.

## Key insights

- Telegram theme = immutable object of ~11 nested color groups; only *app-chrome*
  groups matter (nav/tab, list, controls, sheet/alert/menu, field). Drop chat groups.
- Accent customization = HSB-derive a few colors from one accent (see
  `DefaultDarkPresentationTheme.swift` recolor). Port the math, not the 500-line tables.
- Settings persist as one Codable struct + per-theme accent/wallpaper maps.
- Current app: `AppearanceMode {system,light,dark}` in `SettingsStore`, applied via
  `.preferredColorScheme` in `VaultifyApp.swift:19`; accent via asset `AccentColor`.

## Requirements

- Define `AppTheme` (semantic colors), `AppThemeReference` + `BuiltinTheme`,
  `AppAccentColor` (+ recolor), `ThemeSettings` (Codable), `AutoNightSetting`.
- `ThemeStore` (`@MainActor @Observable`) owns settings, persists to **App Group**
  defaults, resolves the **active** `AppTheme` from (reference + accent + auto-night +
  system trait), exposes active wallpaper.
- Migrate old `appearance_mode`: `system→autoNight.system(day/night)`, `light→.day`,
  `dark→.night`.
- Inject active `AppTheme` + `ThemeStore` into SwiftUI environment; root applies
  `.tint(theme.accent)` + `.preferredColorScheme(theme.resolvedColorScheme)`.

## Architecture

```
ThemeSettings (Codable, App Group JSON)
  theme: AppThemeReference            // .builtin(BuiltinTheme) | .custom(UUID)
  accents: [String: AppAccentColor]   // per theme-key override
  wallpapers: [String: Wallpaper]     // per theme-key (Wallpaper lands Phase 03)
  customThemes: [CustomTheme]         // Phase 06
  autoNight: AutoNightSetting         // .off | .system | .time(from,to) | .brightness(t)
  fontScale: FontScale                // Phase 05 slider; default .regular
  reduceMotion: Bool

ThemeStore (@Observable)
  - load/save settings (suite group.com.bervion.vaultify)
  - var active: AppTheme   (resolved; recomputed on settings / trait / time change)
  - var wallpaper: Wallpaper
  - migration from standard defaults
  - resolve(reference,accent,isDarkNow) -> AppTheme via BuiltinThemes + recolor
```

`AppTheme` groups: `chrome` (nav/tab/toolbar bg+tint+separator), `list`
(bg plain/grouped, itemBg, text primary/secondary/tertiary, accent, separator,
destructive), `control` (switchOn, check, buttonFill/Stroke, selection), `surface`
(card/material tints, sheet dim), `field` (bg, stroke, placeholder), plus Vaultify
semantics: `category(ItemCategory)`, `strength(PasswordStrength)`, `severity`.

## Related code files

**Create** (under `Vaultify/DesignSystem/Theme/`): `AppTheme.swift`,
`AppThemeReference.swift`, `BuiltinThemes.swift`, `AccentColor.swift`,
`ThemeSettings.swift`, `AutoNight.swift`, `ThemeStore.swift`, `ThemeEnvironment.swift`.

**Modify**: `Vaultify/App/AppEnvironment.swift` (own `ThemeStore`),
`Vaultify/App/VaultifyApp.swift` (tint + colorScheme from theme),
`Vaultify/App/SettingsStore.swift` (remove `appearance`; keep other prefs),
`VaultifyCore/SharedConfig.swift` (reuse app-group id constant).

## Implementation steps

1. Port `AppAccentColor` + `nonisolated` `recolor(base:UIColor, accent:UIColor)` HSB
   helpers (from Telegram dark/day recolor). Preset list: blue/cyan/green/teal/orange/
   pink/purple/red/yellow/graphite + custom RGB.
2. Define `AppTheme` struct + `BuiltinThemes.day/.dayClassic/.night/.nightTinted`
   with literal Polaris-derived palettes (reuse existing hex in `VaultColors`).
3. `ThemeSettings` + `AutoNightSetting` Codable; default `.builtin(.day)` +
   `autoNight.system`.
4. `ThemeStore`: App-Group load/save, migration, `active`/`wallpaper` resolution,
   auto-night evaluation (system trait now; time/brightness come from `AutoNight`).
5. `ThemeEnvironment`: `EnvironmentValues.appTheme`; helper `Color`/style accessors.
6. Wire `AppEnvironment` + `VaultifyApp` (tint + colorScheme). Keep visuals identical
   for default theme (no regression).
7. `tuist generate` → `make check`.

## Todo

- [ ] AccentColor + recolor (nonisolated) + unit-testable
- [ ] AppTheme + 4 BuiltinThemes
- [ ] ThemeSettings / AutoNightSetting Codable
- [ ] ThemeStore (App Group persist + migration + resolution)
- [ ] Environment injection + root tint/colorScheme
- [ ] Migrate & remove `SettingsStore.appearance` references (compile)
- [ ] `make check` green

## Success criteria

- Builds (app+ext). Default look unchanged. Switching `theme`/`accent` in a debug
  harness recolors `Color.accentColor` app-wide. Settings round-trip through App Group.
- Codec + recolor covered by unit tests (Phase 07 expands).

## Risks

- Removing `appearance` touches `SettingsScreen`, `ChooseThemeView`, `OnboardingFlow`
  → update in this phase (temporary shims ok) to keep compiling.
- App-Group defaults vs standard defaults: ensure migration runs once; guard a flag.

## Security

- Settings are non-secret prefs. No secrets in defaults. App-Group container already
  used for the vault — same trust boundary.

## Next

→ Phase 02 re-backs all chrome/semantic colors by `active` theme.
