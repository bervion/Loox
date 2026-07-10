# Phase 3 — Home protagonist reorder + concentric + card-diet

**Tier:** T2+T1 · **Priority:** P1 · **Status:** pending · **Depends:** P0 (+P1 strings)
**Owns exclusively:** `HomeScreen.swift`, `QuickActionCard.swift`

Reverses part of the just-merged PR #79 layout — **explicitly approved**. Highest-visibility change in the pass.

## Context
- Audit DNA #1 (protagonist), #3 (concentricity), #4 (typography), #2 (card-diet).
- Current order (`HomeScreen.swift:170-207`): profileRow → quickActionsGrid → pendingShares* → approval* →
  totp* → attention* → favorites* → allItems. Credential content sits at tier 5+.
- profileRow `:329-355` (outer `Radius.lg`=20, padding `Space.s4`=16, avatar hardcoded `cornerRadius: 10` at :359,
  + hairline stroke :348-351). quickActionsGrid `:382-422` 2×2. groupedCard hairline stroke `:627-637`.
- QuickActionCard glyph badge uses `Radius.sm`=10 (`QuickActionCard.swift:101`) inset into `Radius.lg` card.
- `recentlyUsed` helper from P0 (sort by `lastUsedAt`).

## Requirements (protagonist = "find & use a credential instantly")
1. **Reorder** so live/credential content leads: TOTP scroller → Needs Attention → **Recently used** (new, from
   `recentlyUsed`) / Favorites → All items. Move profile + quick-actions BELOW the protagonist band.
2. **Shrink profile row** to a thin single-line identity strip (avatar small + name + chevron; drop the 2-line
   subtitle card weight). Keep the tap→Profile behavior and active-persona semantics (INV-R03 untouched).
3. **Compress quick actions**: from the 2×2 grid to a compact single row (or Add-prominent + secondary chips).
   2FA/Watchtower counts become secondary. Keep all 4 destinations reachable. Keep glass (control layer, valid).
4. **Concentric fixes** (P0 helper): profile avatar radius → `Radius.concentric(outer: Radius.lg, inset: Space.s4)`
   instead of hardcoded 10; QuickActionCard badge radius likewise relative to its card+inset.
5. **vaultType sweep**: any raw `.font(...)` in Home → roles (audit-flagged; most already use `vaultType`).
6. **Card-diet**: consider dropping the `groupedCard` hairline stroke (`:633-636`) and the profile-row stroke,
   letting elevation/spacing carry hierarchy. Verify light mode (surface==bg) still reads as grouped.

## Data flow
- Sections read `env.repository` (`totpItems`, `itemsNeedingAttention`, `recentlyUsed`, `favorites`, `allItems`),
  all folder-scoped by `selectedFolderId`. Reorder is view-tree only; no data/model change.
- Recently-used section renders only when `recentlyUsed(folder:limit:)` non-empty (mirror existing conditional pattern).
- Persona/Space filters, restore-on-launch, shared-items feed logic (`:66-147`) **unchanged** — only section ORDER moves.

## Files
**Edit (exclusive):** `Vaultify/Features/Home/HomeScreen.swift`, `Vaultify/Features/Home/Components/QuickActionCard.swift`
**Append strings:** `Localizable.xcstrings` ("Recently Used" section header EN+VI) — coordinate w/ P1.

## Implementation steps
1. Extract a `recentlyUsedSection` (pattern of `favoritesSection`), gated on non-empty.
2. Rebuild `scrollContent` VStack order: protagonist band first, then profile strip + compact quick-actions.
3. Rewrite `profileRow` to thin strip; keep `ProfileRoute` navigation + `personaSubtitle` (single-line or drop).
4. Compress `quickActionsGrid` layout; keep `QuickActionCard.totp/watchtower/generate` + Add menu.
5. Apply `Radius.concentric` to avatar (`:359`) and badge (`QuickActionCard.swift:101`).
6. vaultType sweep; drop non-semantic strokes; verify.
7. `make check`.

## Todo
- [ ] `recentlyUsedSection` (P0 helper)
- [ ] section reorder: protagonist band first
- [ ] profile row → thin strip (nav preserved)
- [ ] quick actions compact row (4 destinations kept)
- [ ] concentric avatar + badge radii
- [ ] Home vaultType sweep + card-diet strokes
- [ ] "Recently Used" header EN+VI
- [ ] `make check`; light+dark + Reduce Transparency verified

## Success criteria
- First credential-bearing content appears above the fold, before profile/quick-actions.
- Profile is a single thin row; quick-actions a compact row; all original destinations reachable.
- Avatar/badge radii derive from `Radius.concentric`; no hardcoded `cornerRadius: 10`.
- Persona/Space filtering and shared-feed behavior unchanged (regression check).

## Risks
| Risk | L×I | Mitigation |
|------|-----|-----------|
| Reorder regresses persona/Space filter or shared-feed visibility | M×H | ONLY move section order; leave `:66-147` logic intact; test single-Space + shares |
| Reverses PR #79 — user perception | L×M | approved explicitly; keep change reviewable, screenshot before/after |
| Dropping strokes flattens Home in light mode | M×M | verify surface vs groupedBackground contrast; keep elevation |
| Compact quick-actions hurts one-handed reach of Add | L×M | keep Add prominent/top-reachable; header "+" still present |
| Recently-used duplicates All-items visually | L×L | cap limit (~4-5); distinct header; it's use-time not edit-time |

## Rollback
Single-file revert of `HomeScreen.swift` restores PR #79 order; `QuickActionCard.swift` revert restores badge radius.

## Next
Disjoint from P2/P4/P5. Feeds P6.
