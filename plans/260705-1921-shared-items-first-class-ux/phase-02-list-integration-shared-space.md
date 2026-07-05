# Phase 02 — List integration + Shared-with-Me space (V1, V3)

## Overview
Priority P1 · Status: pending · Depends: phase 01. Shared items appear in B's normal lists;
"Được chia sẻ với tôi" becomes a pure Space; Home row removed.

## Related code
- Modify: `Vaultify/Features/Home/HomeScreen.swift` — REMOVE `sharedWithMeRow` + its gating;
  merge `env.sharedItems.items` into the All-items section data source (badge via row, phase 3).
- Modify: `Vaultify/Features/Items/ItemsScreen.swift` — Shared-with-Me space row stays (gate:
  `approvalModeEnabled || !env.sharedItems.items.isEmpty`), now with live `count:`.
- Modify: `Vaultify/Features/Search/SearchScreen.swift` — include shared items in results.
- Modify: `Vaultify/Features/Sharing/SharedWithMeScreen.swift` — REWRITE as a standard item list
  (VaultItemRow) over `env.sharedItems.items`; zone-list UI + SharedZoneRoute destinations die
  in phase 7 after detail parity.
- Modify: `Vaultify/Features/Main/VaultShellBehaviors.swift` — add
  `.task(id: env.approvalCoordinator.recipientChangeCounter) { await env.sharedItems.refresh… }`
  + foreground refresh (one trigger set, mirrors invite reconcile pattern).
- Rows: `VaultItemRow` gains a small "Shared" badge when `item.sharedOrigin != nil`
  (Polaris icon + tint; no layout fork).

## Implementation steps
1. Projection refresh triggers in shell behaviors (unlock, foreground, recipientChangeCounter).
2. VaultItemRow badge (shared) — reuse FolderBadge sizing conventions, Polaris `share` icon.
3. Home: remove row; merge shared items into All items (sorted with owned; favorites/pin
   unavailable for shared — they simply never appear there).
4. ItemsScreen: space row count = projection count; navigation → SharedWithMeScreen (list).
5. SearchScreen merge + badge.
6. Localization sweep EN+VI for new strings ("Shared", space title unchanged).

## Success criteria
- B sees shared item in Home All-items, Items→Shared-with-Me space, Search — tap opens detail
  (phase 3 read-only).
- No Home row anymore; space hidden for users who never shared/received.
- Owned-only surfaces (Watchtower counts, AutoFill, export) show ZERO shared items — assert in tests.
