# Tutorial snapshot noise audit

2026-10-07. Read-only audit of retained images and receipts; no tests rerun, app/test source changed, or reference images replaced by this audit.

**Judgment: PASS for the narrowly scoped `precision: 0.9999` adjustment.** Both failures contain sparse text-edge raster differences, with unchanged geometry, content, alpha, and image dimensions. This establishes the nature of the difference; it does not prove which OS/font-renderer change produced it.

## Independent image measurements

Pillow/NumPy comparison of decoded RGBA arrays, all images 780 × 1400 pixels (`@2x`, 390 × 700 points):

| Case | Changed pixels / 1,092,000 | Differing RGBA bytes / 4,368,000 | Maximum channel delta | Largest 8-connected cluster | Exact byte match fraction |
|---|---:|---:|---:|---:|---:|
| Closing card, no Skip | 74 (0.006777%) | 186 | 2/255 | 3 pixels | 0.999957418 |
| Circular health-ring spotlight | 80 (0.007326%) | 202 | 2/255 | 3 pixels | 0.999953755 |

Closing: 185 changed channels differ by 1, one by 2. Spotlight: 201 differ by 1, one by 2. Neither case changes any alpha channel. All 74 closing-card differences recur at identical positions relative to the tooltip in the spotlight case (vertical translation +275 raster pixels); the six additional spotlight pixels belong to the Skip text. Visual inspection of reference, actual, and diff for both cases confirms unchanged text wrapping, trailing Next-button placement, card shape, and spotlight shape.

The current repository reference PNGs are **byte-identical to `HEAD`** and pixel-identical to the exported references. SHA-256:

- Closing: `1c3271523385a8c2967452319e4e4204f2dca696d42d45821400ccc8dc75699c`
- Spotlight: `73583fca8c452083ccfa16ffe568abcc1b7da933ec6f33f90e80a808269ed62b`

## Elimination and timeline

Times below are Asia/Ho_Chi_Minh; environment is Xcode SDK 27.0, iPhone 17 Pro simulator iOS 26.5 (23F77).

- **20:53:51:** full-suite strict-comparison failures retained in `/tmp/vaultify-ux-native-captures/manifest.json`.
- **20:56:21:** fresh isolated Tutorial suite fails both strict comparisons (`/tmp/vaultify-ux-tooltip-isolated.log:360`). Its exported actual and reference images are pixel-identical to the full-suite pair for each case. This eliminates earlier tests contaminating the rendered result.
- **20:59:49–50:** both Tutorial cases and all 12 snapshot cases pass after the precision change (`/tmp/vaultify-ux-snapshots.log:967`, `/tmp/vaultify-ux-snapshot-summary.json`: 12 passed, 0 failed, 0 skipped).

Geometry/content regression is ruled out for these retained images by the equal dimensions, sparse ≤2/255 differences, matching glyph-relative coordinates, and direct inspection. Tutorial layout, typography, spacing tokens, and reference files have no source diff. The added body-contrast theme roles are opt-in; this tooltip retains its existing `.primary`, `.secondary`, and `.tertiary` roles. A specific historical SDK rendering cause remains unproven because the original reference-rendering executable is unavailable.

## Change scope and limitation

Only `TutorialTooltipSnapshotTests.swift:36` and `:48` opt into 0.9999. `SnapshotEnvironment.swift:30` adds a parameter whose default remains 1; the other existing snapshot assertions retain exact comparison. No baseline update occurred.

The installed SnapshotTesting comparator (`Sources/SnapshotTesting/Snapshotting/UIImage.swift:140`) counts differing **RGBA bytes**, despite its public pixel terminology. The threshold permits 436 differing bytes at this size; observed counts are 186 and 202. Larger changes still fail, but a sufficiently small product change within this budget can pass. The test comment should avoid an unconditional guarantee that every geometry/content change fails. Keep this tolerance confined to these two cases and retain strict comparison elsewhere.

## Retained evidence

All original exports below are extensionless PNG files under `/tmp/vaultify-ux-native-captures/`:

| Case | Reference | Actual | Diff |
|---|---|---|---|
| Closing | `CAF5FCD1-648F-438E-B2B5-4F4331E9AED2` | `EFBCAB81-744A-4274-85CF-7B1A8702D37E` | `44DDC1F3-7B50-4B97-9A98-4191CE5A0989` |
| Spotlight | `4A063255-0C91-4116-AC5D-87D0EEB986ED` | `38B7BDC5-7A58-402C-A8E5-7F2E70EB1749` | `A67EB12B-ACD9-4D26-8C01-EB8442F66959` |

Independent isolated exports: `/tmp/vaultify-tooltip-audit-isolated/manifest.json`. Green receipt: `/tmp/vaultify-ux-snapshots-final.xcresult`.

The known unit skip is `FaviconServiceTests.testCachedFileIsWrittenWithCompleteProtection`, explicitly skipped when the simulator provides no protection class (`VaultifyTests/FaviconServiceTests.swift:260`; `/tmp/vaultify-ux-unit.log:2807`: “Data protection is not enforced on the simulator”). It does not validate physical-device file protection; this audit makes no claim about the final unit-suite outcome.

Unresolved: exact historical rendering cause; physical-device data-protection assertion remains a device-only check.
