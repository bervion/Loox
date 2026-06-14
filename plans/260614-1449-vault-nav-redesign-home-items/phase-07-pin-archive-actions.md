# Phase 07 — Pin / Archive Actions (rows + detail)

## Context Links
- Row + swipe actions: `Vaultify/Features/Vault/VaultItemRowLink.swift` (trash/favorite swipes)
- Row content (badges): `Vaultify/Features/Vault/VaultItemRow.swift` (favorite star at `:35-38`)
- Detail toolbar/favorite: `Vaultify/Features/ItemDetail/ItemDetailScreen.swift:36` (toolbar),
  `:44` (moveToTrash), `:73-75` (favorite toggle button), `:13` (`item` lookup from `items`)
- Repo mutators (Phase 2): `togglePin`, `archive`, `unarchive`
- Pin icons (Phase 1): `Icons.pin`, `Icons.pinFill`; archive icon `Icons.archive`

## Overview
- **Priority:** P2
- **Status:** pending
- **Depends:** 2 (mutators), 6 (ArchiveScreen so archived items have a destination).
- Add **Pin/Unpin** and **Archive** actions to item rows (swipe + context menu) and to ItemDetail
  (toolbar/menu); detail reflects pin + archive state. Fix ItemDetail's item lookup so an item opened
  from ArchiveScreen (archived → excluded from `items`) still resolves.

## Key Insights
- `VaultItemRowLink` already wires `.swipeActions` for trash (trailing) + favorite (leading) — add pin
  to the leading group and archive to the trailing group, OR move secondary actions into a
  `.contextMenu` to avoid swipe overload. **Recommend:** keep favorite (leading) + trash (trailing)
  swipes as-is; add **pin + archive to a `.contextMenu`** on the row (less crowded, scales). Optionally
  also a pin leading-swipe (common gesture). Confirm gesture set — see Open Q.
- `VaultItemRow` shows a favorite star (`:35`). Add a **pin indicator** (small `Icons.pinFill`) next to
  it when `item.pinned` so the Pinned state is visible in lists. Keep it subtle (like the star).
- ItemDetail looks up `item` via `env.repository.items.first { $0.id == itemID }` (`:13`). After Phase 2,
  archived items aren't in `items` → an item opened from ArchiveScreen would be nil. **Fix:** look up
  across live + archived (e.g. `(items + archived).first { $0.id == itemID }`) or add a repo
  `item(id:)` accessor that searches both. **Add `VaultRepository.item(id:)`** (searches items + archived
  + optionally trashed) and use it in ItemDetail (DRY, also helps any future caller).
- Archiving from detail should pop back (like `moveToTrash` does `dismiss()` at `:44`) since the item
  leaves the current surface. Unarchive (from ArchiveScreen-opened detail) stays.

## Requirements
**Functional:**
- Row context menu (and/or swipe): Pin/Unpin (`togglePin`), Archive (`archive`).
- ArchiveScreen rows: Unarchive (`unarchive`) — landed in Phase 6; ensure consistency here.
- Detail: pin toggle (toolbar button or menu) reflecting `item.pinned`; Archive action (menu) that
  archives + dismisses; if item is archived (opened from Archive), show Unarchive instead.
- Pin indicator in `VaultItemRow` when pinned.
- ItemDetail resolves items from live + archived (so Archive-opened detail works).

**Non-functional:** localized action labels EN+VI; Polaris icons (pin/pinFill/archive); reuse repo
mutators; no re-seal (Phase 2 guarantees column-only).

## Architecture
**Data flow:** user taps Pin/Archive on a row or in detail → `env.repository.togglePin(item)` /
`archive(item)` / `unarchive(item)` → repo column-only mutate → `reload()` → `@Observable` refresh →
Pinned/Frequently-Used/Items lists + ArchiveScreen update. Archive removes the item from `items` → it
disappears from Home/Items/Search and appears in ArchiveScreen.
- `VaultItemRowLink` gains a `.contextMenu` with Pin + Archive buttons (icons + localized labels).
- `VaultItemRow` gains a conditional pin glyph.
- `ItemDetailScreen` gains pin + archive controls and switches its lookup to `repository.item(id:)`.

## Related Code Files
**Modify:**
- `Vaultify/Features/Vault/VaultItemRowLink.swift` — add `.contextMenu { Pin; Archive }` (and optional
  pin leading-swipe). Buttons call `togglePin`/`archive`.
- `Vaultify/Features/Vault/VaultItemRow.swift` — show `Icons.pinFill` (small, tinted) when `item.pinned`,
  beside the favorite star.
- `Vaultify/Features/ItemDetail/ItemDetailScreen.swift` — (a) lookup via `repository.item(id:)`;
  (b) add pin toggle control (mirror favorite at `:73-75`); (c) add Archive/Unarchive action (menu or
  toolbar), archive → `dismiss()`.
- `Vaultify/Data/Repositories/VaultRepository.swift` — add `func item(id:) -> VaultItem?` searching
  `items` then `archived` (then `trashed` if a trashed-detail path exists).
- `Vaultify/Features/Items/ArchiveScreen.swift` — confirm Unarchive action present (Phase 6); align
  labels/icons with this phase.

## Implementation Steps
1. Add `VaultRepository.item(id:)` (live + archived lookup).
2. ItemDetail: switch lookup to `item(id:)`; add pin toggle + Archive/Unarchive action; archive dismisses.
3. VaultItemRow: conditional pin glyph when `pinned`.
4. VaultItemRowLink: `.contextMenu` with Pin/Unpin + Archive (and optional pin swipe).
5. Verify ArchiveScreen Unarchive consistent.
6. `tuist generate` + `make check` green.

## Todo List
- [ ] VaultRepository.item(id:) (live + archived)
- [ ] ItemDetail: item(id:) lookup + pin toggle + archive/unarchive (+dismiss on archive)
- [ ] VaultItemRow: pin indicator when pinned
- [ ] VaultItemRowLink: context menu Pin/Archive (+ optional pin swipe)
- [ ] ArchiveScreen Unarchive consistency
- [ ] `make check` green

## Success Criteria
- Pin from a row/detail → item appears in Home "Pinned" + shows pin glyph; unpin reverses.
- Archive from a row/detail → item leaves Home/Items/Search, appears in ArchiveScreen; detail dismisses.
- Unarchive → item returns to normal surfaces.
- Detail opened from ArchiveScreen renders (lookup includes archived).
- `make check` green.

## Risk Assessment
| Risk | L×I | Mitigation |
|---|---|---|
| Archive-opened detail is nil (item not in `items`) | High×High | `repository.item(id:)` searches archived too; ItemDetail uses it. This is the key correctness fix — trace before shipping. |
| Swipe-action overload (4 swipes) hurts UX | Med×Low | Put Pin/Archive in `.contextMenu`; keep only favorite+trash swipes (+ optional pin swipe). |
| Archiving doesn't pop detail → stale view of a now-archived item | Med×Med | Mirror `moveToTrash` pattern: `dismiss()` after archive (verified at `:44`). |
| Pin glyph clutters rows | Low×Low | Subtle small glyph like the existing star; only when pinned. |
| Context-menu actions on Archive/Trash rows offer wrong verbs | Low×Med | Conditional menu: archived rows → Unarchive; trashed rows already have restore/delete (TrashScreen). |

## Security Considerations
- Pin/archive are metadata toggles (Phase 2 columns) — no secret access, no re-seal. ItemDetail already
  gates secret reveal behind its own protections; adding pin/archive controls doesn't change that.

## Next Steps
Phase 8 localizes the new action labels. Phase 9 tests togglePin/archive/unarchive + item(id:) lookup.
