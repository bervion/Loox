---
date: 2026-10-08
status: verified-working-tree
branch: codex/loox-member-card-layout
scope: member-tile-layout-follow-up
---

# Member tile layout follow-up

## Summary

This bounded follow-up corrects Member tile geometry and resting fill after the
overhaul in `1f6d0a64`. Fresh native/theme checks and final compilation passed in the
working tree. It does not change the
[overhaul plan](../plan.md) acceptance count: 21/34, all five phases in progress.
Existing TestFlight 1.57.0 (96) does not contain this working-tree fix.

## Findings and decision

- Wrapped localized metrics exposed differing intrinsic tile heights in `LazyVGrid`.
  `EqualHeightTileLayout` measures every tile at the column width and applies the
  tallest intrinsic height to all tiles in a multi-column section. Accessibility
  single-column layouts keep each tile's natural height.
- Resting tiles used `surfacePressed`, making Day too dark. `surfaceInset` resolves
  to `isDark ? controlBackground : secondaryBackground`; pressed fill remains an
  interaction state. No fixed tile height, truncation or label shrinking is introduced.
- The reusable layout and token belong to the Design System. Member sections compose
  them, and [the design contract](../../../docs/design-guidelines.md) records the rule.

## Verification receipts

| Check | Result |
| --- | --- |
| Selected theme units and native probe | 42 passed, zero failed: 41 existing units plus one temporary unit-host probe |
| Theme-unit composition | AccentContrastGuard 10, BodyTextContrast 1, ThemeEngine 30; coverage includes four themes and seven accents |
| Native geometry | 19 final configurations, 33 before/after PNG receipts; multi-column maximum height spread about 4.3e-14pt (effectively zero), previously 18–40pt |
| Accessibility layout | Accessibility3 uses one column with natural heights |
| Frame bounds and hit area | All six real Button/NavigationLink tiles in a NavigationStack are in bounds and at least 44pt |
| RTL | First tile x=221pt, second x=32pt after removing manual double mirroring |
| Resting fills and supporting text | Light F2F2F6, dark 2C2C2E; secondary-body contrast 5.699:1 and 8.275:1 |
| Visual review | Root inspected VI 430pt light/dark and 375pt Accessibility3; uniform backgrounds and unclipped labels |
| Regeneration after probe removal | Tuist passed |
| Final generic Simulator compilation | Exit 0; app and embedded extensions passed after regeneration and probe removal |

Receipts: `/tmp/vaultify-member-tile-native-final-261008.log` and
`/tmp/vaultify-member-tile-native-final-261008.xcresult`,
`/tmp/vaultify-member-tile-renders-261008/receipts.json`,
`/tmp/vaultify-member-tile-final-generation.log`, and
`/tmp/vaultify-member-tile-final-compile-261008.log`.

Native configurations include widths 375/430/440pt, EN/VI/JA, light/dark, xLarge,
Accessibility3, regular-width 820/1180pt, increased-contrast UIKit traits and RTL.
This is a targeted fixture matrix, not every Cartesian combination. The temporary
probe was removed from the repository. These checks did not run snapshot/UI suites
or alter CI. Solid fills and unchanged motion were reviewed statically; Reduce Motion
and Reduce Transparency were not overridden at runtime. Localization/catalog unchanged.

The subsequent copy request shortens the Share Links metric to `%lld links` / `%lld
liên kết` / `%lld件のリンク` (EN/VI/JA). Catalog JSON, translations and the numeric
placeholder pass validation. The native images above precede this copy-only change.
The subsequent visual request increases Member tile rounding from the 6pt concentric
floor to the existing `Radius.md` 14pt token. Swift syntax and whitespace checks pass;
the native images above also precede this radius-only change.

## Unresolved acceptance

This bounded follow-up is verified in the working tree. The earlier uploaded binary
does not contain it. Physical and full runtime accessibility acceptance remain open.
The parent plan's 21/34 acceptance count, five in-progress phases and broader mail,
Browser, Family and physical-device gates remain unchanged.
