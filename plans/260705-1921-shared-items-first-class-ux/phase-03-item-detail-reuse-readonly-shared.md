# Phase 03 — ItemDetailScreen read-only shared mode (V1, V2)

## Overview
Priority P1 · Status: pending · Depends: phase 01-02. The STANDARD detail screen renders shared
items; `SharedItemView` becomes dead code (deleted phase 7).

## Key insights
- `ItemDetailScreen(itemID:)` resolves via `env.repository.item(id:)` — must fall through to
  `env.sharedItems.item(id:)` for `shared::` ids (single lookup point, no route changes).
- RequestCodeModel identity MUST survive push-driven projection refreshes of the same grant
  (in-flight WAITING machine holds ephemeral keys) — models live in the projection cache
  (phase 1), the view only reads them.
- Read-only = remove mutation affordances, keep reveal/copy/TOTP UX identical.

## Related code
- Modify: `Vaultify/Features/ItemDetail/ItemDetailScreen.swift`
- Modify: field row component(s) under `Vaultify/Features/ItemDetail/` (TOTP row: inline Request
  button when `sharedOrigin != nil` && capability is askEachTime)
- Reuse: `Vaultify/Features/Sharing/RequestCodeView.swift` (`RequestCodeModel`, `ApprovedCodeView`)
- Reuse strings: safety code footer (from SharedItemView), leave-share dialog

## Implementation steps
1. Lookup fallback: `item(id:)` → repository, else projection.
2. `isShared` branch in ItemDetailScreen:
   - Hide: edit button, favorite/pin, Space pill (move), delete, rotation reminder, attachments add.
   - Toolbar: "…"-menu → Leave Share (destructive confirm — port copy from SharedItemView).
   - Header badge: "Shared with you — read only" callout (port sharedByBadge).
   - Footer: safety-code row (optional verify, port from SharedItemView).
3. Field rendering: shared values render like normal fields (reveal/copy). TOTP askEachTime
   capability → embed `RequestCodeView(model:deviceId:)` in place of the live-TOTP code view.
4. `recipientDeviceId` helper moves from SharedItemView to a shared location (projection or util).
5. Leave → dismiss + projection refresh; zoneNotFound (revoked) → graceful "owner stopped sharing"
   state (port).
6. Localization EN+VI for any new strings.

## Success criteria
- B: tap shared item anywhere → standard detail, read-only, values copyable, Request→approve→code
  round-trip works (2-device), Leave works, revoked share shows graceful state.
- Owned-item detail completely unchanged (no regression — snapshot the toolbar/menu items).
