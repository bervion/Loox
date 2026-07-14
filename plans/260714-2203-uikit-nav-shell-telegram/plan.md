# UIKit Navigation Shell — Telegram-parity (compact iOS)

Status: **PLANNED** (not started) · Branch to use: `experiment/uikit-shell` (off `main`) · Base: `main` @ 850b352

## Goal
Give the compact-iPhone shell **both** behaviors Telegram has and pure SwiftUI can't do together:
1. **Native search** — detached search button in the tab bar + the search field flying up above the keyboard (iOS 26 `role: .search`).
2. **Full-screen detail push** — pushing a detail covers the tab bar with a **buttery UIKit slide** (no beta jank), back-swipe reveals the tab bar underneath.

Telegram achieves both because it is UIKit (`UINavigationController → UITabBarController → pushed VCs`). SwiftUI forces a choice:
- `TabView { NavigationStack }` → native search works, but tab-bar-hide on push is janky (iOS 26 beta).
- `NavigationStack { TabView }` → smooth full-screen push, but native search breaks.

This plan takes the **UIKit route** — but the *minimal* one that keeps ~all SwiftUI UI intact.

## Non-goals
- No change to iPad/Mac. `VaultSidebarView` / `MacRootView` stay pure SwiftUI (regular width). The UIKit shell is **compact iOS only**.
- No rewrite of detail screens' internal navigation. They keep their SwiftUI `NavigationStack` + `.navigationDestination`.
- No change to unlock/lock, sheets, toasts, auto-lock (those come from `vaultShellBehaviors()`, applied on the SwiftUI content — unchanged).

---

## Architecture (the refined hybrid)

Keep the **SwiftUI `TabView`** exactly as on `main` (with `role: .search`). Wrap it in a UIKit `UINavigationController`. Route every **top-level** tab→detail push through that nav controller. Each pushed destination gets its **own self-contained SwiftUI `NavigationStack`**, so the detail's *internal* navigation stays pure SwiftUI and unchanged.

```
AdaptiveRootView (compact iOS)
  └─ VaultUINavShell : UIViewControllerRepresentable
       └─ UINavigationController                 ← nav bar HIDDEN at root, SHOWN for pushes
            ├─ root VC:  UIHostingController( MainTabView + vaultRootEnvironment )
            │              └─ SwiftUI TabView (role:.search)   → native search + Liquid Glass bar
            └─ pushed VC: UIHostingController( NavigationStack { DetailRoot + destinations }
                                               + vaultRootEnvironment )
                            → covers the tab bar (UIKit push), detail's own SwiftUI nav inside
```

Why this is the *minimal* UIKit intervention:
- The SwiftUI `TabView` is the **root of its own hosting controller** (NOT wrapped in a SwiftUI `NavigationStack`) → `role: .search` behaves natively (the exact thing that broke on the `NavigationStack { TabView }` experiment).
- Detail pushes go onto the **UIKit** `UINavigationController` → smooth native slide, tab bar covered, no `.toolbar(.hidden)` jank.
- Because each pushed destination carries its **own** `NavigationStack`, sub-navigation inside a detail (ItemDetail → passkey, Settings → General → Language) is **plain SwiftUI** and needs **zero** conversion. Only the *first hop out of a tab* is bridged.

### Components to build
1. **`AppNavigator`** (`Vaultify/Platform/AppNavigator.swift`) — `@Observable` (or plain class) bridge.
   - `weak var navigationController: UINavigationController?`
   - `func push<V: View>(@ViewBuilder _ dest: () -> V)` — wraps `NavigationStack { dest() }` in `vaultRootEnvironment`, makes a `UIHostingController`, `pushViewController(_, animated: true)`.
   - `func pop()` / `func popToRoot()`.
   - Injected into the SwiftUI environment so any screen can call it.
2. **`vaultRootEnvironment(_ env:)`** view modifier (`Vaultify/App/VaultRootEnvironment.swift`) — single source of truth for the env chain, applied at **app root AND every pushed hosting controller**:
   ```
   .environment(env)
   .environment(env.uiState)
   .environment(\.locale, locale)
   .environment(\.appTheme, env.theme.active)
   .environment(\.meshPhase, env.theme.meshPhase)
   .environment(\.meshAnimated, !env.theme.settings.reduceMotion)
   .environment(navigator)                       // NEW
   .toggleStyle(.themed) / .tint(.primary)
   .preferredColorScheme(env.theme.preferredColorScheme)
   .appFontScale(env.theme.settings.fontScale)
   ```
   Refactor `VaultifyApp` main window to use this same modifier (DRY — today it inlines the chain at lines ~111-120). **Missing any env on a pushed VC = crash**, so centralizing is mandatory.
3. **`VaultUINavShell`** (`Vaultify/Features/Main/VaultUINavShell.swift`) — `UIViewControllerRepresentable`.
   - `makeUIViewController`: build `UINavigationController`, set root = hosting(`MainTabView`), create `AppNavigator(nav)`, hide nav bar at root.
   - `updateUIViewController`: keep env refs fresh (theme/locale changes must re-flow — verify live theme switch still works through the boundary).
   - A `UINavigationControllerDelegate` (`willShow`): `setNavigationBarHidden(topVC === rootTabHost, animated:)` so root has no bar, pushes get a bar + back button.
4. **`AdaptiveRootView`** — swap `MainTabView()` → `VaultUINavShell()` on the `#if os(iOS)` compact branch only.

### Nav-bar / back-button handling
- Pushed detail screens draw a SwiftUI `.toolbar` (back handled by UIKit's `UINavigationController`; SwiftUI toolbar items bridge to the UIKit nav bar via `UIHostingController`, iOS 16+).
- Detail screens that currently call `.platformHiddenNavigationBar()` + draw their own header: keep as-is, but the pushed `NavigationStack` must let them hide their bar. Verify ItemDetail header + back gesture. (ItemDetail is the highest-risk screen — test first.)
- Interactive back-swipe: UIKit gives it for free. Confirm it reveals the tab bar during the swipe (the whole point).

---

## Push-site conversion (the ONLY bridging surgery)

Remove each tab screen's own `NavigationStack` (they become plain content in the `TabView`). Convert each **top-level** push to `navigator.push { ... }`. Exact sites (verified on `main`):

| File | Line(s) | Current | New |
|------|--------|---------|-----|
| `Home/HomeScreen.swift` | 156, 398 | `uiState.homePath.append(SettingsRoute()/ProfileRoute())` | `navigator.push { SettingsScreen() }` / `{ ProfileScreen() }` |
| `Home/HomeScreen.swift` | 346 | `NavigationLink(value: NotificationsRoute())` | `Button { navigator.push { NotificationsScreen() } }` |
| `Home/HomeScreen.swift` | 528, 819 | `uiState.homePath.append(item.id / $0.id)` | `navigator.push { ItemDetailScreen(itemID:) }` |
| `Home/HomeScreen.swift` | 165-166 | `.navigationDestination(ProfileRoute/SettingsRoute)` | **delete** (destinations move into the pushed stack) |
| `Items/ItemsScreen.swift` | 201 | `NavigationLink(value: route)` | `Button { navigator.push { destination(for: route) } }` |
| `Watchtower/WatchtowerScreen.swift` | 272,327,338,346,372 | `NavigationLink(value: WatchtowerCategory.*)` | `Button { navigator.push { WatchtowerCategoryDestination(...) } }` |
| `Watchtower/WatchtowerScreen.swift` | 134,137 | `.navigationDestination(String/WatchtowerCategory)` | **delete** (moves into pushed stack) |
| `Search/SearchScreen.swift` | (item tap) | item selection push | `navigator.push { ItemDetailScreen(itemID:) }` |
| `Vault/VaultRoutes.swift` | 33-59 | `vaultNavigationDestinations()` (String/VaultRoute/SharedWithMe/Notifications) | **reuse inside each pushed `NavigationStack`** as `.vaultNavigationDestinations()` so deep links within a detail still resolve |

Note: `SearchScreen.swift:67-69` `.append(...)` are **search-scope arrays**, NOT navigation — do not touch (except the scope-chip relocation below).

`uiState.rootPath` / per-tab paths become unused for compact iOS (keep for the sidebar/iPad path bindings). Do not delete `UIStateStore` paths blindly — sidebar uses them.

---

## Search polish (Telegram parity)
- **Native search stays SwiftUI** — `MainTabView` keeps `Tab(role: .search) { SearchScreen() }`. `SearchScreen` keeps its `.searchable(text:isPresented:)`. Because the TabView is now the hosting controller's root (not SwiftUI-nav-wrapped), `role: .search` should present the field above the keyboard natively. **This is the behavior that failed on the experiment branch and should now work — verify first thing.**
- **Scope chips relocation** (user ask): move the search scope chips (This Space / All Spaces / Shared) to sit **directly above the search bar / keyboard**, like Telegram's Chat/Kênh/… row. Options: `.searchScopes(_, activation: .onTextEntry)` (native, sits under the search field) or a custom chip row pinned via `.safeAreaInset(edge: .bottom)` above the keyboard. Prefer native `.searchScopes` if it renders in the right place on iOS 26; fall back to custom inset.

---

## Fallback matrix (verify each)
| iOS | Tab bar | Search | Push |
|-----|---------|--------|------|
| 26+ | SwiftUI TabView (Liquid Glass) | `role:.search` detached button + above-keyboard | UIKit slide, tab bar covered |
| 18–25.x | SwiftUI TabView | `role:.search` (search tab, no glass) | UIKit slide |
| 17.3–17.x | `LegacyChipTabBar` (existing safeAreaInset) | Search as ordinary tab, `.searchable` | UIKit slide |

The `UINavigationController` push works on **all** targets (iOS 16+). Only the tab-bar/search *visuals* differ by version — already handled inside `MainTabView`, which we keep. So the fallback is inherited, not rebuilt.

---

## Phases (each ends with a user runtime-test — I cannot verify UIKit/SwiftUI bridging without a run)

- **Phase 1 — Shell skeleton (prove smooth + search).**
  Build `AppNavigator`, `vaultRootEnvironment`, `VaultUINavShell`, wire into `AdaptiveRootView`. Convert **only** the Home→ItemDetail push. Leave other tabs' pushes temporarily working via their existing stacks IF compatible, else stub. Compile.
  **User tests:** tab bar + Liquid Glass intact · tap search → field flies up + keyboard (native) · tap a Home item → smooth full-screen slide, tab bar covered, back-swipe reveals it · live theme/locale switch still flows into a pushed detail.
  Gate: if search or push isn't right, stop and rethink before mass conversion.

- **Phase 2 — Convert all tab push sites.** Items, Watchtower, Search, Home settings/profile/notifications per the table. Remove tab screens' `NavigationStack`s. Each pushed destination wraps its own `NavigationStack { … .vaultNavigationDestinations() }`.
  **User tests:** every tab's drill-downs push full-screen; deep sub-navigation inside details works; back all the way out.

- **Phase 3 — Nav-bar/back-button correctness.** The delegate hiding at root, SwiftUI `.toolbar` items bridging on pushed screens, ItemDetail header + toolbar actions, edit sheets. **User tests** the highest-risk screens (ItemDetail, Settings tree, Watchtower fix queue).

- **Phase 4 — Search scope chips relocation** + final Telegram-parity polish (animation timing, large-title behavior, back gesture feel).

- **Phase 5 — Full DNA pass:** light/dark, Reduce Motion/Transparency, increased contrast, Dynamic Type, VI longest labels, 44pt targets, no invisible chrome after theme switch. `make check`. Then PR `experiment/uikit-shell` → `main`.

---

## Risks & mitigations
- **Env not flowing across the UIKit boundary → crash on push.** Mitigate: single `vaultRootEnvironment` modifier reused everywhere; Phase 1 explicitly tests a pushed detail + live theme switch.
- **`role: .search` still not presenting** even as hosting-root. If so, the fallback is a `UISearchController` on the tab controller (more UIKit) — decide in Phase 1, don't build preemptively.
- **SwiftUI `.toolbar` items not bridging to the UIKit nav bar** on pushed VCs. Known to work iOS 16+; verify in Phase 3, else set `navigationItem` manually per hosting controller.
- **Retain cycle** navigator ⇄ nav controller: navigator holds `weak` nav controller; nav controller does not strongly hold navigator beyond the representable's coordinator.
- **iPad size-class flip** compact↔regular must still swap shells cleanly (AdaptiveRootView already keys on `horizontalSizeClass`); verify a Stage Manager resize doesn't strand a pushed UIKit stack.
- **Unverifiable by me** — every phase is gated on the user running it on device/simulator. Ship nothing half-converted to `main`.

## Rollback
`main` is the safe base (native search + full-screen detail already work; only the beta jank remains). If the UIKit shell misbehaves, `AdaptiveRootView` swaps `VaultUINavShell()` back to `MainTabView()` in one line — the SwiftUI screens are unchanged underneath, so revert is trivial.

## Open questions for the user
1. Scope chips: native `.searchScopes` placement acceptable, or must it be a pixel-match custom row above the keyboard?
2. On iOS 17.3, is the legacy chip tab bar + ordinary search tab acceptable, or should search there also try to mimic Telegram?
3. Any detail screen besides ItemDetail/Settings/Watchtower with tricky internal navigation to flag for Phase 3?
