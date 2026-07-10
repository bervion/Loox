# Phase 0 — Primitives (BLOCKING)

**Tier:** foundation · **Priority:** P1 · **Status:** pending · **Blocks:** P1–P5

Additive DS primitives every later phase consumes. No behavior change to existing screens.

## Context
- Audit DNA #3 (concentricity), #5 (motion), #10 (recents).
- Tokens: `Radius.swift`, `Motion.swift` (`Motion.fast`, `Animation.vault(_:reduceMotion:)`).
- Reduce Motion pattern: `@Environment(\.accessibilityReduceMotion)` (see `QuickActionCard.swift:18,142`).

## Requirements
1. `Radius.concentric(outer:inset:)` = `max(outer - inset, xs)` — additive, does NOT change the 6/10/14/20/28/pill scale.
2. `GlyphResolveText` — staggered per-character reveal of a secret string (dots → real glyphs, left→right).
   Reduce Motion → instant (no stagger). MonoLisa (`Font.vaultCode`) for secret values. Reusable by any field.
3. `CopyMorphIcon` — Polaris `ic_clipboard` → `ic_clipboard_check` crossfade + scale + `Haptics` tick.
   Reduce Motion → instant swap. NO SF Symbols.
4. `recentlyUsed(folder:limit:)` repository helper — items with non-nil `lastUsedAt`, most-recent first.
   (`allItems` sorts by `updatedAt` = edit-time, unusable for "recently used".)
5. Concentricity rule note in `docs/design-guidelines.md` (`R_inner ≈ R_outer − inset`, cite the helper).

## Data flow
- `GlyphResolveText(text:isRevealed:)` — parent toggles `isRevealed`; component animates dots→chars via a
  per-index reveal timer/`TimelineView` or a phased `withAnimation`. No secret logged; string held in-memory only.
- `CopyMorphIcon(copied:)` — parent drives `copied` Bool; component owns the crossfade.
- `recentlyUsed` reads `env.repository` `lastUsedAt`; pure, no mutation.

## Files
**Create**
- `Vaultify/DesignSystem/Components/GlyphResolveText.swift`
- `Vaultify/DesignSystem/Components/CopyMorphIcon.swift`

**Edit**
- `Vaultify/DesignSystem/Tokens/Radius.swift` (add `concentric` static func)
- `Vaultify/Data/Repositories/VaultRepository+Folders.swift` (add `recentlyUsed`)
- `docs/design-guidelines.md` (concentricity rule paragraph under the DS model section)

`tuist generate` after adding the two new files.

## Implementation steps
1. Add `static func concentric(outer:inset:) -> CGFloat` to `Radius`.
2. Build `GlyphResolveText`: input `text`, `isRevealed`, optional `font` (default `.vaultCode()`);
   staggered char reveal (~`Motion.fast` per glyph, cap total ~0.4s); Reduce Motion collapses to instant.
   Placeholder glyph = `•` matching `SpoilerText` visual.
3. Build `CopyMorphIcon`: two `PolarisIcon` layered, opacity+scale crossfade on `copied`, `Motion.vault`.
4. Add `recentlyUsed(folder:limit:)` to the folders extension (reuse `scoped(folderId)`).
5. Doc: append concentricity rule.
6. `make check`.

## Todo
- [ ] `Radius.concentric` helper
- [ ] `GlyphResolveText` component (+ Reduce Motion instant)
- [ ] `CopyMorphIcon` component (+ Reduce Motion instant)
- [ ] `recentlyUsed` repository helper
- [ ] concentricity doc note
- [ ] `tuist generate` + `make check` green

## Success criteria
- Both components compile and preview in isolation; Reduce Motion path verified.
- `Radius.concentric(20, inset: 16) == 6`; existing radius constants unchanged.
- `recentlyUsed` returns most-recent-first, excludes never-used items.

## Risks
| Risk | L×I | Mitigation |
|------|-----|-----------|
| Per-glyph stagger jank on long strings | M×L | cap total duration; reveal in fixed time-budget regardless of length |
| MonoLisa width shift dots↔chars | L×M | MonoLisa is monospaced → glyph width stable; verify with 20+ char secret |

## Rollback
Delete the two new files, revert 3 edits. Nothing else references them yet.

## Next
Unblocks P1–P5. P2 consumes `GlyphResolveText`+`CopyMorphIcon`; P3/P4 consume `recentlyUsed`+`concentric`.
