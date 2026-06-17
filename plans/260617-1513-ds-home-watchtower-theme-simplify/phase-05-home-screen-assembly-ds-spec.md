---
phase: 5
title: "Home screen assembly (DS spec)"
status: pending
priority: P2
effort: "5-7h"
dependencies: [3, 4]
---

# Phase 5: Home screen assembly (DS spec)

## Overview

Recompose `HomeScreen` to the DS UI kit Home (`Design System/ui_kits/ios-app/app.jsx:110-195`):
folder switcher header → search → quick actions → TOTP quick view → "Cần chú ý" → "Yêu thích" →
"Tất cả mục". Retire the old personalized-sections model (Pinned/Recent/Frequent + Customize Home);
**keep the data** (`pinned`/`favorite`/`useCount`) — `pinned` just sorts to the top of "Tất cả".

## Requirements

- Functional: header folder switcher filters the whole screen; quick actions open Add/Generator/
  TOTP-list/Watchtower; TOTP quick view shows items with a TOTP field; "Cần chú ý" shows
  rotation+weak (max ~4); favorites + all-items grouped lists; empty state when vault empty.
- Non-functional: token-driven, localized, 96px/tab-bar bottom inset, flat themed bg.

## Key Insights

- DS Home merges some surfaces: it has its own search **entry** (tap → Search tab/sheet) and a full
  "Tất cả mục" list. "Tất cả" stays on Home per "bám spec tối đa" (Open Q acknowledged — duplicates the
  Items tab's content but matches spec).
- "Cần chú ý" = `VaultRepository.itemsNeedingAttention()` (Phase 3) — **not** a new rotation surface.
- Folder filter = DS "space" filter; default "Tất cả".

## Architecture

`HomeScreen` holds `selectedFolder` state → repo queries filtered by folder → sections built from
filtered set. Sections render only when non-empty.

## Related Code Files

- Rewrite: `Vaultify/Features/Home/HomeScreen.swift` — compose header + search + quick actions +
  sections in DS order; folder filter state.
- Modify/retire: `Vaultify/Features/Home/HomeSection.swift` — drop the old section enum (pinned/
  recentlyCreated/frequentlyUsed/recentlyUsed/recentlyModified) or repurpose for the 3 DS sections
  (attention/favorites/all).
- Retire (Open Q4): `Vaultify/Features/Home/CustomizeHomeScreen.swift` + `UtilitiesSection.swift`
  (Generator now a quick action). Remove `homeShowRecentlyUsed/Modified` settings + the Customize nav.
- Modify: `Vaultify/Data/Repositories/VaultRepository.swift` — `favorites(folder:)`, `allItems(folder:sortedPinnedFirst:)`, `totpItems(folder:)`, reuse `itemsNeedingAttention(folder:)`.
- Reuse: Phase-4 components (HomeHeaderBar, QuickActionTile, TotpCardView, AttentionCell) + existing item row.

## Validation Session 1 updates
<!-- Updated: Validation Session 1 - confirm retire Customize Home -->

- **Confirmed: retire Customize Home.** Delete `CustomizeHomeScreen.swift` + `UtilitiesSection.swift`
  + the `homeShowRecentlyUsed/Modified` settings + the Customize nav entry (Home layout fixed per DS).
  Open Q4 resolved — this is no longer conditional.

## Implementation Steps

1. Repo queries: folder-scoped favorites / all (pinned-first) / totp / attention.
2. `HomeScreen` layout, top→bottom:
   - `HomeHeaderBar` (folder switcher + Add + Settings).
   - Search entry button → opens Search.
   - Quick actions row: Add / Tạo mật khẩu (Generator) / Mã 2FA (TOTP list) / Giám sát (Watchtower tab).
   - "Mã xác thực" horizontal `TotpCardView` scroller (if `totpItems` non-empty) + "Xem tất cả".
   - "Cần chú ý · N" grouped `AttentionCell` list (max 4).
   - "Yêu thích" grouped list (if any).
   - "Tất cả · N" grouped list (pinned first) + "Sắp xếp".
   - Empty state when vault empty.
3. Wire folder switcher to re-filter; persist last-selected folder (optional).
4. Remove Customize Home + optional-section settings (Open Q4); delete dead `HomeSection` cases.
5. `tuist generate --no-open` (files added/removed) → compile; manual pass on a seeded vault.

## Todo List

- [ ] Repo folder-scoped queries (fav/all/totp/attention)
- [ ] HomeScreen composed in DS order with folder filter
- [ ] Quick actions wired (Add/Generator/TOTP/Watchtower)
- [ ] TOTP quick view + "Cần chú ý" + Yêu thích + Tất cả
- [ ] Old sections + Customize Home retired (data kept)
- [ ] Empty state; `make check` passes

## Success Criteria

- [ ] Home matches the DS kit order/affordances; folder switcher filters all sections.
- [ ] "Cần chú ý" reflects rotation+weak; TOTP quick view copies codes.
- [ ] `pinned`/`favorite`/`useCount` data intact (no migration/data loss); flat themed bg + 96px inset.

## Risk Assessment

- **"Tất cả mục" duplicates the Items tab** — accepted per user spec choice; keep one shared row view.
- **Retiring Customize Home** removes a shipped surface → gated by Open Q4; if user wants it kept,
  re-add as a thin toggle. Don't silently drop without confirming.
- Folder picker presentation from Home header (sheet vs push) — verify nav.

## Security Considerations

TOTP on Home increases code exposure surface — respect lock-on-background; codes never persisted.
