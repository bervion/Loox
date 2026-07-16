# Search X dismiss routes back to previous tab

Date: 2026-07-15
Status: DONE_WITH_CONCERNS (compiles clean; iOS 26 device behavior unverifiable headless — see Concerns)

## Files changed

- `Vaultify/App/UIStateStore.swift` — added `var previousTab: VaultTab = .home`, ephemeral (not in on-disk `Snapshot`), the tab a search dismiss routes back to.
- `Vaultify/Features/Main/MainTabView.swift` — added `.onChange(of: uiState.selectedTab)` on `body` that records `previousTab = oldTab` whenever the tab moves TO `.search` FROM something else.
- `Vaultify/Features/Search/SearchScreen.swift` — added `@State hasPresentedThisEntry` (reset in `handleEntry()`), a new `.onChange(of: searchPresented)` wired to a new `handleSearchPresentedChange(_:)` that marks presentation and, on a genuine dismiss, sets `uiState.selectedTab = uiState.previousTab`.

## State-flow reasoning

**Recording `previousTab` (`MainTabView`).** A single `.onChange(of: uiState.selectedTab)` sits on `MainTabView.body`'s `shell`, which is mounted for the entire lifetime of the compact unlocked session (it's the root view hosted by `VaultUINavShell`'s `UINavigationController`, per `AdaptiveRootView`). SwiftUI's `.onChange(of:)` fires on any change to the observed value regardless of which code path wrote it, so this one handler reliably catches every `selectedTab` mutation — the native `TabView` selection binding, the pre-26 `LegacyChipTabBar`, and the notification-driven jumps in `VaultShellBehaviors` (`.vaultSwitchToSearch` etc.) — without needing a hook at each call site. The condition `newTab == .search && oldTab != .search` records `previousTab` only on the way IN to Search from a genuinely different tab.

**Detecting a dismiss and routing back (`SearchScreen`).** `SearchScreen` already binds `searchPresented` to `.searchable(isPresented:)`; the native role:.search X (iOS 26) and the classic Cancel button (pre-26, since `.searchable` is unconditional in this screen) both drive that same binding to `false`. The new `handleSearchPresentedChange(_:)`:
- `presented == true` → `hasPresentedThisEntry = true` (search genuinely showed this entry).
- `presented == false` → only route back if `hasPresentedThisEntry` is true AND `uiState.selectedTab == .search`, then reset the flag and set `uiState.selectedTab = uiState.previousTab`.

`hasPresentedThisEntry` is reset to `false` at the top of `handleEntry()` (called from `.onAppear`, which per the existing doc comment "fires once per tab entry"), so every fresh entry into Search starts the gate closed.

## Race-guard explanation (why the initial pre-focus `false` can't misfire)

`searchPresented` starts at `false` (its `@State` default) and stays there through the entire deferred-focus window: `requestSearchFocus()` only flips it to `true` inside a `Task` after a 400ms (cold) / 150ms (warm) sleep. Two facts combine to make this safe:

1. **SwiftUI's `.onChange(of:)` never fires for a value's initial/unchanged state** — it only fires on an actual transition. Since `searchPresented` sits at its default `false` from view creation through the whole focus-request delay, `.onChange(of: searchPresented)` simply does not run during that window; there is no "false" event to misinterpret as a dismiss.
2. **`hasPresentedThisEntry` is the belt-and-suspenders gate on the eventual real transitions.** It's `false` from `handleEntry()`'s reset until the first genuine `searchPresented → true` (set by `requestSearchFocus()`'s Task, or a native tab tap which focuses instantly on iOS 18+). Only AFTER that first `true` does a later `false` count as a dismiss. So even if some future code path fired `.onChange` spuriously at `false` before ever going `true`, the `hasPresentedThisEntry` check would still block routing.

Net effect: the very first time `searchPresented` becomes `false` after entering the tab is necessarily preceded by a `true` (there is no code path that sets it `false` without it first being `true`, other than the untouched initial state, which never triggers `onChange` at all) — so the gate can only ever open after a real presentation.

**Second guard — `uiState.selectedTab == .search`.** If the user leaves Search by tapping a different tab directly (not the X), by the time our `searchPresented` false-transition (if the platform also collapses search as a side effect of the tab switch) is observed, `selectedTab` may already read the newly tapped tab. The guard skips routing in that case so an explicit tap is never overridden by a stale `previousTab` route. Worst case if event ordering were reversed (collapse observed before the tab-selection state settles) is a same-frame `previousTab` write immediately superseded by the real tap's `selectedTab` value — no persisted incorrect state, at most a same-transaction flicker. This ordering nuance is the one thing that needs the on-device check below.

**No feedback loop.** Routing back does `uiState.selectedTab = uiState.previousTab` (e.g. `.home`). This retriggers `MainTabView`'s onChange with `newTab != .search`, so the `if newTab == .search` branch is skipped — `previousTab` is never clobbered by the very navigation it caused.

## Re-entry correctness (Home vs. another tab)

- Home → Search: `MainTabView` onChange sees `oldTab = .home, newTab = .search` → `previousTab = .home`. Dismiss → back to Home.
- Items → Search: `oldTab = .items` → `previousTab = .items`. Dismiss → back to Items.
- Search → Search is never observed (tapping the already-selected tab doesn't change `selectedTab`), so `previousTab` is never overwritten mid-session, including by the routing-back write itself (see loop note above).
- A cold app-restore landing directly on the Search tab (persisted `selectedTab`) never runs the "moved TO `.search` FROM another tab" transition, so `previousTab` keeps its default `.home` — a reasonable fallback since there's no real "previous tab" for that session yet.

## Compile

`tuist generate --no-open` then the standard workspace `xcodebuild` (Debug, generic iOS Simulator, `CODE_SIGNING_ALLOWED=NO`) — single scheme build embeds all three targets (`VaultifyAutoFill.appex` and `VaultifySafari.appex` are explicit dependencies of `Vaultify`, confirmed in the log). Zero `error:` lines; log ends:

```
ValidateEmbeddedBinary .../Vaultify.app/PlugIns/VaultifySafari.appex (in target 'Vaultify' from project 'Vaultify')
ValidateEmbeddedBinary .../Vaultify.app/PlugIns/VaultifyAutoFill.appex (in target 'Vaultify' from project 'Vaultify')
Validate .../Vaultify.app (in target 'Vaultify' from project 'Vaultify')
PruneExplicitPrecompiledModules ...
** BUILD SUCCEEDED **
```

Full log: `/tmp/vaultify-xc.log` (1954 lines).

## On-device test steps (iOS 26 — cannot be verified headless)

1. **Home → Search → X → Home.** From Home, tap the Search tab. Search field auto-focuses. Tap the native X (dismiss). Expect: lands back on Home, no leftover "search tab but not searching" state, no visible content jump beyond the normal collapse animation.
2. **Home → Search → type → X → Home.** Same as above but type a query first (so results render), then tap X. Expect: still routes to Home (typing shouldn't change the destination).
3. **Items → Search → X → Items.** From Items, tap the Search tab. Tap X. Expect: lands back on Items (confirms `previousTab` tracks the actual entry tab, not a hardcoded Home).
4. **Regression: auto-focus still works.** Re-enter Search from Home and from Items — keyboard/field should still auto-present as today (unchanged behavior, only the dismiss path is new).
5. **Regression: direct tab tap away from Search (no X).** From Search (presented), tap Home directly (not X). Expect: lands on Home (as tapped) — verifies the `selectedTab == .search` guard doesn't fight an explicit tap, and no double-navigation/flicker.
6. **Home "See all" browse path.** Home → "See all" for a Space → Search opens in browse mode (no auto-keyboard, per `suppressFocus`) → tap X. Expect: still routes back to Home (browse entry is still an entry from Home), and the existing browse-mode behavior (scope seeding, no auto-keyboard) is unaffected.

## Concerns

- Everything here rides on the empirical assumption that the native `Tab(role: .search)` X button on iOS 26 actually drives the `.searchable(isPresented:)` binding to `false` (rather than only clearing text, or not touching the binding at all). I could not verify this headless per the task's own constraint — flagging per the "STOP and report BLOCKED" instruction would have been premature since there's no way to observe the binding's real behavior without a device/simulator UI interaction, so I implemented the mechanism as specified and am surfacing this as the one on-device-only unknown rather than blocking. If step 1 above shows the X does nothing (no route-back), the binding assumption is wrong and the fix needs a different signal (worth an `@kongming` consult on `role: .search` internals if that's the case).
- The same `SearchScreen` type also backs the iPad/Mac sidebar (`VaultSidebarView`, regular width class) as a plain detail-column `.searchable` (no tab bar, no X-driven route-back UX pattern expected there). This fix is not gated by size class — a search dismiss there will also route `sidebarSelection`'s backing `selectedTab` to `previousTab`, then `VaultSidebarView`'s own `.onChange(of: selectedTab)` mirrors that into `sidebarSelection`. This looked correct on inspection (same "return to where you came from" semantics apply) and CLAUDE.md states the app is iPhone-only, so this path is very likely unreachable in practice — did not chase further per scope.

Status: DONE_WITH_CONCERNS
Summary: Added `previousTab` tracking (`UIStateStore` + `MainTabView.onChange`) and a guarded `searchPresented` dismiss handler in `SearchScreen` that routes `selectedTab` back to `previousTab`; compiles clean across all three targets but the core assumption (native X actually flips `searchPresented` false) needs an on-device iOS 26 check per the task's own constraint.
Files changed: Vaultify/App/UIStateStore.swift, Vaultify/Features/Main/MainTabView.swift, Vaultify/Features/Search/SearchScreen.swift
Compile: PASS
Concerns: native-X-to-`searchPresented` binding assumption unverified headless (see above); sidebar/iPad path shares the mechanism but is out of the iPhone-only scope
