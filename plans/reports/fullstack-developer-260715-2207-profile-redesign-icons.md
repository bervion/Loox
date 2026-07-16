# Profile Screen Redesign — Icons (260715)

Redesigned the Profile hub's row icons per owner spec: SF Symbols (Profile-only exception) for
Section 1/2 tiles, the Loox brand mark on a white badge, and FontAwesome6 Duotone device icons
for an inline Devices list. Scope: `Vaultify/Features/Profile/**` + new device-icon assets only.

## Files changed

| File | Why |
| --- | --- |
| `Vaultify/Features/Profile/ProfileComponents.swift` | Extended `ProfileRowTile`/`ProfileNavRow` with `ProfileTileStyle`/`ProfileGlyphSource` (system-gray, white-badge, brand-mark tile styles); added `ProfileBadgeTint` (fixed contrast-safe glyph tints); extracted `DeviceRow` (shared device-row rendering) and `ProfileDevicesCard` (new inline Devices card); tokenized `ProfileRowDivider`'s hardcoded `30`. |
| `Vaultify/Features/Profile/ProfileScreen.swift` | Section 1 (Personal Information, Payment) → `.system` SF Symbol tiles; Section 2 Loox → `.brandMark`, Family → `.colored` SF Symbol; Devices nav row replaced with inline `ProfileDevicesCard()`. Doc comments updated to match. |
| `Vaultify/Features/Profile/DevicesScreen.swift` | Refactored to reuse the shared `DeviceRow`/`ProfileRowDivider` (removed the now-duplicate `deviceRow`/`subtitle`/`activeBadge`); doc comment notes it's currently unlinked from Profile (kept as a future destination, not deleted). |
| `Vaultify/Features/Profile/DeviceIcons.swift` (new) | `DeviceIcons` asset-name constants + `DeviceIconMapping.icon(forModel:)` — pure, testable device-type → glyph mapping. |
| `Vaultify/Assets.xcassets/DeviceIcons/` (new) | 8 imagesets (`fa_mobile_notch`, `fa_tablet_screen`, `fa_laptop`, `fa_computer_speaker`, `fa_computer_classic`, `fa_display`, `fa_watch_apple`, `fa_glasses`) — raw FontAwesome6 Duotone SVGs copied verbatim, `Contents.json` mirrors the existing Polaris pattern exactly (`preserves-vector-representation` + `template-rendering-intent: template`). |
| `VaultifyTests/DeviceIconMappingTests.swift` (new) | Unit tests for `DeviceIconMapping` — known Apple device strings, Mac-variant substring ordering (`macbook`/`mac mini`/`mac studio` vs generic `mac`), case-insensitivity, unknown-model fallback. |

No files outside this list were touched. Verified via `git status`/`git diff --stat` before and after — the pre-existing Family-sharing/SpaceShareSafelist uncommitted changes are untouched.

## SF Symbols used (Profile-only exception, 260715)

| Row | Symbol | Tile |
| --- | --- | --- |
| Personal Information | `person.text.rectangle.fill` | `.system` — white glyph on fixed system-gray (`0x8E8E93`/`0x98989D`, Apple's own `systemGray` light/dark — matches `SettingsIconBadge`'s existing precedent for this exact look) |
| Payment | `creditcard.fill` | `.system`, same tile |
| Family | `person.2.fill` | `.colored` — tint `ProfileBadgeTint.family` (fixed `0x1A8E5F`) on white + hairline border |
| Loox | *(no SF Symbol — `.brandMark`, the actual `Image("BrandSymbol")` six-circle Loox logo)* | white + hairline border, `Space.s1` inset |

Every SF Symbol usage carries the `// Profile-only SF Symbols: owner-approved exception to the
Polaris-only rule (260715).` comment at its call site (`ProfileRowTile.body` and `.glyph(_:)`).
`Icons.device` (`ic_phone`, the old single Polaris device glyph) is no longer referenced anywhere
but was left defined in `PolarisIcon.swift` (untouched file, out of scope, harmless if unused).

## FontAwesome import + rendering (duotone, not flattened)

Copied the 8 raw SVGs from `/Users/bervion/Resources/Icons/fontawesome6/duotone/` byte-for-byte
into new imagesets (renamed to the `ic_`-style `fa_snake_case` convention), **without stripping
or rewriting** the `<style>.fa-secondary{opacity:.4}</style>` / `class="fa-secondary"` markup —
mirroring exactly how `Assets.xcassets/PolarisIcons/*.svg` are stored (single-file imageset,
`preserves-vector-representation: true`, `template-rendering-intent: template`).

Verified this renders as **true duotone**, not a flattened silhouette, before committing to it:
1. `xcrun actool --compile` on a scratch catalog containing the raw `mobile-notch.svg` compiled
   cleanly with **zero warnings/errors**, producing a non-opaque (`"Opaque": false`) monochrome
   template rendition — consistent with a real two-tier alpha mask, not a flat fill.
2. `qlmanage -t` rendered the same raw SVG showing the outer phone frame at ~40% gray and the
   inner screen at full black — Apple's SVG stack (shared rendering path) genuinely honors the
   FontAwesome `<style>` opacity, it isn't dropped.
3. The real project compile (`Assets.xcassets` including the new `DeviceIcons` folder) also
   produced zero asset-catalog warnings.

Because `Image(...).renderingMode(.template)` tints by *replacing color while preserving each
pixel's original alpha*, the two FontAwesome opacity tiers survive as two opacities of the SAME
`.foregroundStyle` tint — a genuine single-hue duotone, reused through `PolarisIcon` itself
(`PolarisIcon` is a generic name+size template renderer, not literally limited to the Polaris
set — reused as-is rather than duplicating its `Image` chain). **No SF Symbol fallback was
needed**; the documented fallback path (`iphone`/`ipad`/`laptopcomputer`/… SF Symbols) was not
used.

## Device-type → icon map (`DeviceIconMapping.icon(forModel:)`)

`VaultDevice.model` comes from `UIDevice.current.model`, which on this iPhone-only app is
realistically always the literal string `"iPhone"` — the fuller table below is forward-looking
(a future Mac/iPad/Watch companion publishing its own `OwnerDevice` record), matched by
case-insensitive substring, most-specific Mac variants checked before the generic `"mac"`
fallback (order-tested in `DeviceIconMappingTests`):

| Model substring | Icon |
| --- | --- |
| `vision` | `fa_glasses` (Vision Pro) |
| `watch` | `fa_watch_apple` |
| `ipad` | `fa_tablet_screen` |
| `homepod` / `speaker` | `fa_computer_speaker` |
| `imac` | `fa_display` |
| `macbook` | `fa_laptop` |
| `mac mini` / `macmini` / `mac studio` / `macstudio` | `fa_computer_classic` |
| `mac` (generic) | `fa_laptop` |
| `iphone` / unrecognized | `fa_mobile_notch` (default — this app ships iPhone-only) |

## Tokens / colors the owner may want to adjust

1. **`ProfileBadgeTint` (new, `ProfileComponents.swift`)** — I discovered mid-build that the
   owner-suggested theme roles for the colored glyphs (`env.theme.active.success` for Family,
   `env.theme.active.iconSecondary` for device icons) **fail contrast in dark mode** when drawn
   on the spec's fixed-WHITE badge tile: those roles are tuned to invert against the theme's
   *own* background (paler in dark mode for legibility on a dark surface), but the badge tile
   stays white in both modes. Measured: `iconSecondary` dark ≈ **1.7:1** on white, `success`
   dark ≈ **2.0:1** on white — both fail the 3:1 WCAG floor for non-text UI (the glyph would
   nearly vanish in dark mode). Replaced with two **fixed** tones verified ≥4:1 on white in both
   appearances: `family = 0x1A8E5F` (~4.1:1), `device = 0x6E6E73` (~5.1:1). These are my color
   picks, not the owner's — swap the two hex values in `ProfileBadgeTint` if a different green
   or gray is wanted; the fix (fixed-not-adaptive) should stay regardless of the exact hue.
2. **Section 1 system-gray tile** (`0x8E8E93`/`0x98989D`) — chosen to match Apple's own
   `systemGray` / this codebase's existing `SettingsIconBadge` "gray" tint exactly (same values,
   not referenced directly to avoid coupling Profile to a Settings-named type), per the owner's
   "like iOS Settings system rows" cue. Not `env.theme.active.iconSecondary` — see rationale in
   the `ProfileRowTile.systemGrayTile` doc comment (same invert-in-dark-mode problem as above).
3. **White-badge hairline border width** — `0.75pt` (spec allowed "~0.5–1pt"); picked toward the
   thicker end since the owner's own concern was the light-mode white-tile blending into a
   white/near-white card.
4. **No screenshot verification was possible** — this environment has no simulator-screenshot
   tool available to me. All sizing/contrast reasoning above is computed (WCAG luminance math,
   `actool`/`qlmanage` renders), not eyeballed on-device. Recommend a quick simulator look in
   both light and dark before merging, especially the Loox brand-mark inset (`Space.s1` padding
   on a non-square 357×337 mark) and the Family/Personal Information/Payment glyph sizes
   (`sfGlyphSize = 14`, tuned by the same reasoning `SettingsIconBadge` documents but not
   independently re-verified visually).

## Devices section — inline, not pushed

`ProfileDevicesCard` (new) replaces the old "Devices" nav row: a plain `Text("Devices")`
`.sectionLabel` above a `ProfileGroupCard` of `DeviceRow`s (no icon header — the owner's spec
made a header conditional on "if it keeps one"; a text-only label was simplest and sidesteps
picking yet another icon treatment). `DevicesScreen` itself still exists, still compiles, still
works standalone (list + empty-state footnote), but is **no longer linked from Profile** since
list-only-v1 has no other actions to preserve access to (its own doc comment already said so).
Flagged in its updated header comment as a ready destination for a future "manage/revoke devices"
action rather than deleted. `ProfileDevicesCard.load()` duplicates `DevicesScreen.load()`'s
5-line publish-then-fetch sequence rather than reaching into `DeviceRegistryService` (in
`Services/Sync/`, outside this redesign's file scope) to add a shared helper — a deliberate small
DRY trade-off in favor of respecting file ownership.

## Localization

Zero new user-facing strings. "Personal Information", "Payment", "Loox", "Family", "Devices",
and the empty-state footnote are all pre-existing `Localizable.xcstrings` keys (verified EN via
source key + VI localization present for every reused string before starting). SF Symbol/asset
glyphs carry no user-facing text of their own (`.accessibilityHidden(true)`; the row's title
`Text` remains the VoiceOver label, unchanged from before).

## Compile log tail

```
ValidateEmbeddedBinary .../Vaultify.app/PlugIns/VaultifyAutoFill.appex (in target 'Vaultify' from project 'Vaultify')
ValidateEmbeddedBinary .../Vaultify.app/PlugIns/VaultifySafari.appex (in target 'Vaultify' from project 'Vaultify')
Validate /tmp/vaultify-dd/Build/Products/Debug-iphonesimulator/Vaultify.app (in target 'Vaultify' from project 'Vaultify')
PruneExplicitPrecompiledModules /tmp/vaultify-dd/Build/Intermediates.noindex/SwiftExplicitPrecompiledModules
PruneExplicitPrecompiledModules /tmp/vaultify-dd/Build/Intermediates.noindex/ExplicitPrecompiledModules
PruneExplicitPrecompiledModules /tmp/vaultify-dd/SDKExplicitPrecompiledModules
** BUILD SUCCEEDED **
```

0 errors; the only 2 warnings in the whole log are pre-existing/unrelated
(`appintentsmetadataprocessor ... no AppIntents.framework dependency found`, on the two
extension targets, present before this change). App + `VaultifyAutoFill` + `VaultifySafari` all
compiled/linked/embedded successfully in the same workspace build.

## Tests

```
Test Suite 'DeviceIconMappingTests' passed — Executed 4 tests, with 0 failures
Test Suite 'SpaceShareSafelistTests' passed — Executed 12 tests, with 0 failures
Test Suite 'Selected tests' passed — Executed 16 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
```

`SpaceShareSafelistTests` (the pre-existing, unrelated safelist edit riding along in the dirty
tree) passes unmodified — confirms my changes didn't disturb it.

---

Status: DONE
Summary: Profile hub rows now use SF Symbol tiles (Profile-only exception) for Personal Information/Payment/Family, the real Loox brand mark for Loox, and the Devices list renders inline with true-duotone FontAwesome6 device glyphs; app + AutoFill + Safari compile clean and both requested test suites pass.
Files changed:
- Vaultify/Features/Profile/ProfileComponents.swift (extended)
- Vaultify/Features/Profile/ProfileScreen.swift (extended)
- Vaultify/Features/Profile/DevicesScreen.swift (refactored to share DeviceRow)
- Vaultify/Features/Profile/DeviceIcons.swift (new)
- Vaultify/Assets.xcassets/DeviceIcons/ (new, 8 imagesets)
- VaultifyTests/DeviceIconMappingTests.swift (new)
Compile: PASS
Concerns:
- No simulator-screenshot capability in this environment — sizing/contrast is verified by computation (WCAG math, actool/QuickLook renders) and against documented precedent, not eyeballed; recommend a quick on-device look in light+dark before merge, especially the Loox mark inset and SF glyph sizes.
- `ProfileBadgeTint.family`/`.device` are MY color picks (fixed hex, not the owner's), chosen only to fix a genuine dark-mode contrast failure in the originally-suggested theme roles — owner may want different hues (see "Tokens / colors the owner may want to adjust").
- `DevicesScreen.swift` is now unreached from Profile navigation (kept, not deleted) — confirm that's the intended product decision, or tell me if a secondary entry point (e.g. a "Manage" affordance) is wanted.
