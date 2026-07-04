---
phase: 2
title: "iPad Adaptive Sidebar"
status: code-complete (iOS+macOS compile, 133 tests pass, review PASS; pending on-device iPad QA)
priority: P1
effort: "3-5d"
dependencies: [1]

<!--
Implementation (2026-07-04):
- AdaptiveRootView switches MainTabView (compact) ↔ VaultSidebarView (regular) by horizontalSizeClass.
- Shared shell concerns extracted to VaultShellBehaviors ViewModifier (toast, editor sheets, auto-lock
  timer, shake, .vaultSwitchTo* notifications, mesh) — applied by BOTH shells → iPhone byte-identical.
- 2-COLUMN NavigationSplitView (not the aspirational 3-column): detail hosts each section's existing
  self-contained NavigationStack screen; space→wrapped FolderItemsScreen, profile→wrapped ProfileScreen.
  KISS choice reuses screens + avoids double-nav (plan's own risk note).
- UIStateStore.sidebarSelection is LIVE (not persisted); seeded from selectedTab on restore; reconciled
  in VaultSidebarView.onAppear so a Stage-Manager size-class flip never strands a stale section
  (red-team #18 fix — added after code review caught the missing reconcile) + drops deleted-space selection.
- Selection ↔ selectedTab two-way sync with equality guard (no loop).
- New strings Vault/Spaces/Profile already localized EN+VI (Kho/Nhóm/Hồ sơ).
- Pending: on-device iPad QA (sidebar layout, rotation/Stage Manager, .searchable in split, sheet hosting).
-->

---

# Phase 2: iPad Adaptive Sidebar

## Overview

On regular-width devices (iPad + Mac) replace the bottom `TabView` with a `NavigationSplitView`
sidebar + content + detail. Keep the existing `MainTabView` untouched on compact iPhone. One layout
switch driven by `horizontalSizeClass`; both paths reuse the same screens and
`vaultNavigationDestinations()`.

## Requirements

- Functional: iPad shows a 3-column layout (sidebar sections + Spaces · list/content · item detail).
- Functional: iPhone keeps the current 4-tab bottom bar exactly as-is.
- Functional: Sidebar sections mirror the 4 tabs (Home, Items, Watchtower, Search) + Spaces list +
  Profile/Settings entry; selection state persists via existing `UIStateStore`.
- Non-functional: Rotation (portrait/landscape) and split-view multitasking don't break layout.
- Non-functional: `.searchable` native search still works from the Search section.

## Architecture

**Adaptive root** (new `Vaultify/Features/Main/AdaptiveRootView.swift`):
```
if horizontalSizeClass == .compact { MainTabView() }        // iPhone (unchanged)
else { VaultSidebarView() }                                 // iPad + Mac
```
`RootView` swaps `MainTabView()` → `AdaptiveRootView()` at the unlocked branch.

**`VaultSidebarView`** = `NavigationSplitView(columnVisibility:)`:
- **Sidebar column**: `List(selection:)` of `VaultTab` sections + a Spaces section (folders from
  `VaultRepository`) + footer row → Profile/Settings. Polaris icons, token-driven rows.
- **Content column**: the selected section's screen (`HomeScreen` / `ItemsScreen` /
  `WatchtowerScreen` / `SearchScreen`), each already self-contained.
- **Detail column**: item detail via a shared selected-item binding; empty-state placeholder when none.

**State**: extend `UIStateStore` with `sidebarSelection` (reuse `selectedTab` where possible) and a
`selectedItemID` for the detail column. Restoration (sealed UI state) already exists — extend it so
iPad restores sidebar + detail selection the same way tabs restore today.

**Reuse**: `vaultNavigationDestinations()` stays the single destination registry; the split view's
detail column hosts a `NavigationStack` using it, so pushes behave consistently across columns.

**Notifications**: existing `.vaultSwitchToSearch/Items/Watchtower` NotificationCenter hooks must also
drive `sidebarSelection` (extract a small `VaultSectionRouter` so both `MainTabView` and
`VaultSidebarView` react identically).

## Related Code Files

- Create: `Vaultify/Features/Main/AdaptiveRootView.swift`, `VaultSidebarView.swift`,
  `VaultSidebarList.swift`, `VaultDetailColumn.swift`, `VaultSectionRouter.swift`
- Modify: `Vaultify/App/RootView.swift` (unlocked branch → `AdaptiveRootView`)
- Modify: `Vaultify/App/UIStateStore.swift` (sidebar + detail selection, restoration)
- Modify: `Vaultify/Features/Main/VaultTabItem.swift` (`VaultTab` gains sidebar label/section metadata)
- Reuse (no change): `HomeScreen`, `ItemsScreen`, `WatchtowerScreen`, `SearchScreen`,
  `vaultNavigationDestinations()`

## Implementation Steps

1. Extract `VaultSectionRouter` from `MainTabView`'s NotificationCenter switch logic (shared selection).
2. Build `VaultSidebarList` (sections + Spaces + Profile/Settings) with `List(selection:)`, Polaris icons.
3. Build `VaultSidebarView` (`NavigationSplitView`) wiring sidebar → content → detail columns.
4. Add `AdaptiveRootView` size-class switch; wire into `RootView` unlocked branch.
5. Extend `UIStateStore` + restoration for sidebar/detail selection (sealed under Vault Key, same as tabs).
6. Verify iPad portrait/landscape/split-view; verify iPhone unchanged; verify Search `.searchable`,
   copy toast, TOTP import sheet, restored-draft sheet still present correctly in split layout.

## Success Criteria

- [ ] iPad shows sidebar + content + detail; selecting an item fills the detail column.
- [ ] iPhone bottom tab bar behavior identical to before (no visual/behavior diff).
- [ ] Section switching via in-app notifications (search/watchtower/items jumps) works in both layouts.
- [ ] UI-state restoration restores sidebar section + detail item on iPad cold launch.
- [ ] Rotation + iPad split-view multitasking render correctly; 44pt hit targets; EN + VI labels.
- [ ] Copy toast, TOTP import sheet, restored-draft sheet appear correctly over the split layout.

## Risk Assessment

- **Sheets/overlays anchored to `MainTabView`** (`CopyToastOverlay`, TOTP import, restored draft)
  must be re-hosted at the split-view root or they won't present on iPad → move to `AdaptiveRootView`.
- **Detail column double-navigation**: pushing from a list already in a `NavigationStack` inside the
  content column vs. detail column can double-present → decide list taps set detail selection (not push)
  on regular width; keep push on compact.
- **State restoration divergence** iPhone(tab) vs iPad(sidebar+detail) → keep one persisted model,
  map to both layouts, so a device that changes size class (iPad Stage Manager) stays consistent.

## Red Team Amendments (2026-07-04)

- **[Medium #18] Decouple layout-state from the once-per-launch restore gate.** `UIStateStore.restore()`
  is gated by `guard !hasRestored` (`UIStateStore.swift:77-79`) and the persisted snapshot holds only
  `selectedTab` (`UIStateStore.swift:50,62-65`) — no detail/sidebar selection. If iPad Stage Manager
  resizes to compact mid-session, `MainTabView` appears, the detail selection is lost, and because
  `hasRestored` is already true it is never reconstructed (empty detail column on resize back).
  **Fix:** derive sidebar/detail selection from a LIVE shared model on every `horizontalSizeClass`
  change, not from the one-shot cold-launch `restore()`. Add an explicit task for size-class-transition
  state continuity (distinct from cold-launch restoration). Provide a compact-layout fallback for the
  detail-column selection (e.g. push the item on the active tab's stack).
- **[Medium #20] Add `Localizable.xcstrings` to Related Code Files.** This phase introduces new
  user-facing strings (sidebar section labels, Spaces header, Profile/Settings row). Each needs an
  EN + VI entry (a missing VI is a bug). Add an "all new strings localized EN + VI" success criterion.
