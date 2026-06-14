# Phase 02 — Semantic color migration (app-wide)

**Priority:** P0 · **Status:** ☐ todo · **Depends:** 01

Make built-in themes + accent actually drive the whole UI. No wallpaper yet — this
phase guarantees every screen reads theme colors and stays legible in all 4 themes.

## Key insights

- `VaultColors` is the existing semantic layer (category/strength). 20+ screens use
  `Color.accentColor` + `VaultColors.*`. Re-back these by `active` theme instead of
  hardcoded light/dark hex.
- `.tint()` at root recolors all `Color.accentColor` usages for free (Phase 01).
- Standard `List`/`Form` chrome (separators, grouped bg, nav bar) follows
  `preferredColorScheme` + tint; only custom-colored surfaces need explicit theming.

## Requirements

- `VaultColors` reads from `active` `AppTheme` (category/strength/severity) while
  keeping its call sites unchanged (API-compatible static funcs → theme-aware).
- Nav/tab bar, grouped backgrounds, card surfaces, switches/checks reflect the theme
  (esp. Night-Tinted, which is not plain black).
- Verify contrast/legibility for Day / Day-Classic / Night / Night-Tinted.
- **AutoFill extension UI** reads the shared theme (`VaultifyCore` `ThemeReader`, App
  Group) and applies themed colors + accent — same chrome as the app, static (no
  wallpaper/morph in the extension). Modify `VaultifyAutoFill/**` credential views.

## Architecture

- Convert `VaultColors` static color props/funcs to resolve via an injected
  `AppTheme` (read from a `@MainActor` current-theme holder or environment-bridged
  cache). Keep `dynamic(light:dark:)` fallback for any not-yet-mapped color.
- Introduce themed surface helpers: `themedCard`, `themedGroupedBackground`,
  `themedSeparator` used by list rows / sections.

## Related code files

**Modify**: `Vaultify/DesignSystem/VaultColors.swift` (theme-backed),
`Vaultify/Features/Main/MainTabView.swift` (tab tint/toast),
`Vaultify/Features/Settings/SettingsScreen.swift` (Appearance section temp),
`Vaultify/Features/Components/VaultComponents.swift`, item-row/detail/editor field
rows that hardcode colors (`VaultItemRowLink.swift`, `DetailFieldRow.swift`,
`ProtectedFieldRow.swift`, `TOTPFieldRow.swift`, `EditorFieldRow.swift`, etc.).

**Create**: `Vaultify/DesignSystem/Theme/ThemedSurfaces.swift` (surface helpers).

## Implementation steps

1. Bridge `active` theme to a synchronously-readable holder so `VaultColors` static
   API can resolve without a `View` context (e.g. `ThemeStore.current` set on change).
2. Map every `VaultColors` value + category/strength to theme tokens; keep signatures.
3. Add `ThemedSurfaces` helpers; apply to cards/sections that previously used
   `Color(.secondarySystemBackground)` etc.
4. Audit the 4 themes on key screens (Home, Items list, Item detail, Editor, Settings,
   Lock, Onboarding) for contrast; fix tokens.
5. `tuist generate` → `make check`; DEBUG self-test screenshot per theme.

## Todo

- [ ] Theme-backed `VaultColors`
- [ ] `ThemedSurfaces` + apply to cards/sections
- [ ] Tab/nav tint per theme
- [ ] 4-theme legibility audit + fixes
- [ ] `make check` green

## Success criteria

- Toggling theme/accent live-recolors the whole app with no hardcoded-color leftovers
  on the audited screens. All 4 themes pass a contrast eyeball pass (WCAG-ish).

## Risks

- Static `VaultColors` reading a mutable current theme can render stale on first frame
  → ensure `ThemeStore` sets `current` before first `body`; invalidate on change.
- Over-theming system `Form` can look off — prefer leaving native grouped chrome to
  `colorScheme`/tint where it already looks right.

## Security

- None (presentation only).

## Next

→ Phase 03 adds the wallpaper layer behind canvas/lock and floats content in cards.
