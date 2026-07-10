# Phase 2 — Item Detail (typography · disclosure · card-diet · reveal · copy · bottom cluster)

**Tier:** T1+T2+T3 · **Priority:** P1 · **Status:** pending · **Depends:** P0 (+P1 strings)
**Owns exclusively:** `ItemDetailScreen.swift`, `DetailFieldRow.swift`, `TOTPFieldRow.swift`

All Item-Detail-surface changes bundled so these 3 files have a single owner (no parallel conflict).
Run internally in order **2a (T1) → 2b (T2) → 2c (T3)**; not parallel (same files).

## Context
- Audit DNA #2 (card disease), #4 (typography), #5 (reveal/copy motion), #6 (bottom ergonomics), #7 (disclosure).
- Current: `ItemDetailScreen.body` stacks header→sharedBadge→org→fieldsCard→passkeys→sharing→**trashCard(always)**→metadata (:59-93).
- Raw fonts: `ItemDetailScreen.swift:306` `.font(.title2.bold())`, `:307` `.font(.subheadline)`;
  `DetailFieldRow.swift:46,73,116`; `TOTPFieldRow.swift:11` `.font(.body.weight(.bold))`.
- Reveal anti-pattern: `DetailFieldRow.swift:83-93,126-133` swaps `SpoilerText`↔`Text` under `withAnimation`.
- Copy: `DetailFieldRow.swift:174-183` row flash + "Copied" text swap; `Icons.copyDone` already exists.
- trashCard always rendered (`:80`, def `:499-526`); Archive already in "…" menu (`:133-145`) → destructive x2.

### 2a — T1 (typography · OTP object · disclosure · sharedBadge flat)
1. Replace raw `.font(...)` with `vaultType` roles: title `:306` → `.vaultType(.screenTitle)` (or `.section`),
   category `:307` → `.vaultType(.subhead)`; `DetailFieldRow` label `:46` → `.vaultType(.caption)` weighted,
   strength `:116` → `.vaultType(.subhead)`. Keep the 10 roles; add none.
2. OTP typographic object: `TOTPCodeView` (`TOTPFieldRow.swift:4-21`) → `.font(.vaultCode(.title3, weight: .semibold))`,
   keep the `123 456` grouping (`format`), keep tabular. (Reverses the current SF-body choice — approved T1.)
3. Progressive disclosure: remove `trashCard` from the live-item body; add **"Move to Trash"** (destructive) to the
   "…" menu (reuses existing `confirmTrash` dialog). Trashed items KEEP the Restore/Delete card. Shared projections
   keep "Leave Share". So `trashCard(item)` at `:80` renders only for `isTrashed` or `sharedOrigin != nil`.
4. Metadata `:548-555` → single line ("Created … · Modified …").
5. sharedBadge `:406-416` → flat banner: drop the card look (no surface stroke; keep subtle tint or plain),
   use the P1 de-em-dashed string.

### 2b — T2 (card-diet · glyph reveal · copy-morph)
6. Card-diet: keep `fieldsCard` and `sharingSection` (real semantic groups). Drop non-semantic stroked wrappers
   where they add nothing (evaluate the `Radius.md` stroke overlays at `:399-402`, `:456-459`, `:540-543`).
   Prefer elevation/spacing over hairline strokes; keep one card identity for the fields group.
7. Reveal → `GlyphResolveText` (P0): replace the `SpoilerText`↔`Text` swap in `valueView`/menu-reveal so a secret
   resolves per-glyph instead of whole-field crossfade. Reduce Motion instant. `revealed` state stays the driver.
8. Copy feedback → wire `CopyMorphIcon` (P0) into the row's trailing/menu; keep the accent row flash + `Haptics`.
   Optionally show `Copied · clears in {n}s` (P1 string) when `sensitive && clipboardClearSeconds > 0`, else `Copied`.

### 2c — T3 (bottom copy cluster)
9. Bottom floating **"Copy Password"** cluster: **only** for login items **with a password**, **only when the
   password field is scrolled out of the viewport**. Not on other categories/screens. Tapping copies the password
   (same `env.clipboard.copy(sensitive:)` path) + `Haptics`. Respects safe area / clears tab bar. Reduce Motion:
   no slide, just fade. Detect viewport via a `GeometryReader`/`onScrollGeometryChange`-style visibility check on
   the password row (iOS 17-safe: preference-key bounds, not iOS 18 scroll APIs).

## Data flow
- Copy: row/cluster → `env.clipboard.copy(value, label:, sensitive:)` → `PlatformPasteboard` (auto-expire per settings).
- Trash: menu "Move to Trash" → `confirmTrash` dialog → `env.repository.moveToTrash` → `dismiss()`.
- Reveal: `revealed` Bool → `GlyphResolveText.isRevealed`; secret in-memory only.

## Files
**Edit (exclusive):** `Vaultify/Features/ItemDetail/ItemDetailScreen.swift`,
`Vaultify/Features/ItemDetail/DetailFieldRow.swift`, `Vaultify/Features/ItemDetail/TOTPFieldRow.swift`
**Append strings:** `Localizable.xcstrings` (menu "Move to Trash" if new, "Copy Password", EN+VI) — coordinate w/ P1.

## Todo
- [ ] 2a raw `.font` → `vaultType` (3 files)
- [ ] 2a OTP → `vaultCode(.title3,.semibold)` keep grouping
- [ ] 2a trash→"…" menu; live body drops trashCard; trashed/shared keep it
- [ ] 2a metadata single line
- [ ] 2a sharedBadge flat banner (P1 string)
- [ ] 2b card-diet stroke audit
- [ ] 2b reveal → `GlyphResolveText`
- [ ] 2b copy → `CopyMorphIcon` (+ honest clears-in-Ns)
- [ ] 2c bottom Copy-Password cluster (login+password+offscreen only)
- [ ] `make check` green; Reduce Motion verified

## Success criteria
- No raw `.font(...)` in the 3 files; OTP renders as a MonoLisa title3 object with `123 456` grouping.
- Live item: no trashCard in body; "Move to Trash" in "…" menu, confirm dialog intact.
- Secret reveal is per-glyph; whole-field crossfade gone. Copy shows icon morph + haptic.
- Bottom cluster appears ONLY for a login with a password when that field is off-screen; absent otherwise.

## Risks
| Risk | L×I | Mitigation |
|------|-----|-----------|
| Removing strokes flattens hierarchy in light mode (card==bg white) | M×M | keep fields-group surface distinct; verify light+dark; elevation over stroke |
| OTP MonoLisa title3 too wide on SE / large Dynamic Type | M×M | test SE + XXL; `minimumScaleFactor` or drop to `.body` if clipping |
| Bottom cluster covers content / double-CTA noise | M×M | strict visibility gate; single action; safe-area + tab-bar inset |
| Viewport detection flakey on iOS 17 | M×M | preference-key bounds (no iOS 18 API); debounce; fail-closed = hidden |
| Trash moved to menu reduces discoverability | L×M | approved (disclosure); Archive already there; confirm dialog unchanged |

## Rollback
Per-sub-phase git revert; each of 2a/2b/2c is independently revertible on the same 3 files.

## Security
Copy stays on the sensitive path (auto-expire). Reveal holds secrets in-memory only, no logging. Trash confirm intact.

## Next
Independent of P3/P4/P5 (disjoint files). Feeds P6 compile/tests.
