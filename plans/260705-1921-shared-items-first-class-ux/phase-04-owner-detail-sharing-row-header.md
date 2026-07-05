# Phase 04 — Owner detail: sharing section + single header share button (V4, V5)

## Overview
Priority P2 · Status: pending · Independent of phases 1-3 (owner side).

## Current state (scouted)
`ItemDetailScreen.swift:51-65` — header has a `ShareLink` (shares website URL text) AND
"Share Access…" inside the "…" menu. User verdict V5: ONE share button = capability sharing.

## Implementation steps
1. Header: the share icon button now presents `ShareAccessSheet` directly
   (`showShareAccess = true`). Remove the "Share Access…" menu entry.
2. Website-URL `ShareLink` moves INTO the "…" menu as "Share Website Link" (utility, not deleted —
   it shares non-secret URL text; if item has no URL field, omit).
3. "Sharing" section in detail body (only when `env.sharingStore.shares(forItem:)` non-empty):
   - One row per recipient: email label + status (Active/Pending) + chevron.
   - Tap → `ShareAccessSheet` (existing manage/revoke lives there).
   - Row copy: "Đang chia sẻ với %@" pattern; count header "Sharing with N".
4. Shared-badge parity: owner's OWN item rows could show a subtle "shared" indicator when the
   item has active shares (optional; do it — same badge component as phase 2, different tint).
5. Localization EN+VI.

## Success criteria
- One share button in header → capability sheet; URL share reachable via menu.
- Detail shows recipients + status; tap manages; revoke from sheet reflects in section.
- Items never shared: zero UI change.
