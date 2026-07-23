# iPad Readiness Audit — Screen Inventory + Width Mechanism (260723)

Read-only audit of `/Users/prime/Developer/Vaultify`. Shell context: `Vaultify/Features/Main/AdaptiveRootView.swift:20-28` picks `VaultUINavShell(MainTabView)` for compact width and `VaultSidebarView` (NavigationSplitView) for regular width; `MacRootView` on macOS. All file paths below are relative to the repo root; every screen listed was read in source.

> Note: `VaultSidebarView.swift` changed mid-audit (another session landed the permanent-sidebar commit marked "owner 260723"). §3 audits the version now on disk.

---

## §1 Screen inventory — full-width iPhone layouts at regular width

Legend: **sizing** = how the screen constrains horizontal content today; **break** = what happens at 1024–1366pt regular width. Severity: **H** = functionally broken/absurd, **M** = clearly wrong-looking, **L** = tolerable but off-spec.

| Screen | Current sizing | Break at iPad width | Sev |
| --- | --- | --- | --- |
| **WelcomeLandingView** (`Features/Onboarding/WelcomeLandingView.swift`) | Logo capped `min(width*0.56, 252)` (:35); content `frame(maxWidth: .infinity)` (:56); carousel card capped `min(width*0.72, 320)` (:175) | Text/CTA column fine-ish (capsule hugs text), but the **launch bloom cannot cover the screen**: bloom max = 1950 canvas units × scale derived from the 252pt-capped frame ≈ 1,196pt diameter (`BrandAnimation/LooxLaunchResolver.swift:166`, `LooxAnimationGeometry.swift:14`) vs a 13" diagonal of ~1,707pt — the "crossfade behind the flood" hand-off (:143) happens with the screen visibly un-flooded. Carousel shows 3 tiny cards lost in 1366pt | **H** |
| **CreateMasterPasswordView** (`Features/Onboarding/CreateMasterPasswordView.swift`) | `ScrollView > VStack.frame(maxWidth:.infinity).padding(Space.s6)` (:56-57); capsule field group full-width (:75-105) | 54pt-high password capsule stretched to ~1,300pt; left-aligned title marooned; `BrandCapsuleCTA` spans full width (`DesignSystem/Components/BrandCapsuleCTA.swift:17,26`) | **H** |
| **NameStepView** (`Features/Onboarding/NameStepView.swift`) | Same pattern: `.frame(maxWidth:.infinity).padding(Space.s6)` (:43-45), full-width capsule field group | ~1,300pt name/email fields + full-width CTA | **H** |
| **EmergencyKitView** (`Features/Onboarding/EmergencyKitView.swift`) | `.frame(maxWidth:.infinity).padding(Space.s6)` (:62-63); kit card + Save button full-width (:214-230) | The branded kit card and dashed recovery-key box stretch to ~1,300pt; two-line key split (:249-254) becomes one absurdly wide strip | **H** |
| **ChooseThemeView** (`Features/Onboarding/ChooseThemeView.swift`) | `.frame(maxWidth:.infinity).padding(Space.s6)` (:32-33); `LazyVGrid(.adaptive(minimum:104))` (:47) | 3 theme cards left-aligned in a 1,300pt row (adaptive min 104 → cards stay ~104pt wide, mass of empty space right); full-width CTA (:39) | M |
| **EnableBiometricView** (`Features/Onboarding/EnableBiometricView.swift`) | `OnboardingScrollingStep` (`.frame(maxWidth:.infinity)`, `OnboardingStepHeader.swift:56`); buttons `.frame(maxWidth:.infinity)` (:27,32) | Enable/Not-now buttons stretched to ~1,300pt | **H** |
| **OnboardingDoneStep** (`Features/Onboarding/OnboardingFlow.swift:178-237`) | `OnboardingScrollingStep`; animation fixed 220pt (:204); CTA `.frame(maxWidth:.infinity)` (:215) | Full-width "Open Loox" button; same bloom under-coverage as Welcome (220pt frame → bloom ≈ 1,043pt) | **H** |
| **JoinVaultFlow** (`Features/Onboarding/JoinVaultFlow.swift`) | Steps in `OnboardingScrollingStep` (:269, :395); QR capped `.frame(maxWidth:260)` (:287); one CTA `.frame(maxWidth:260)` | QR itself fine; headers/error cards/CTAs stretch; `RestoreMethodSheet` (:154-220) is a `.sheet` → OK as a form sheet on iPad | M |
| **LockScreen** (`Features/Unlock/LockScreen.swift`) | `OnboardingScrollingStep` + `.padding(.horizontal, Space.s8)` (:115); password field full-width; `SlideToUnlock` fills width via GeometryReader (`SlideToUnlock.swift:21-23`) | Password field ~1,290pt wide; **slide-to-confirm track becomes a ~1,286pt drag** (physically absurd, and `maxX*0.9` threshold makes it nearly impossible one-handed) | **H** |
| **HomeScreen** (`Features/Home/HomeScreen.swift`) | All sections in one column `.padding(.horizontal, Space.gutter)` (:273); rows/cards `frame(maxWidth:.infinity)` (:447); empty states cap text at 300pt (:710,715,757) but not the layout (:681) | Profile card, attention/recent/favorites list cards, pending-share rows stretch to ~1,320pt single-column; `QuickActionsGroupCard` 2×2 tiles become ~640pt-wide buttons (`Home/Components/QuickActionCard.swift:57,121`); TOTP h-scroller ok (fixed cards) | **H** |
| **SearchScreen** (`Features/Search/SearchScreen.swift`) | `List` `.platformInsetGroupedListStyle()` (:234,251); scope chip bar `.padding(.horizontal, Space.gutter)` (:388) | Result rows stretch full column width (insetGrouped adds only ~20pt margins on iPad); chip bar strip floats along a 1,346pt row | M |
| **ItemsScreen** (`Features/Items/ItemsScreen.swift`) | Single column `.padding(.horizontal, Space.gutter)` (:36) | Spaces/Categories/Tags row cards stretch to ~1,320pt | M |
| **WatchtowerScreen** (`Features/Watchtower/WatchtowerScreen.swift`) | Sections `.padding(.horizontal, Space.gutter)` (:365,373,382,419,439,463) | Score ring band + finding cards at ~1,320pt; ring gauge visually tiny inside a huge card | M |
| **ItemDetailScreen** (`Features/ItemDetail/ItemDetailScreen.swift`) | `ScrollView > VStack .padding(Space.gutter)` (:118-155) | Field cards ~1,320pt wide; secret value rows with copy affordances become mostly dead space (Mac shell already clamps its detail pane instead — see §2) | **H** |
| **ItemEditorScreen** (`Features/ItemEditor/ItemEditorScreen.swift`) | `Form` (:79); presented as `.sheet` everywhere (e.g. `HomeScreen.swift:221`) | On iPad `.sheet` = centered form sheet (~540pt) → mostly fine as-is; only wrong if ever pushed full-screen. Alias sub-sheet detents (:371) ignored on iPad (becomes form sheet) — acceptable | L |
| **SettingsScreen + children** (`Features/Settings/SettingsScreen.swift:95` `Form`; children are Forms/Lists) | System `Form` full column width | Rows stretch to detail-column width (~1,300pt fullscreen); iPad Settings idiom expects ~700pt max readable rows | M |
| **ProfileScreen** (`Features/Profile/ProfileScreen.swift:40-80`) | `ScrollView > VStack .padding(Space.gutter)` (:80) | Group cards + devices card at ~1,320pt | M |
| **LooxHubScreen** (`Features/Profile/LooxHubScreen.swift`) | `.padding(Space.gutter)` (:37); section cards use **fixed 2-column** `LazyVGrid(.flexible × 2)` (:398) | Two ~640pt-wide tiles per row — the clearest "stretched iPhone" tell in the app | **H** |
| **Paywall** (`Features/Subscription/LooxAcquisitionPaywallView.swift:40-54`, `LooxPaywallScreen.swift:107`, `LooxPlanLandingScreen.swift:23`) | `ScrollView` + fixed margins (`Self.margin = Space.s5` :37-38) | Plan cards, price rows, and the purchase `bottomBar` span full sheet/screen width; as a pushed screen at fullscreen iPad it's ~1,300pt | **H** (pushed) / L (as sheet) |
| **TotpListScreen** (`Features/Home/TotpListScreen.swift:10`) | `LazyVGrid(.adaptive(min 158, max 200))` (:10), gutter (:26) | Adapts to ~7-8 columns — actually the one grid that behaves; only needs an outer cap for taste | L |
| **Sharing sheets** (`ShareAccessSheet.swift:639`, `QuickLinkView.swift:71-95`, `ShareSpaceSheet`, `QuickView/*`) | Full-width VStacks inside `.sheet` | Form-sheet presentation on iPad (~540pt) absorbs most of it; interior `frame(maxWidth:.infinity)` CTAs fine at that width | L |
| **GeneratorScreen** (`Features/Generator/GeneratorScreen.swift:8-23`) | `VaultSheetScaffold` sheet | Form sheet on iPad — fine; macOS branch already sets an explicit frame (`VaultSheetScaffold.swift:45`) | L |
| **FamilyScreen** (`Features/Profile/FamilyScreen.swift:97`) | empty-state text capped 320pt, rest gutter-padded | Cards stretch | M |

**Compact-in-Split-View note:** iPhone-width layouts are *correct* in narrow iPad Split View / Slide Over because `AdaptiveRootView` swaps to `MainTabView` at compact width — the problem is exclusively regular width. But `Space.gutter` misreports there (see §5, `Spacing.swift:26-33`).

---

## §2 Recommended width mechanism

### Existing machinery (evidence)

- `Space.contentMax: CGFloat = 430` — already defined, **zero call sites** (`Vaultify/DesignSystem/Tokens/Spacing.swift:35`; web-spec twin `Design System/tokens/spacing.css:21` `--content-max: 430px`). The token slot exists; nothing consumes it.
- `Space.gutter` — adaptive 16/20 screen margin, `UIScreen.main`-based (`Spacing.swift:26-33`). Regular-width variant slots here.
- Mac shell already width-clamps by hand: list pane `frame(minWidth:260, idealWidth:300, maxWidth:420)` (`MacRootView.swift:64`), toolbar search `frame(minWidth:280, idealWidth:560, maxWidth:720)` (`MacHeaderBar.swift:37`), title block `frame(maxWidth:560)` (`MacHeaderBar.swift:129`), sheet frame `minWidth:460 idealWidth:520` (`VaultSheetScaffold.swift:45`). These are exactly the 520–720pt band the shared modifier should standardize.
- Ad-hoc caps that prove the pattern: `HomeScreen.swift:710,715,757` (`maxWidth:300` empty-state text), `FamilyScreen.swift:97` (320), `JoinVaultFlow.swift:287` (260 QR).

### The ONE mechanism

Add a platform-neutral (pure SwiftUI, no UIKit — macOS reuses it as-is) content-width clamp in the token layer, next to `Space.contentMax`:

- **Where:** `Vaultify/DesignSystem/Tokens/Spacing.swift` (extend `Space`) + a small `View` extension in a new `Vaultify/DesignSystem/Tokens/ContentWidth.swift` (or appended to `Spacing.swift` — repo precedent: helpers live beside tokens, cf. `.vaultCornerRadius`).
- **Shape:**
  - `Space.contentMaxForm = 560` — onboarding steps, unlock, single-column forms/settings (matches `MacHeaderBar.swift:129`'s 560).
  - `Space.contentMaxReading = 640` — detail screens, paywall.
  - `Space.contentMaxWide = 960` — feeds/grids (Home, Hub, Watchtower).
  - `.vaultContentWidth(_ max: CGFloat = Space.contentMaxForm)` = `frame(maxWidth: max).frame(maxWidth: .infinity)` — clamps and re-centers; applied to the **content inside** the ScrollView so backgrounds, scroll indicators, and `safeAreaInset` bars stay full-bleed. (Existing `contentMax = 430` stays as-is or is renamed into this family.)
- On compact width the clamp is a no-op (content is already < 560pt), so no size-class branching is needed — one modifier everywhere, and no behavior change on iPhone.

### Call sites by phase

**P1 — onboarding + unlock (highest leverage first):**
1. `OnboardingStepHeader.swift:49-62` — clamp inside `OnboardingScrollingStep`'s `content` (single edit fixes `LockScreen.swift:74`, `EnableBiometricView.swift:12`, `JoinVaultFlow.swift:269,395`, `OnboardingFlow.swift:198`).
2. `BrandCapsuleCTA.swift:13-28` — clamp inside the component (fixes the pinned CTA on every step at once: `CreateMasterPasswordView.swift:66`, `NameStepView.swift:53`, `EmergencyKitView.swift:73`, `ChooseThemeView.swift:39`).
3. Per-screen scroll content: `CreateMasterPasswordView.swift:56`, `NameStepView.swift:43`, `EmergencyKitView.swift:62`, `ChooseThemeView.swift:32`, `WelcomeLandingView.swift:51` (`landingContent` only — keep the carousel full-bleed), `OnboardingDoneStep` CTA `OnboardingFlow.swift:214-221`.
4. `LockScreen.swift:106-115` — clamp the `passwordSection` + `SlideToUnlock` group (or bake a `maxWidth` into `SlideToUnlock.swift` itself; a confirm-slide should never exceed ~400pt).
5. Bloom fix (separate from width): scale `LooxLaunchResolver.bloomState`'s 1950-unit target by the hosting screen size, or overlay the flood outside the capped animation frame (`LooxLaunchResolver.swift:161-169`, consumed at `LooxCloudAnimationView.swift:55-66`).

**P2 — tab roots (regular-width detail column):**
- `HomeScreen.swift:273` (scrollContent) + `:681` (emptyStateScaffold) — `contentMaxWide`.
- `ItemsScreen.swift:36` — `contentMaxWide` (or `Reading`).
- `WatchtowerScreen.swift:365,373,382,419,439,463` — `contentMaxWide`.
- `SearchScreen.swift:388` (chip bar) + result `List` (:234) via `.contentMargins(.horizontal, …)` (iOS 17+, within the 17.3 floor) or row-level clamp.
- `SettingsScreen.swift:95` and Form-based children — `.contentMargins` or clamp; lowest priority of P2.
- `ProfileScreen.swift:80`, `LooxHubScreen.swift:37` — `contentMaxWide`; additionally switch `LooxHubScreen.swift:398` from fixed 2-col to `.adaptive(minimum: ~160)` so tiles keep sane width inside the clamp.

**P3 — sheets/detail/paywall:**
- `ItemDetailScreen.swift:118-155` — `contentMaxReading` (aligns with how `MacRootView.swift:190-208` will host it).
- `LooxAcquisitionPaywallView.swift:40-54` (+ its `bottomBar` safeAreaInset), `LooxPaywallScreen.swift:107`, `LooxPlanLandingScreen.swift:23` — `contentMaxReading`.
- `LargeTypeView` via `platformFullScreenCover` (`ProtectedFieldRow.swift:49`, `DetailFieldRow.swift:100`, `RequestCodeView.swift:328`) — keep fullscreen (it is deliberately huge type) but clamp the glyph grid (`LargeTypeView.swift:34` adaptive already helps).
- Sharing/editor sheets: no width work needed (form-sheet width ~540pt), only detent review (§4).

---

## §3 Sidebar shell — permanent sidebar

Current state on disk (`Features/Main/VaultSidebarView.swift`): **already permanent.**

- `NavigationSplitView(columnVisibility: .constant(.all))` (:20) — visibility pinned; system writes into a `.constant` binding are discarded, so the sidebar can't be collapsed by chrome or edge gestures.
- `.toolbar(removing: .sidebarToggle)` on the sidebar column content (:30) — removes the toggle button. **API floor OK:** `toolbar(removing:)` + `ToolbarDefaultItemKind.sidebarToggle` are iOS 17.0+/macOS 14.0+, within the 17.3 deployment floor and the stable-Xcode CI SDK. Nothing here needs an availability guard.
- `.navigationSplitViewStyle(.balanced)` (:36) — in portrait/regular the detail is compressed to keep both columns visible rather than overlaying the sidebar; with `.constant(.all)` this is the only coherent style (with `.automatic`, portrait would want to overlay and fight the pinned binding). Detail column width at 11" portrait ≈ 834 − ~230 = ~604pt; at 13" landscape ≈ 1,366 − ~230 − separators ≈ ~1,120pt (which is why §2 matters).
- Sidebar width `min 200 / ideal 230 / max 320` (:29) matches Apple sidebar proportions; `MacRootView.swift:39` uses 200/230/300 — near-identical, fine.

**Compact narrowing (Split View ½ on 11", any Slide Over):** `AdaptiveRootView.swift:20-27` swaps the whole shell to `VaultUINavShell(MainTabView)`. State carry-over:

- Section selection survives both directions: `sidebarSelection` ⇄ `selectedTab` mirroring (`VaultSidebarView.swift:46-56`) + `reconcileSelection()` on re-mount (:43, :60-75). `.space`/`.profile` selections degrade gracefully (deleted-folder fallback :67-71; `.profile` is retained :72-73).
- Per-tab `NavigationPath`s are shared and persisted (`App/UIStateStore.swift:51-54, 83-101`), and the sidebar's detail screens push into them (e.g. `HomeScreen.swift:846,850` `uiState.homePath.append`), so **regular → compact keeps pushed detail** (it re-materializes inside the tab's stack).
- **Compact → regular loses pushed detail:** the compact shell pushes via UIKit (`AppNavigator.push` onto the `UINavigationController`, `Platform/AppNavigator.swift:37-65`; used when `navigator != nil`, `HomeScreen.swift:844-859`), bypassing the SwiftUI paths. A size-class flip tears down `VaultUINavShell` and every navigator-pushed ItemDetail/Settings/Profile/Notifications screen with it. Also any open sheet dismisses on the shell swap (view identity changes). Known, pre-existing asymmetry — worth an ADR note or routing compact pushes through the shared paths later; not a blocker for the permanent sidebar itself.
- The two ad-hoc stacks in the sidebar detail (`VaultSidebarView.swift:84-91` — `.space` and `.profile` cases build path-less `NavigationStack`s) lose their internal pushes on any re-mount; low impact.

---

## §4 Sheets/covers on iPad

iPad presents `.sheet` as a centered form sheet and **ignores `presentationDetents`** (detents are compact-height only), so per sheet:

| Sheet | Evidence | iPad behavior | Fix direction |
| --- | --- | --- | --- |
| `CodePromptSheet` `[.medium]` | `ItemDetail/CodePromptSheet.swift:37` | Small code prompt inflates to a full form sheet with dead space | Content is short — add an ideal-height via `presentationSizing`-style frame or accept; low priority |
| `ItemEditorScreen` alias sub-sheet `[.medium,.large]` | `ItemEditor/ItemEditorScreen.swift:371` | Form sheet; fine | none |
| `ItemTypePickerSheet` `[.large]`, drag indicator hidden | `ItemEditor/ItemTypePickerSheet.swift:68-69` | Form sheet; grid inside adapts | verify grid at 540pt |
| `RestoreMethodSheet` `[.large]` | `Onboarding/JoinVaultFlow.swift:219` | Bottom-sheet design becomes centered card — visually acceptable | none |
| `SafetyCodeVerifySheet` `[.medium,.large]` | `Sharing/SafetyCodeVerifySheet.swift:67` | Form sheet | none |
| `platformFullScreenCover` → `LargeTypeView` | `Platform/PlatformNavigation.swift:33-56`; call sites `ProtectedFieldRow.swift:49`, `DetailFieldRow.swift:100`, `RequestCodeView.swift:328` | True fullscreen 1366pt cover — intended for glanceable large type; acceptable, but the char-grid should stay clamped | keep; clamp grid (`LargeTypeView.swift:34`) |
| Editor/Sharing/Generator/Paywall sheets (`HomeScreen.swift:221-244`, `ItemDetailScreen.swift:265-288`, `WatchtowerScreen.swift:128-130`, etc.) | all `.sheet` | Form sheets ~540pt — the one place iPhone-width layouts are automatically right | none; do NOT `vaultContentWidth` inside sheets |
| Shell-level sheets (approval ceremony, TOTP import, restored draft) | `Features/Main/VaultShellBehaviors.swift:57-149` | Form sheets over either shell; fine — and they survive neither shell swap (see §3) | none |
| `OnboardingFlow` restore sheet + copy-toast overlay | `OnboardingFlow.swift:93-101` | Sheet fine; bottom toast overlay floats over 1366pt width — cosmetic | optional clamp in `CopyToastOverlay` |

No custom-height bottom sheets or `UIScreen`-sized custom covers were found (the only fixed-height custom control is `SlideToUnlock`, §1).

---

## §5 Animation / performance risks at iPad sizes

- **`ControlledRevealModifier`** — lock/unlock route transition applies `blur(radius:10)` + scale to the entire LockScreen at screen size (`App/RootView.swift:142-151`, used :34). At 1366×1024@2x that's a ~4.7× iPhone-area offscreen pass for 0.35s. Worst realistic frame-drop candidate; consider reducing blur radius or skipping blur at regular width.
- **`PrivacyShield`** — fullscreen `.ultraThinMaterial` mounted on every inactive transition (`RootView.swift:164-171`). System material, Metal-backed — acceptable, just aware it now covers 2.4× the points.
- **`LooxCloudAnimationView`** — `TimelineView(.animation)` + 3 always-mounted Memoji video players + per-orb shadows (`BrandAnimation/LooxCloudAnimationView.swift:17, 143, 216-224`). Cost is bounded because every host caps the frame (252pt `WelcomeLandingView.swift:35`, 220pt `OnboardingFlow.swift:204`, 280pt `LooxWinkView.swift:28`) — **not** O(screen area). No action beyond the bloom-coverage bug (§1/§2 P1.5).
- **`LooxSwirlAnimationView`** — Canvas of 96 dots masked over an image scaled ×1.8 overscan (`DesignSystem/Components/LooxSwirlAnimationView.swift:59-70`); all call sites use fixed 130–176pt frames (`JoinVaultFlow.swift:170,274`, `WatchtowerEmptyState.swift:20-24`, `LanguageSwitchOverlay.swift:18`). Safe.
- **Wallpaper engine** — gated OFF (`VaultifyCore/Theme/WallpaperFeature.swift`, flat path `DesignSystem/Wallpaper/WallpaperView.swift:19-31`); the dormant decorative path carries a fullscreen `blur(28)` (`WallpaperView.swift:84`) — flag it in the re-enable checklist, not now.
- **`Space.gutter` uses `UIScreen.main`** (`DesignSystem/Tokens/Spacing.swift:28-29`) — the only `UIScreen.main` and the only hardcoded 414 in the app. Two defects: (a) it reads the *device* screen, not the window, so a 320pt Slide Over window still gets the 20pt "wide phone" gutter; (b) it's the wrong knob for regular width entirely (nav-bar layout margins on iPad are 20pt, so the value accidentally matches fullscreen iPad, but by luck). Fix alongside §2: derive from container/window width or size class.
- Tab bar / headers: glass is scoped to small chips and 44pt circles (`VaultTabBarBackground.swift:25-37`, `HomeHeaderBar.swift:139`), never full-width panes — no area-scaling risk.
- No other hardcoded 375/390/414/428 anywhere in app or core sources (verified by grep).

---

## §6 What the design docs already mandate

- **`docs/design-dna-standard.md:97-101` (Multi-device acceptance matrix)** — currently *iPhone-only*: "Widths: iPhone SE (375pt) and Pro Max (430pt)". There is **no iPad row**; the standard literally cannot fail an iPad layout today. It does already mandate the right *doctrine* to extend: "no squeezed grids; if 4 don't fit, use 2×2" and Dynamic-Type "layout reflows (grids → fewer columns) rather than shrinking text" (:101-105) — the symmetric rule ("if the row is too wide, add columns / clamp the column") is the natural amendment, plus new width checkpoints (e.g. 744, 834, 1024, 1366pt + Split View ½/⅓).
- **`docs/design-guidelines.md:69`** — tokens table documents `Space.gutter` ("adaptive screen margin 16/20, screen edges only — card interiors use `Space.s4`") and **already lists `Space.contentMax`** as a shipping token; the §2 mechanism is an extension of a documented token family, not a new concept.
- **Web spec** — `Design System/tokens/spacing.css:21` `--content-max: 430px` ("iPhone portrait content width cap"): the cross-platform token slot for the new width tiers.
- **`CLAUDE.md` (Design System section)** — codifies gutter = screen-edge-only and fixed card interiors; the clamp respects that split (clamp the column, keep `Space.s4` interiors).
- **`docs/app-feature-map-ui-ux.md:391-400`** — documents the multi-platform shell (tabs on compact, sidebar on regular) as shipped intent; the permanent-sidebar change (§3) is consistent with it, doc needs a one-line update for "pinned visible, no toggle".
- The DNA rules' "design for the LONGEST localized label (VI)" applies unchanged — width clamps must be tested with VI strings at 560pt, not just EN.

---

Status: DONE_WITH_CONCERNS
Summary: Full inventory delivered — onboarding/unlock and Home/Hub/ItemDetail are the hard breaks at regular width; the fix is one token-layer `.vaultContentWidth` clamp (560/640/960) with phased call sites, and the permanent sidebar is already implemented on disk with only compact→regular navigation-state loss as the open behavioral gap.
Concerns/Blockers: (1) `VaultSidebarView.swift` was modified by another session mid-audit — §3 reflects the current on-disk version; re-verify no further concurrent edits before acting. (2) The welcome/done launch-bloom under-coverage (`LooxLaunchResolver.swift:166`) is a functional animation bug at iPad sizes, independent of the width-clamp work. (3) Width numbers (560/640/960) are recommendations calibrated to existing Mac constraints (`MacHeaderBar.swift:37,129`); owner should confirm before rollout.
