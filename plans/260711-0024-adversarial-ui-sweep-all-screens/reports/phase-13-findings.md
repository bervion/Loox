# Phase 13 — Main shell + Mac surfaces + App root: findings

Owned: `Vaultify/Features/Main/*` (12 files), `Vaultify/App/RootView.swift` (router +
`PrivacyShield` + `ControlledRevealModifier`, presentational-only per scope amendment),
`Vaultify/App/VaultifyApp.swift` (review-light). 16 surfaces per registry row-13.

## 6 audit greps (run over all 14 owned files)

1. **SE-width/Dynamic Type** (`.frame(width:` / `GeometryReader` / `minimumScaleFactor` /
   `lineLimit(1)`): 6 hits — `MacHeaderBar.swift:101,104` (search-hit title/subtitle
   `lineLimit(1)`, arbitrary user data in a Mac popover, acceptable), `MacSidebarList.swift`
   (avatar frame, fixed at review time — see finding #2; identity-name `lineLimit(1)`,
   acceptable data truncation), `VaultTabBar.swift:24,61` (`TabBarMetric.indicatorSize` /
   `.badgeDot`, token-backed, not magic numbers). No fixed-frame VI-clipping defect.
2. **Typography** (`.font(\.`): 0 hits. Clean.
3. **Radius** (`cornerRadius(`): 3 hits, all token-backed — `VaultTabBarBackground.swift:18`
   (`TabBarMetric.cornerRadius`), `MacHeaderBar.swift:34,119` (`Radius.sm` / `Radius.md`).
   Clean.
4. **Spacing** (`.padding(`): 12 hits, all `Space.s*` or `TabBarMetric.horizontalInset`
   tokens. Clean.
5. **Hit target** (`PolarisIcon(` on tappable glyphs): 18 hits, all token-sized
   (`Metric.iconTab/iconTile` or explicit Mac-pointer sizes 10-16pt — Mac is
   cursor-driven, the 44pt iOS thumb-target rule doesn't transfer 1:1; every Mac icon
   button carries an `accessibilityLabel`). `VaultTabBar`'s own tap row uses
   `Metric.hitMin` (44pt) correctly.
6. **Haptics** (`Haptics\.`): 2 hits — `VaultShellBehaviors.swift:193`
   (`Haptics.success()` on shake-to-lock, mirrors `SlideToUnlock`'s `.success()` for a
   gesture-completed security-state change — consistent precedent, not doubled: `lock()`
   itself fires no haptic, verified `VaultSecurity/VaultSession.swift:138`) and
   `VaultTabBar.swift:49` (was `.selection()`, inconsistent with the app-wide convention
   where every other selection/minor-action site uses `.tap()` — **fixed**, see below).

**Color** (raw `.white/.black/.gray/.red/.primary/.secondary`): 0 hits across all 14
files. Clean.

## Findings table

| Surface | Protocol Q(1-5) | Finding | Fix | Severity | Status |
|---|---|---|---|---|---|
| `RootView` (router) | Q1 pass, Q5 pass | Single job (route switch), no competing content. | — | — | pass |
| `RootView` route `.animation` | Q5 | `reduceMotion ? nil : .smooth(duration:0.35)` on `route` only — verified collapses to instant swap under Reduce Motion. | none needed | — | pass |
| `PrivacyShield` overlay | Q5 (privacy exposure timing) | `obscured` is set via plain assignment (no `withAnimation`, no `.animation(value: obscured)`) → shield show/hide is **instant**, not a fade — verified by reading `handleScenePhase`. This is the SAFE behavior (no partial-opacity exposure window when backgrounding); `.transition(.opacity)` is inert without an animation trigger. | none — correct as-is, flagging so intent is on record | — | pass (verified) |
| `PrivacyShield` z-order | Q4 | Declared after the route `switch` in the `ZStack` → renders on top without needing explicit `zIndex`; covers full screen (`ignoresSafeArea()`), logo-only per CLAUDE.md spec. | none | — | pass |
| `ControlledRevealModifier` | Q4/Q5 | Blur radius (10) / scale (1.05) are one-off physics constants, not part of `Space`/`Radius`/`Motion` token scale — same tier as `Motion.pressScale` (a bespoke motion constant) rather than a spacing/radius value. Shipped very recently; scope explicitly says verify-don't-redesign. | none — YAGNI to add a single-use token; documented rationale | Low (observational) | pass, not touched |
| `VaultifyApp` (review-light) | Q2 | Invite alerts + `Button("OK")` all resolve via the string catalog (`Couldn't accept the invitation` / `Invitation accepted` / message text all EN+VI present); dynamic `Text(verbatim: inviteError)` is correct usage (already-localized `NSError.localizedDescription`, not a literal). | none | — | pass |
| `AdaptiveRootView` | Q1 | Pure size-class/platform router, single job. | none | — | pass |
| `MainTabView` | Q1, Q3, Haptics | Native `TabView`/`Tab(role:.search)` + 17.6 `.tabItem` fallback; icon-only by design (VoiceOver labels localized EN+VI, verified in catalog: Home/Items/Watchtower/Search); `tabImage` re-renders at `Metric.iconTab` (native bar ignores SwiftUI `.frame`, documented workaround). No custom overlay reintroduced (native tab bar owns switching/safe-area, matches CLAUDE.md lock). | none | — | pass |
| `VaultTab` enum | Q2 | 4 accessibility labels, single words, no `!`/`—`/`·`, EN+VI present. | none | — | pass |
| `VaultShellBehaviors` | Haptics | Shake-to-lock `Haptics.success()` mirrors `SlideToUnlock`'s established gesture-completion convention; not doubled (`VaultSession.lock()` fires no haptic itself). | none | — | pass |
| `VaultShellBehaviors` | Q1 | Composition-only modifier (toast/sheets/auto-lock/notifications); no visual surface of its own to score against Q1-5 beyond its child overlays (owned by other phases). | none | — | pass (n/a) |
| `VaultTabBar` / `VaultTabBarBackground` / `TabPressStyle` | dead-code check | Confirmed **not referenced anywhere** (`grep -rn "VaultTabBar("` → 0 hits outside its own file) — this is intentional: `docs/design-guidelines.md:408` documents it as "legacy custom implementation kept out of the runtime path unless a future experiment explicitly re-enables it," same pattern as the Wallpaper engine. Not a defect; CLAUDE.md's "do not restore custom shell overlay" reinforces why it stays inert. | none | — | pass (dormant-by-design) |
| `VaultTabBar` haptic | Haptics | `Haptics.selection()` on tab select — every other selection/minor-action call site in the app uses `Haptics.tap()` (grep across `Vaultify/Features/**`: 15 `.tap()` sites, 0 other `.selection()` sites). Inconsistent with the vocabulary table's "Selection / toggle / minor action → tap" row. Dormant code (zero runtime impact today) but cheap to keep correct for the documented re-enable path. | Changed `Haptics.selection()` → `Haptics.tap()`. | Low | **fixed** |
| `VaultTabBar` glass (`vaultTabBarSurface`/`vaultTabSelectionSurface`) | glass guard | `#if compiler(>=6.2)` + `#available(iOS 26, macOS 26, *)` + Reduce-Transparency solid/material fallback, correctly guarded. Not scroll-tied (this is a persistent floating control, not a scrolling header) — the on-device "glass conditional on scroll" lesson applies to header bars over scrolling content, a different surface class; not applicable here. Also currently dormant (see above). | none | — | pass |
| `MacRootView` | Q1, Q4 | Three-column shell (sidebar/list/detail), matches reference layout; tokens throughout (`Space.*`, `Radius` via children); alert "Keep at least one identity" — single OK button, correct pattern. Mac review-light. | none | — | pass |
| `MacSidebarList` | Q4 | Sidebar profile-row avatar used a bare `28` frame instead of a `Metric` token (list-row leading-tile pattern already has `Metric.iconTile = 32` for exactly this role). | Changed `.frame(width: 28, height: 28)` → `.frame(width: Metric.iconTile, height: Metric.iconTile)`. | Low | **fixed** |
| `MacSidebarList` identity-name `lineLimit(1)` | Q2 | User-provided identity title, not a fixed known-longest string; standard row-truncation pattern used elsewhere in the app. | none | — | pass |
| `MacHeaderBar` — `MacToolbarSearchField` | Q2, Q3 | Search field + clear button, `accessibilityLabel("Clear")`, Esc key handling, token radius/spacing. | none | — | pass |
| `MacHeaderBar` — `MacDetailHeader` | Q3, action-hierarchy | Two actions (Edit + overflow Menu), not stacked/not a "button wall"; Edit is the primary (bordered), overflow Menu demotes Archive — correct rank. `accessibilityLabel("More")`. | none | — | pass |
| `MacHeaderBar` — `MacSearchSuggestionsPanel` | Q2 (copy standard) | `Text(verbatim: "— \(subtitle)")` — em-dash used as a title/subtitle separator, a direct violation of the "never em-dashes in UI strings... separate ideas with real layout" rule. | Replaced the single-line `title — subtitle` HStack pairing with a two-line `VStack` (title, then subtitle on its own line, `.footnote`/secondary) — no glue character. | Medium | **fixed** |
| `MacItemListColumn` | Q1, Q5 (empty state) | `ContentUnavailableView` with Polaris icon + localized copy for the zero-items state; reuses `VaultItemRow` for populated state (no forked visual language, matches shell rule 3's "same feature screens" requirement). | none | — | pass |
| `VaultSidebarList` | Q1, Q2 | Mirrors the 4 iPhone tabs + Spaces + Profile; all labels via `LocalizedStringResource`/`.inAppLocalized`, catalog-verified (`Vault`, `Spaces`, `Profile` all EN+VI present). | none | — | pass |
| `VaultSidebarView` | Q1, Q5 | iPad/Mac `NavigationSplitView`; `reconcileSelection()` handles size-class flips (compact↔regular) without stranding a selection — verified against the red-team note already in the code comment. Shares `vaultShellBehaviors()` with `MainTabView` (single behavior source, no fork). | none | — | pass |

## Action-hierarchy audit (mid-sweep rule)

No completion/result screens are owned by Phase 13. The only multi-button surfaces are
`MacDetailHeader` (2, correctly ranked, not a "wall") and menus (which are the demotion
mechanism itself, not a violation). No 3+ stacked-button state found in owned files.

## Fixes applied (3, all Low/Medium — no High)

1. **Medium** — `MacHeaderBar.swift` (`MacSearchSuggestionsPanel`): removed em-dash
   title/subtitle glue, switched to two-line layout.
2. **Low** — `MacSidebarList.swift`: `28` → `Metric.iconTile` for the profile-row avatar.
3. **Low** — `VaultTabBar.swift`: `Haptics.selection()` → `Haptics.tap()` (dormant file,
   kept correct for its documented future re-enable path).

## Deferred / flagged, not fixed

- **`ControlledRevealModifier`'s bespoke blur/scale constants**: no token exists for
  one-off route-transition physics; introducing a token for a single call site would be
  YAGNI. Recently shipped and explicitly scoped as verify-not-redesign — left as-is.
- **Mac hit-target sizing** (10-16pt icon glyphs in `MacHeaderBar`/`MacSidebarList`):
  the 44pt rule is an iOS/touch HIG constant; Mac is pointer-driven. Flagged, not changed
  (review-light, no user-reported friction).
- **Doc drift**: `docs/app-feature-map-ui-ux.md` has no "Mac/iPad surfaces" section
  (already flagged by Phase 0's registry, `reports/phase-00-surface-registry.md` — carried
  forward here, not re-litigated). Follow-up docs task, not a Phase 13 code fix.

## Compile

`tuist generate --no-open` then `xcodebuild … -scheme Vaultify -configuration Debug
-destination 'generic/platform=iOS Simulator' … CODE_SIGNING_ALLOWED=NO` — see session
report for tail output; result: **BUILD SUCCEEDED** (app + embedded AutoFill extension).

**Status:** DONE
**Summary:** 16/16 owned surfaces reviewed against the 5-question protocol + 6 audit
greps. 3 low/medium fixes applied (em-dash copy violation, one magic-number token swap,
one haptic-vocabulary correction in dormant code). Privacy Shield timing + Controlled
Reveal Reduce-Motion collapse verified correct by reading the actual animation bindings
(not redesigned, per scope). Native `TabView` tab architecture untouched — no custom
shell overlay reintroduced. `VaultTabBar`/`VaultTabBarBackground` confirmed dormant/
documented, not accidentally-dead orphan code. Mac surfaces reviewed light: tokens clean,
no forked visual language, 2 cheap fixes applied, hit-target sizing flagged not changed.
Zero new/changed catalog strings (em-dash fix touched a `Text(verbatim:)`, not a catalog
key) — `strings-manifest-phase-13.md` is empty by design.

**Unresolved questions:** none blocking. (Carried from Phase 0, not mine to resolve:
Mac/iPad doc-map gap — flagged to docs-manager already in the registry report.)
