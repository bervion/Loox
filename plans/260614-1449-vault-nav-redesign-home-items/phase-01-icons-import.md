# Phase 01 — Icons Import + Constants

## Context Links
- Icon view + constants: `Vaultify/DesignSystem/PolarisIcon.swift:27` (`enum Icons`)
- Sample imageset: `Vaultify/Assets.xcassets/PolarisIcons/ic_alert_bubble.imageset/Contents.json`
- SVG source: `/Users/bervion/Resources/Icons/polaris-icons/` (535 SVGs)
- Project manifest (globbed sources, asset catalog auto-included): `Project.swift`

## Overview
- **Priority:** P1 (blocks tab icons in Phase 3, pin icons in Phase 7)
- **Status:** pending
- Import 4 missing Polaris icons (`ic_plan`, `ic_plan_filled`, `ic_pin`, `ic_pin_filled`) into the
  asset catalog as vector-PDF template imagesets, and add name constants to `enum Icons`.

## Key Insights
- All 4 SVGs exist in source (verified: `ls .../ic_plan*.svg`, `.../ic_pin*.svg` present).
- Existing imagesets use **PDF** with `preserves-vector-representation: true` +
  `template-rendering-intent: template`. Source SVGs are `viewBox="0 0 20 20"`, single-color paths
  with **no explicit fill** → inherit `currentColor`, so template tint works after PDF conversion.
- `rsvg-convert -f pdf` is installed and verified (produced a 1.3k PDF matching existing sizes).
  This avoids adding SVG imagesets (different format from the 134 existing PDFs) — lower risk, KISS.
- All other needed icons already in catalog: `ic_home(_filled)`, `ic_organization(_filled)`,
  `ic_search`, `ic_archive`, `ic_clock`, `ic_calendar`, `ic_chart_vertical_filled`, `ic_magic`
  (verified present). Only the 4 above are missing.

## Requirements
- **Functional:** 4 new template imagesets render correctly (tint to `foregroundStyle`).
- **Non-functional:** Match existing PDF format exactly; no SVG imagesets introduced; `tuist generate`
  picks them up (asset catalog is part of the globbed app sources).

## Architecture
- Data flow: SVG (source) → `rsvg-convert -f pdf` → `<name>.pdf` placed in
  `Vaultify/Assets.xcassets/PolarisIcons/<name>.imageset/` alongside a `Contents.json` copied from an
  existing imageset (same `properties` block) → `PolarisIcon(name)` renders via `.template`.

## Related Code Files
**Create (4 imagesets, each = dir + Contents.json + pdf):**
- `Vaultify/Assets.xcassets/PolarisIcons/ic_plan.imageset/{Contents.json, ic_plan.pdf}`
- `Vaultify/Assets.xcassets/PolarisIcons/ic_plan_filled.imageset/{Contents.json, ic_plan_filled.pdf}`
- `Vaultify/Assets.xcassets/PolarisIcons/ic_pin.imageset/{Contents.json, ic_pin.pdf}`
- `Vaultify/Assets.xcassets/PolarisIcons/ic_pin_filled.imageset/{Contents.json, ic_pin_filled.pdf}`

**Modify:**
- `Vaultify/DesignSystem/PolarisIcon.swift` — add to `enum Icons`:
  `plan = "ic_plan"`, `planFill = "ic_plan_filled"`, `pin = "ic_pin"`, `pinFill = "ic_pin_filled"`.
  Also add `archive = "ic_archive"`, `calendar = "ic_calendar"`, `chartFill = "ic_chart_vertical_filled"`
  constants (icons already in catalog; constants keep literals out of view code per the file's purpose).

## Implementation Steps
1. For each of the 4 icons, create the imageset dir under `PolarisIcons/`.
2. Convert: `rsvg-convert -f pdf -o <imageset>/<name>.pdf /Users/bervion/Resources/Icons/polaris-icons/<name>.svg`.
3. Write each `Contents.json` mirroring `ic_alert_bubble.imageset/Contents.json` (single PDF filename,
   same `info` + `properties` with `preserves-vector-representation` + `template-rendering-intent`).
4. Add the 4 (+3 convenience) constants to `enum Icons` in `PolarisIcon.swift`.
5. `tuist generate --no-open` then `make check` (compile app + extension).
6. Verify template tinting via DEBUG preview or by temporarily placing a `PolarisIcon(Icons.plan)`
   in a visible screen and confirming it adopts the accent/foreground color (not solid black).

## Todo List
- [ ] Create 4 imageset dirs
- [ ] rsvg-convert each SVG → PDF into its imageset
- [ ] Write 4 Contents.json (template properties)
- [ ] Add Icons constants (plan/planFill/pin/pinFill + archive/calendar/chartFill)
- [ ] `tuist generate` + `make check` green
- [ ] Verify template tint renders (not baked black)

## Success Criteria
- `make check` passes after `tuist generate`.
- The 4 icons appear in the catalog and tint as templates (verified visually or in preview).
- `Icons.plan/planFill/pin/pinFill` resolve in code.

## Risk Assessment
| Risk | L×I | Mitigation |
|---|---|---|
| PDF bakes a black fill (won't tint) | Low×Med | Verified source SVGs have no explicit fill; template-rendering-intent forces tint. Inspect render in step 6; if baked, strip fill attrs from SVG before convert. |
| `rsvg-convert` viewBox→PDF scale differs from existing icons | Low×Low | All Polaris SVGs share `0 0 20 20`; `PolarisIcon` uses `.scaledToFit()` + fixed frame, so intrinsic size is normalized at render. |
| Asset not picked up | Low×Low | Asset catalog is inside globbed `Vaultify/**`; `tuist generate` includes it. Confirm in step 5. |

## Security Considerations
None — static UI assets, no data flow.

## Next Steps
Unblocks Phase 3 (Watchtower tab icon) and Phase 7 (pin icons in rows/detail).
