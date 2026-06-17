---
phase: 4
title: Home DS component library
status: completed
priority: P2
effort: 4-6h
dependencies:
  - 1
---

# Phase 4: Home DS component library

## Overview

Build the SwiftUI components Home needs to match the DS UI kit, all **token-driven**
(Space/Radius/Metric/VaultType/ThemeRole — never hardcoded). Reuse existing shared DS components
(Card/Row/IconTile/Badge/SectionHeader from the standardization work) where present; only create the
genuinely new pieces below. No screen assembly here (Phase 5).

## Requirements

- Functional: components render with live TOTP, theme colors, and 44pt hit targets.
- Non-functional: each component ≤ ~150 LoC, Polaris icons only, localized labels, Reduce-Motion safe.

## Key Insights

- DS contracts to match exactly: `QuickAction`, `TotpCard`, `TotpRing`, `AttentionCell`, folder
  switcher header (`kit-components.jsx:259-320`, `app.jsx:89-152`).
- Live codes already exist via `Vaultify/Services/TOTPGenerator.swift` — wrap it, don't reimplement.
- "Space switcher" → **Folder switcher**: reuse `Vaultify/Features/Folders/FolderPickerSheet.swift`
  + `FolderBadge`/`CuratedFolderIcons` for the dot/name/icon.

## Architecture

Reusable views under `Vaultify/Features/Home/Components/`, composed by `HomeScreen` (Phase 5).
TOTP card/ring observe a 1s timer; pause when off-screen.

## Related Code Files

- Create: `Vaultify/Features/Home/Components/QuickActionTile.swift` — 54pt tile (Radius.md), tint 14% bg, icon 24, caption label (VaultType.caption, text-secondary). Actions: Add (accent), Generate (teal), 2FA (purple), Watchtower (green).
- Create: `Vaultify/Features/Home/Components/TotpRingView.swift` — progress ring + remaining secs; warning tint ≤5s; reuse mono font.
- Create: `Vaultify/Features/Home/Components/TotpCardView.swift` — 158pt card, surface-base, Radius.md, hairline; IconTile(26) + TotpRing + mono code (Font.vaultMono ~23) + name; tap = copy + "Đã chép" flash.
- Create: `Vaultify/Features/Home/Components/AttentionCell.swift` — IconTile + name + reason row (icon+label, destructive/warning from `RotationStatus`) + "Đổi" button (primary if destructive else secondary).
- Create: `Vaultify/Features/Home/Components/HomeHeaderBar.swift` — folder dot + folder name (VaultType.screenTitle) + chevron.down (opens FolderPickerSheet) + Add + Settings icon buttons.
- Read for parity/reuse: `Vaultify/DesignSystem/Components/ThemedComponents.swift`, shared `Card`/`Row`/`IconTile`/`Badge`, `Vaultify/DesignSystem/Tokens/*`, `Typography.swift`.

## Implementation Steps

1. Audit existing shared components (Card/Row/IconTile/Badge/SectionHeader) — list what to reuse vs
   build. Do NOT duplicate an existing primitive.
2. `QuickActionTile` — DS metrics via `Space`/`Radius`/`Metric`; per-action tint (decorative, like item
   favicon tints — allowed). Localized labels.
3. `TotpRingView` + `TotpCardView` — bind to `TOTPGenerator`; 1s tick; copy on tap with haptic + flash;
   Reduce-Motion → no ring animation, just numeric countdown.
4. `AttentionCell` — map `RotationStatus`/weak → icon + tone + label; "Đổi" opens editor.
5. `HomeHeaderBar` — folder switcher via `FolderPickerSheet`; "Tất cả" state when no folder filter.
6. SwiftUI previews (light+dark) for each; `tuist generate --no-open` → compile.

## Todo List

- [ ] Reuse audit (shared primitives) done
- [ ] QuickActionTile (token-driven, 4 actions)
- [ ] TotpRingView + TotpCardView (live, copy, RM-safe)
- [ ] AttentionCell ("Đổi" → editor)
- [ ] HomeHeaderBar (folder switcher + Add + Settings)
- [ ] Previews compile light/dark; `make check` passes

## Success Criteria

- [ ] Components visually match the DS kit at default scale + SE/Pro Max scale.
- [ ] TOTP codes tick + copy correctly; ring warns ≤5s.
- [ ] No `Icons.*`/SF Symbols, no hardcoded radii/padding/font, all strings localized.

## Risk Assessment

- **Timer churn** from many TOTP cards → single shared tick or throttle; pause off-screen.
- **Folder picker reuse** may assume a navigation context — verify it presents as a sheet from Home.

## Security Considerations

TOTP codes are sensitive — never log; clear copied-state flash quickly; respect existing clipboard
auto-clear behavior if present.
