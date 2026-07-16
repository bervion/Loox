# Device model names + Profile icon tweaks

Date: 2026-07-15
Scope: Vaultify Profile Devices list (icon-only device rows, Family icon swap, real device
marketing names)

## Summary

Implemented all three changes. Device rows now render icon-only (no badge tile), the Family
row uses the FontAwesome duotone `users` glyph on its existing white tile, and the Devices list
shows real marketing names ("iPhone 16 Pro Max", "iPad Pro 11-inch (M4)") instead of the
generic "iPhone"/"iPad" `UIDevice` returns. App + VaultifyAutoFill + VaultifySafari compile
clean; `DeviceModelNamesTests` (new, 5 tests) and `DeviceIconMappingTests` (existing, 4 tests)
pass, 0 failures.

One deviation from the literal spec, flagged for visibility per the "verified decisions" /
"threat model" rules rather than silently applied: the icon-only device tile needed a small
contrast-safety addition beyond what was asked (see "Contrast fix" below) — implemented using
an already-established codebase mechanism, not a new pattern.

## Files changed

- `VaultifyCore/Models/DeviceModelNames.swift` (new) — pure `hw.machine` identifier → marketing
  name lookup table + graceful-fallback logic. No I/O.
- `Vaultify/Services/Sync/DeviceRegistryService.swift` (modified) — added
  `hardwareIdentifier()` (uname + Simulator fallback), wired `deviceModel()`'s iOS branch
  through `DeviceModelNames`. macOS branch (`Host.current()` / literal `"Mac"`) left untouched
  — out of scope, no live caller changes it.
- `Vaultify/Features/Profile/ProfileComponents.swift` (modified) — added `ProfileTileStyle
  .plain` case (icon-only, no background); `DeviceRow` uses it + shows `device.model` (falls
  back to `device.name` if empty) as the row title.
- `Vaultify/Features/Profile/ProfileScreen.swift` (modified) — Family row's tile source swapped
  from SF Symbol `person.2.fill` to `.templateAsset("fa_users")`, same `.colored` white-tile
  style and `ProfileBadgeTint.family` tint as before.
- `Vaultify/Features/Profile/DeviceIcons.swift` (doc comment only) — updated the stale "ultimately
  `UIDevice.current.model`" note now that `deviceModel()` resolves a marketing name instead.
- `Vaultify/Assets.xcassets/fa_users.imageset/Contents.json` + `fa_users.svg` (new) — FontAwesome6
  Duotone `users.svg`, byte-identical copy from
  `/Users/bervion/Resources/Icons/fontawesome6/duotone/users.svg`.
- `VaultifyTests/DeviceModelNamesTests.swift` (new) — 5 tests.

Reused as-is (no change needed, confirmed by reading): `DeviceIconMapping.icon(forModel:)`
already resolves marketing-name strings correctly (see "DeviceIconMapping verification" below);
`DevicesScreen.swift` reuses the shared `DeviceRow`, so it inherits both changes automatically.

## Change 1 — icon-only device rows

`ProfileTileStyle.plain(ProfileGlyphSource, UInt32)` renders the glyph in the same
`Metric.badgeTile` frame with no `.background(...)`. `DeviceRow` now uses
`.plain(.templateAsset(DeviceIconMapping.icon(forModel: device.model)), ProfileBadgeTint.deviceHex)`.
Family/Loox/other nav rows are untouched (`.colored`/`.brandMark`/`.system` unchanged).

### Contrast fix (beyond literal spec — flagged, not silent)

`ProfileBadgeTint.device` (`0x6E6E73`) was documented as verified only against an
**always-white** backdrop (`ProfileRowTile.whiteBadgeBackground`'s doc comment: "these fixed
tones hold ≥4:1 against white in both appearances since the backdrop never changes"). Removing
the backdrop (the whole point of `.plain`) exposes that same fixed color to the active THEME's
own `elevatedBackground` instead, which is white in `day`/`dayClassic` but not in `night`
(`0x1C1C1E`) or `nightTinted` (`0x213040`). I computed WCAG contrast with the codebase's own
`RGBMath.contrastRatio` formula (`VaultifyCore/Theme/ColorHex.swift`):

| Theme | elevatedBackground | contrast vs 0x6E6E73 | vs 3:1 non-text floor |
|---|---|---|---|
| day / dayClassic | `0xFFFFFF` | ~5.07:1 | pass |
| night | `0x1C1C1E` | ~3.35:1 | pass (thin margin) |
| nightTinted | `0x213040` | **~2.65:1** | **fail** |

`nightTinted` genuinely fails the app's own 3:1 non-text-UI floor (the same floor
`ProfileRowTile`'s existing doc comments already hold every other badge tint to). Rather than
ship a known-failing color or silently pick a different tint than the one specified, I applied
`RGBMath.ensureContrast(_:on:floor:)` — the exact mechanism `AppTheme.swift:57` already uses for
the accent color against `elevatedBackground` — inside `ProfileRowTile`'s `.plain` case. It is
non-destructive by contract (returns the input byte-identical whenever it already clears the
floor, true for 3 of 4 themes) and only nudges the color toward black/white by the minimal
amount needed in `nightTinted`. `ProfileTileStyle.plain` and `ProfileBadgeTint.deviceHex`
therefore carry `UInt32` (not `Color`) so the raw value reaches `RGBMath` directly.

This only affects the NEW `.plain` style; `.colored`'s literal-white backdrop (Family, brand
mark) is unaffected and its existing contrast claims still hold.

## Change 2 — Family row `fa_users` icon

Imported `/Users/bervion/Resources/Icons/fontawesome6/duotone/users.svg` into
`Vaultify/Assets.xcassets/fa_users.imageset/` — same Contents.json shape as the 8 `DeviceIcons`
imagesets (`preserves-vector-representation: true`, `template-rendering-intent: "template"`,
single universal-idiom SVG), SVG copied byte-for-byte (`diff` confirmed identical). Verified the
compiled rendition via `assetutil --info` on the built `Assets.car`: `Template Mode: template`,
`Preserved Vector Representation: true`, `Opaque: false` — the last one confirms the
fa-secondary/fa-primary two-opacity duotone styling survived the asset pipeline uncollapsed,
same verification method `DeviceIcons.swift`'s doc comment describes for the existing 8 icons.

`ProfileScreen`'s Family row: `.colored(.templateAsset("fa_users"), ProfileBadgeTint.family)` —
same white-tile + hairline-border treatment and green tint as before, only the glyph source
changed.

## Change 3 — real device marketing names

**Identifier reading** (`DeviceRegistryService.hardwareIdentifier()`, iOS-only branch): reads
`hw.machine` via `uname(2)`/`utsname` (`withUnsafeBytes(of:)` → `String(cString:)`, no unsafe
pointer arithmetic beyond the standard tuple-to-C-string idiom). On Simulator, `hw.machine`
reports the HOST Mac's architecture ("arm64"/"x86_64"), so it reads
`ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]` first (set by Xcode/simctl
for every run) and only falls back to `uname` on a real device. Guarded entirely inside `#if
canImport(UIKit)` (unused/absent on the macOS build slice, which is untouched — still literal
`"Mac"` as before).

**Mapping** (`DeviceModelNames.marketingName(forIdentifier:)`, pure, no I/O, in `VaultifyCore`):
a ~150-entry table cross-checked against multiple sources (TheAppleWiki-derived gist data via
WebFetch, AppleDB, Apple Support device-identification pages, and my own knowledge), covering:
- iPhone XS (`iPhone11,2`, the oldest iOS-17-capable model) through iPhone 17 / iPhone Air /
  iPhone 17e (`iPhone18,x`) — every spec example (`iPhone17,1`→"iPhone 16 Pro",
  `iPhone17,2`→"iPhone 16 Pro Max", `iPhone17,3`→"iPhone 16", `iPhone17,4`→"iPhone 16 Plus",
  `iPhone12,3`→"iPhone 11 Pro") matches exactly.
- iPad base/mini/Air/Pro from the 6th-generation era through Pro/Air (M5, 2025).
- Apple Watch from the 1st generation through Series 11 / Ultra 3 / SE 3 (2025).
- Apple Vision Pro (`RealityDevice14,1`).
- Mac — a **modest, high-confidence** sample (MacBook Air/Pro, Mac mini, iMac, Mac Studio, one
  M2-era unified code) rather than an exhaustive table. Apple's 2023+ Mac identifiers collapsed
  into a single unified `MacXX,Y` numbering shared across unrelated product lines with no
  reliable public disambiguation source I could verify — I excluded speculative entries rather
  than ship unverified data (e.g. one source's claimed `iPad16,8-16,11 = "iPad Air (M4)"` was
  dropped: no M4 iPad Air exists in Apple's actual lineup, almost certainly a scraping
  artifact). Mac has no live caller today (task explicitly frames it as "future companions");
  anything missing there still resolves to plain "Mac" via the fallback, matching today's
  existing (pre-change) macOS behavior exactly.

**Fallback** (mandatory, never crashes/empty): family-prefix match
(iPhone/iPad/Watch/RealityDevice/iMac/MacBook/Mac/arm64/x86_64/i386 → generic name, checked
most-specific-first mirroring `DeviceIconMapping`'s own ordering) → else the raw identifier
verbatim → else (only reachable with a truly empty input string, which the real reader never
produces) the existing `appString("Unknown device")` catalog key (already localized EN+VI, so
this adds zero new user-facing strings).

**Display**: `DeviceRow`'s title is now `device.model` (falls back to `device.name` for a
legacy CloudKit record with an empty `model` field). Subtitle (last-seen / "This device")
unchanged.

### DeviceIconMapping verification

Confirmed marketing-name strings still resolve to the correct glyph through the EXISTING
`DeviceIconMapping.icon(forModel:)` substring logic — no changes needed there:
- `"iPhone 16 Pro Max"` → contains `"iphone"` → iPhone glyph (checked after
  vision/watch/ipad/homepod/imac/macbook/mac, none of which match first).
- `"iPad Pro 11-inch (M4)"` → contains `"ipad"` (checked before any "mac" branch) → iPad glyph.
- `"Apple Watch Series 11"` → contains `"watch"` → watch glyph.
- `"Apple Vision Pro"` → contains `"vision"` (first check) → Vision Pro glyph.
- `"MacBook Air (M1, 2020)"` → contains `"macbook"` → laptop glyph.
- `"Mac mini (M1, 2020)"` / `"Mac Studio (M1 Max, 2022)"` → contain `"mac mini"`/`"mac studio"`
  → desktop glyph.
- `"iMac (24-inch, M1, 2021)"` → contains `"imac"` (checked before generic "mac") → display glyph.

No adjustment to `DeviceIconMapping` was needed or made.

## Localization

No new user-facing strings. Marketing names are proper nouns (per constraint, not localized).
The one defensive fallback string reuses the existing `"Unknown device"` catalog key (already
EN+VI translated, used elsewhere in this same file for the CloudKit "missing name" case) instead
of adding a new key.

## Build

```
tuist generate --no-open   → Success
xcodebuild ... (Debug, generic/platform=iOS Simulator, CODE_SIGNING_ALLOWED=NO)
→ ** BUILD SUCCEEDED ** (app + embedded VaultifyAutoFill.appex + VaultifySafari.appex)
```
No warnings in any file this task touched (`grep -i warning` against the build log for
`DeviceModelNames|DeviceRegistryService|ProfileComponents|ProfileScreen|DeviceIcons.swift`:
zero matches).

## Tests

```
xcodebuild test ... -only-testing:VaultifyTests/DeviceModelNamesTests \
                     -only-testing:VaultifyTests/DeviceIconMappingTests
```
`Executed 9 tests, with 0 failures (0 unexpected)` — `DeviceModelNamesTests` (5, new) +
`DeviceIconMappingTests` (4, existing/untouched). `** TEST SUCCEEDED **`.

## Verification note (can't screenshot)

Reasoned through structure rather than rendering:
- Device rows: `ProfileRowTile(style: .plain(...))` → `Group`/`switch` → `.plain` case →
  glyph at `Metric.badgeTile` (30pt) frame, `RGBMath.ensureContrast`-derived tint, **no**
  `.background(...)` call in that case (confirmed by reading the case body) → renders icon-only,
  same 30pt slot as every other row so `DeviceRow`'s `VStack(alignment: .leading)` title stays
  aligned with Family/Loox/etc. rows above it in `ProfileGroupCard`.
- Family row: `.colored(.templateAsset("fa_users"), ProfileBadgeTint.family)` → `.colored` case
  body unchanged (still `whiteBadgeBackground` + green tint) → only `glyph(source)`'s resolved
  asset name changed from an SF Symbol to the new template asset, confirmed compiled
  (`assetutil` showed `fa_users` present, template mode, non-opaque).

## Unresolved / for owner awareness

1. **Contrast fix** (above) — implemented, not asked for verbatim in the brief, but the brief's
   own `ProfileBadgeTint.device` choice was verified only for a white backdrop that `.plain`
   removes. Flagging per repo convention rather than treating it as silently "done as literally
   specified."
2. Mac identifier table is intentionally thin (see Change 3) — no functional impact today (no
   live caller), but if a Mac companion ships later, the table will need real verified data for
   the unified 2023+ `MacXX,Y` codes at that time.
3. `iPad16,8`-`iPad16,11` excluded from the table after finding conflicting/implausible source
   data (a claimed "iPad Air (M4)" that doesn't match any real Apple product I'm aware of) —
   falls back to generic "iPad" if actually encountered.

Status: DONE
Summary: All three Profile/device changes implemented, verified via WCAG contrast math and
DeviceIconMapping substring tracing, and confirmed by a clean compile + passing tests.
Files changed: VaultifyCore/Models/DeviceModelNames.swift (new),
Vaultify/Services/Sync/DeviceRegistryService.swift,
Vaultify/Features/Profile/ProfileComponents.swift, Vaultify/Features/Profile/ProfileScreen.swift,
Vaultify/Features/Profile/DeviceIcons.swift (doc only),
Vaultify/Assets.xcassets/fa_users.imageset/{Contents.json,fa_users.svg} (new),
VaultifyTests/DeviceModelNamesTests.swift (new)
Compile: PASS (app + VaultifyAutoFill + VaultifySafari)
Concerns: see "Unresolved / for owner awareness" above — none block shipping.
