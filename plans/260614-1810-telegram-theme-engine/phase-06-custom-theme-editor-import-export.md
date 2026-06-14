# Phase 06 — Custom theme editor + import/export

**Priority:** P2 · **Status:** ☐ todo · **Depends:** 05

The "tối đa" tail: let users compose, name, save, and share themes — mirrors Telegram's
`EditThemeController` + cloud-theme share, but as a local `.vaultheme` JSON file
(no backend, on-brand).

## Key insights

- A custom theme = base built-in + accent + wallpaper (+ optional color overrides) +
  name. Telegram stores these per-theme and lets users export/import; we keep it local
  and file-based (offline-first).
- Reuse Phase-05 editors; this phase adds the compose → save → manage → share loop.

## Requirements

- `CustomTheme` Codable (id, name, base `BuiltinTheme`, `AppAccentColor`, `Wallpaper`,
  optional color overrides). Stored in `ThemeSettings.customThemes`.
- `ThemeEditorView`: compose (base + accent + wallpaper + name) with live preview; save
  → appears in `ThemePickerView`. Edit / duplicate / delete.
- Export a `CustomTheme` to a `.vaultheme` file (JSON) via share sheet; import via
  document picker (validate + add). Define UTType `com.bervion.vaultify.theme`.
- Manage list: rename, delete, set active.

## Architecture

```
Features/Settings/Appearance/
  ThemeEditorView.swift        // compose + name + live preview + save
  CustomThemeListView.swift    // manage saved themes (rename/dup/delete/share)
  ThemeImportExport.swift      // .vaultheme encode/decode + UTType + share/import
Models:
  CustomTheme (Codable) in DesignSystem/Theme/AppThemeReference.swift (or own file)
```

`.vaultheme` = versioned JSON `{ schema, name, base, accent, wallpaper, overrides }`.
Image-backed wallpapers export the image inline (base64) or fall back to gradient if
too large (cap file size).

## Related code files

**Create**: `ThemeEditorView.swift`, `CustomThemeListView.swift`,
`ThemeImportExport.swift`, `CustomTheme.swift`.
**Modify**: `ThemeSettings.swift` (customThemes already reserved in Phase 01),
`ThemePickerView.swift` (show custom + "Create new"), `AppearanceSettingsView.swift`
(entry point), `Project.swift` (declare exported UTType for `.vaultheme`),
`Localizable.xcstrings` (EN+VI).

## Implementation steps

1. `CustomTheme` model + `ThemeStore` CRUD (add/update/delete/setActive).
2. `ThemeEditorView` reusing accent/wallpaper editors + name field + live preview.
3. `CustomThemeListView` manage screen.
4. `ThemeImportExport`: UTType, encode/decode, image size cap, share sheet + document
   picker; validate schema/version on import.
5. Wire into picker/settings; localize; `make check`.

## Todo

- [ ] `CustomTheme` model + store CRUD
- [ ] `ThemeEditorView` (compose + save + live preview)
- [ ] `CustomThemeListView` (rename/dup/delete/share)
- [ ] `.vaultheme` UTType + export/import + validation
- [ ] Picker/settings integration + EN+VI
- [ ] `make check` green

## Success criteria

- User creates, names, saves a theme; it appears in the picker and applies; can export
  a `.vaultheme`, delete it, re-import the same file, and get an identical theme.

## Risks

- Import of untrusted JSON → strict schema/version validation, clamp colors, ignore
  unknown fields, size-cap embedded images (avoid decompression bombs).
- Embedding photos in JSON bloats files → cap + warn / fall back.

## Security

- Imported themes are presentation-only; never execute or trust embedded paths. Decode
  defensively (no force-unwrap), sandbox image to App-Group storage, file protection.

## Next

→ Phase 07: polish, perf, a11y, tests, docs.
