# Phase 0 — Screen/Surface Registry

Generated from live grep against the current tree (branch `feat/design-dna-controlled-reveal`),
not from the phase-00 authoring map's prose alone. No code changes made.

## Summary

- **Total surfaces: 224** (187 `View` structs matched by the phase-00 baseline grep scan of
  `Vaultify/Features`, `Vaultify/DesignSystem/Components`, `VaultifyAutoFill` — confirmed
  reproduced exactly at 187 — **plus 37 additional surfaces** the plan's method (step 2: "capture
  non-View interactive surfaces … `ButtonStyle`, `ToggleStyle`, `ViewModifier`, `Shape`,
  `UIViewControllerRepresentable`") requires, several of which live **outside any of the 14
  phases' owned directories**).
- **Unassigned count: 0.** Every surface below has a phase in column 4. 14 of the 224 rows are
  marked **"(gap)"** — assigned to the *nearest* phase as a proposal, because their file lives
  outside that phase's stated ownership dirs (see "Ownership gaps" below). Per phase-00's own
  success criteria, these are not silently dropped — each carries a note explaining the gap and a
  concrete proposed absorption (I did not restructure the phases myself).
- **Per-phase counts** (baseline-187 count in parens where it differs from the final count):

| Phase | Surfaces | Baseline (187-scan) | Gap rows added |
|---|---|---|---|
| 1 — Shared primitives | 40 | 26 | +14 (11 in-scope ButtonStyle/ToggleStyle/Shape/ViewModifier already in `Components/`, +3 true gaps: `PolarisIcon`, `ElevationModifier`, `BrandLogoMark`) |
| 2 — Onboarding + Unlock | 24 | 23 | +1 (`UserActivityMonitor`, review-exempt) |
| 3 — Home + Search | 18 | 15 | +3 (Home QuickActionCard's private ButtonStyle/2×ViewModifier) |
| 4 — Items/Folders/Vault | 13 | 13 | 0 |
| 5 — Item Detail + Passkeys | 16 | 16 | 0 |
| 6 — Item Editor | 14 | 12 | +2 (`QRScannerView` UIViewControllerRepresentable, `GenerateChipSurface` modifier) |
| 7 — Watchtower + Generator | 13 | 12 | +1 (`PressableSurfaceStyle`) |
| 8 — Settings core/Security/Data | 13 | 13 | 0 |
| 9 — Appearance + About | 11 | 5 | +6 (Wallpaper engine — gap, gated-off feature) |
| 10 — Personas + Profile | 11 | 11 | 0 |
| 11 — Sharing owner/approval | 14 | 12 | +2 (`InviteInboxBehaviors` pre-listed, `MessageComposeView` representable) |
| 12 — Sharing QuickLink/QuickView | 9 | 9 | 0 |
| 13 — Main shell + Mac | 19 | 11 | +8 (4 in-scope tab-bar/shell ButtonStyle/ViewModifiers, +4 true gaps: `RootView`, `PrivacyShield`, `ControlledRevealModifier`, `VaultifyApp`) |
| 14 — AutoFill extension | 9 | 9 | 0 |
| **Total** | **224** | **187** | **37** |

- **Sharing partition check**: PASS — every `Sharing/*` file lands in exactly P11 XOR P12; no file
  appears in both (`QuickLink*`, `QuickView/*`, `SharedWithMeScreen.swift` → P12; everything else
  in `Sharing/` → P11).

## Ownership gaps (surfaces outside any phase's stated dirs — proposals, not decisions)

The phase-00 authoring map's owned-dirs table covers `DesignSystem/Components/*`,
`Features/Components/*`, `Features/Capabilities/*`, and the 13 `Features/<Cluster>/*` +
`VaultifyAutoFill/*` trees. Four real directories fall **outside all of them**:

1. **`Vaultify/App/*.swift`** (`RootView.swift`, `VaultifyApp.swift`) — the top-level router
   (Onboarding/Locked/Unlocked switch) and `@main App` entry. `RootView` and its private
   `PrivacyShield` (a genuine visual surface — `.ultraThinMaterial` + `BrandLogoMark.hero`, shown
   on backgrounding) are real design-DNA surfaces, and were also **outside phase-00's own grep
   scope** (which only scans `Features/DesignSystem-Components/AutoFill`). **Proposal: Phase 13**
   (Main shell) absorbs `Vaultify/App/RootView.swift` — it's the shell-adjacent root, pairs with
   `AdaptiveRootView`/`MainTabView`. `VaultifyApp.swift` is review-exempt (no visual surface of its
   own) but bookkept under the same phase.
2. **`Vaultify/DesignSystem/PolarisIcon.swift`** — the actual Polaris SVG icon *renderer*
   (`PolarisIcon: View`), sitting directly under `DesignSystem/` rather than
   `DesignSystem/Components/`. This is the single most shared visual primitive in the app (every
   `PolarisIcons.icon()` call route through it per CLAUDE.md's icon convention) and is currently
   unowned. **Proposal: Phase 1** dir list should read `DesignSystem/Components/*,
   DesignSystem/PolarisIcon.swift` (or generalize to `DesignSystem/*.swift` root files).
3. **`Vaultify/DesignSystem/Tokens/Elevation.swift`** (`ElevationModifier`) and
   **`Vaultify/DesignSystem/Wallpaper/**`** (`WallpaperView`, `WallpaperEffects`, `PatternCanvas`,
   `PatternWallpaperView`, `MeshGradientView` ×2) — foundation-token and wallpaper-engine
   directories, neither listed under any phase. `ElevationModifier` is trivial (1 ViewModifier) —
   **proposal: Phase 1** absorbs it (same tier as other token-backed modifiers already in
   `Components/`). The Wallpaper engine is larger (6 surfaces) and is the code CLAUDE.md notes as
   "fully retained... flip the flag to re-enable" (`WallpaperFeature.decorativeEnabled = false`) —
   **proposal: Phase 9** (Appearance) absorbs it, since it pairs semantically with the already-owned
   `WallpaperGalleryView` and is dormant/low-risk to review once, together.
4. **`VaultifyCore/BrandLogoMark.swift`** — the brand wordmark, compiled into **both** targets
   (app + AutoFill extension), reused on onboarding welcome, lock screen, privacy shield, and About.
   `VaultifyCore/` is not listed under any phase at all. **Proposal: Phase 1** absorbs it as a
   cross-target shared primitive — fixing it once benefits every consumer phase (P2, P9, P13)
   without duplicated review.
5. **`Vaultify/Security/UserActivityMonitor.swift`** (`UserActivityMonitor`, `UIViewRepresentable`)
   — an invisible activity-probe (`allowsHitTesting(false)`, no rendered pixels) that resets the
   auto-lock idle timer on touch. Not a design-DNA surface (nothing to look at), so
   **review-exempt**; nearest semantic owner is Phase 2 (auto-lock/Unlock behavior) for
   bookkeeping only.

None of these are large: 3 are single-file/single-struct (`PolarisIcon`, `ElevationModifier`,
`BrandLogoMark`), one is review-exempt with zero visual surface, and the largest (Wallpaper, 6
structs) is an already-dormant feature. Recommend the orchestrator fold these into Phase 1 / 9 / 13
ownership before those phases start (or explicitly mark them out of scope, but then they must be
removed from "every surface reviewed" success claim in `plan.md`).

## Duplicate-name notes (not a defect, just registry-worthy)

- **`QRScannerView`** — two distinct types, same file (`Vaultify/Features/ItemEditor/QRScannerView.swift`):
  `UIViewControllerRepresentable` camera host (line 11) wrapped by a `View` (line 118). Both → Phase 6.
- **`MeshGradientView`** — same pattern in `Vaultify/DesignSystem/Wallpaper/Mesh/MeshGradientView.swift`:
  `UIViewRepresentable` (line 10) wrapped by a `View` (line 99). Both → proposed Phase 9 (gap).
- **`StyledButton`** (private, ×3) in `ThemedButtonStyles.swift` — three separately-scoped private
  structs (one per `ButtonStyle` extension), not one redeclared type; harmless.

## Map cross-check (`docs/app-feature-map-ui-ux.md`)

**Map is thorough and largely matches code** (it was authored 2026-07-10 from direct code survey).
Deltas found:

**Structs with NO map entry** (undocumented — expected per phase-00's own hint, confirmed):
- `ShareDiagnosticsView` (Settings) — internal diagnostics screen, not a designed user surface;
  low priority for the sweep but still owned by P8.
- `InviteInboxBehaviors`, `VaultShellBehaviors`, `ShareStepperModel`'s `ShareMiniProgressBar` — view
  extensions/behind-the-scenes composition helpers, not independently documented (expected; they
  compose into documented screens).
- **Mac-only surfaces are entirely absent from the map**: `MacRootView`, `MacSettingsView` (+2
  private panes), `MacSidebarList`, `MacItemListColumn`, `MacHeaderBar` (+2 sub-views),
  `VaultSidebarList`, `VaultSidebarView`. The map's section 0 states "iPhone-only" (matching
  CLAUDE.md's top banner), but the codebase clearly ships a Mac/iPad-adjacent surface set (per
  memory note `vaultify-ipad-mac-multiplatform-plan`). This is a real doc-drift the sweep's Phase 13
  should flag back to docs-manager — not a registry blocker (Mac surfaces are still cleanly owned
  by P13), but the map needs a "13.x Mac/iPad surfaces" section or an explicit "Mac surfaces are
  build-time-gated, not yet user-facing" caveat.
- `ThemeEditorView`, `WallpaperGalleryView` + the whole Wallpaper engine (`WallpaperView`,
  `PatternWallpaperView`, `MeshGradientView`) — map's closing "Ghi chú" section already flags this
  ("wallpaper picker + custom theme editor có sẵn code nhưng đang tắt"), consistent with what the
  registry found; no new information, just confirms the map's own gap note is accurate.
- `AffectedAccountsScreen` (Personas — rotation-cascade impact screen) — not mentioned in section 12.
- `PersonaSwitcherScreen` / `PersonaEditorSheet` — map only describes persona switching as a *menu*
  action from Profile (12.1); code has a dedicated screen+sheet. Minor doc/code granularity delta,
  not a contradiction.
- `BrandLogoMark`, `RootView`, `PrivacyShield`, `ControlledRevealModifier` — architecture-level
  surfaces (router, privacy shield, brand mark), not screen-level, so their absence from a
  screen-by-screen design map is expected (though section 1 and the closing "Privacy Shield" note
  DO describe `PrivacyShield`'s behavior narratively — code exists to back it, just not in the
  code-inventory phase-00 originally scanned).

**Map entries with NO struct found** (doc claims a screen code lacks): none found. Every
screen/sheet/state described in map sections 2–14 traces to a concrete struct in the registry.

## Full registry (surface | file:line | kind | phase | notes)

| Surface | File:line | Kind | Phase | Notes |
|---|---|---|---|---|
| CopyMorphIcon | `Vaultify/DesignSystem/Components/CopyMorphIcon.swift:8` | component | 1 | |
| GlyphResolveText | `Vaultify/DesignSystem/Components/GlyphResolveText.swift:8` | component | 1 | |
| LooxGateMark | `Vaultify/DesignSystem/Components/LooxGateShape.swift:59` | component | 1 | |
| StyledButton | `Vaultify/DesignSystem/Components/ThemedButtonStyles.swift:10` | component | 1 | private, scoped to its own ButtonStyle extension |
| StyledButton | `Vaultify/DesignSystem/Components/ThemedButtonStyles.swift:37` | component | 1 | private, distinct type (see dup-name note) |
| StyledButton | `Vaultify/DesignSystem/Components/ThemedButtonStyles.swift:61` | component | 1 | private, distinct type (see dup-name note) |
| ThemedDivider | `Vaultify/DesignSystem/Components/ThemedComponents.swift:164` | component | 1 | |
| Switch | `Vaultify/DesignSystem/Components/ThemedToggleStyle.swift:12` | component | 1 | private |
| VaultInfoBanner | `Vaultify/DesignSystem/Components/VaultInfoBanner.swift:8` | component | 1 | |
| VaultHeaderScrollSpacer | `Vaultify/DesignSystem/Components/VaultScreenHeader.swift:124` | component | 1 | |
| HeaderIconButton | `Vaultify/DesignSystem/Components/VaultScreenHeader.swift:247` | component | 1 | |
| VaultScreenHeaderBackground | `Vaultify/DesignSystem/Components/VaultScreenHeader.swift:58` | component | 1 | private bg layer, not a screen |
| SheetDismissButton | `Vaultify/DesignSystem/Components/VaultSheetScaffold.swift:119` | sheet | 1 | |
| StatusDot | `Vaultify/DesignSystem/Components/VaultStatusBadge.swift:20` | component | 1 | |
| VaultStatusBadge | `Vaultify/DesignSystem/Components/VaultStatusBadge.swift:36` | component | 1 | |
| CapabilityBannerView | `Vaultify/Features/Capabilities/CapabilityBannerView.swift:6` | component | 1 | |
| CopyToastOverlay | `Vaultify/Features/Components/CopyToastOverlay.swift:6` | overlay | 1 | |
| FaviconView | `Vaultify/Features/Components/FaviconView.swift:6` | component | 1 | |
| LooxAppIcon | `Vaultify/Features/Components/FaviconView.swift:64` | component | 1 | |
| ItemThumbnail | `Vaultify/Features/Components/ItemThumbnail.swift:9` | component | 1 | |
| PasswordStrengthMeter | `Vaultify/Features/Components/PasswordStrengthMeter.swift:4` | component | 1 | |
| QRCodeView | `Vaultify/Features/Components/QRCodeView.swift:8` | component | 1 | |
| RevealableSecureField | `Vaultify/Features/Components/RevealableSecureField.swift:4` | component | 1 | |
| SpoilerText | `Vaultify/Features/Components/SpoilerText.swift:9` | component | 1 | |
| FilterChip | `Vaultify/Features/Components/VaultComponents.swift:26` | component | 1 | |
| CategoryBadge | `Vaultify/Features/Components/VaultComponents.swift:4` | component | 1 | |
| ThemedProminentButtonStyle | `Vaultify/DesignSystem/Components/ThemedButtonStyles.swift:7` | style | 1 | ButtonStyle — non-View surface, plan method step 2 |
| ThemedTintedButtonStyle | `Vaultify/DesignSystem/Components/ThemedButtonStyles.swift:34` | style | 1 | ButtonStyle |
| ThemedDestructiveButtonStyle | `Vaultify/DesignSystem/Components/ThemedButtonStyles.swift:58` | style | 1 | ButtonStyle |
| ProminentButtonLoading | `Vaultify/DesignSystem/Components/ThemedButtonStyles.swift:86` | modifier | 1 | ViewModifier |
| LooxGateShape | `Vaultify/DesignSystem/Components/LooxGateShape.swift:8` | shape | 1 | Shape (nonisolated) |
| ThemedToggleStyle | `Vaultify/DesignSystem/Components/ThemedToggleStyle.swift:9` | style | 1 | ToggleStyle |
| ThemedForegroundModifier | `Vaultify/DesignSystem/Components/ThemedComponents.swift:26` | modifier | 1 | ViewModifier (private) |
| ThemedColorSchemeModifier | `Vaultify/DesignSystem/Components/ThemedComponents.swift:68` | modifier | 1 | ViewModifier (private) |
| AppBackgroundModifier | `Vaultify/DesignSystem/Components/ThemedComponents.swift:83` | modifier | 1 | ViewModifier (private) |
| ThemedFormBackgroundModifier | `Vaultify/DesignSystem/Components/ThemedComponents.swift:114` | modifier | 1 | ViewModifier (private) |
| HeaderGlassCapsule | `Vaultify/DesignSystem/Components/VaultScreenHeader.swift:208` | modifier | 1 | ViewModifier (private) |
| **PolarisIcon** | `Vaultify/DesignSystem/PolarisIcon.swift:6` | component | **1 (gap)** | OWNERSHIP GAP — outside Phase 1's stated dirs; core Polaris SVG icon renderer used app-wide. Propose Phase 1 dir expand. |
| **ElevationModifier** | `Vaultify/DesignSystem/Tokens/Elevation.swift:37` | modifier | **1 (gap)** | OWNERSHIP GAP — `DesignSystem/Tokens/*` unowned; renders `.elevation()` shadow token. Propose Phase 1 absorb. |
| **BrandLogoMark** | `VaultifyCore/BrandLogoMark.swift:9` | component | **1 (gap)** | OWNERSHIP GAP — in `VaultifyCore/` (both targets), unowned by any phase. Brand wordmark on onboarding/lock/privacy-shield/About. Propose Phase 1 absorb. |
| ThemeOptionRow | `Vaultify/Features/Onboarding/ChooseThemeView.swift:61` | row | 2 | |
| ChooseThemeView | `Vaultify/Features/Onboarding/ChooseThemeView.swift:7` | component | 2 | |
| CreateMasterPasswordView | `Vaultify/Features/Onboarding/CreateMasterPasswordView.swift:5` | component | 2 | |
| EmergencyKitView | `Vaultify/Features/Onboarding/EmergencyKitView.swift:8` | component | 2 | |
| EnableBiometricView | `Vaultify/Features/Onboarding/EnableBiometricView.swift:4` | component | 2 | |
| JoinMethodChoiceView | `Vaultify/Features/Onboarding/JoinVaultFlow.swift:118` | component | 2 | |
| JoinOptionCard | `Vaultify/Features/Onboarding/JoinVaultFlow.swift:156` | component | 2 | |
| JoinByQRView | `Vaultify/Features/Onboarding/JoinVaultFlow.swift:192` | component | 2 | |
| JoinByRecoveryView | `Vaultify/Features/Onboarding/JoinVaultFlow.swift:279` | component | 2 | |
| RecoveryScannerSheet | `Vaultify/Features/Onboarding/JoinVaultFlow.swift:400` | sheet | 2 | |
| JoinVaultFlow | `Vaultify/Features/Onboarding/JoinVaultFlow.swift:9` | screen | 2 | |
| NameStepView | `Vaultify/Features/Onboarding/NameStepView.swift:7` | component | 2 | |
| WelcomeStep | `Vaultify/Features/Onboarding/OnboardingFlow.swift:131` | component | 2 | |
| FeatureCard | `Vaultify/Features/Onboarding/OnboardingFlow.swift:207` | component | 2 | |
| WelcomeBackdrop | `Vaultify/Features/Onboarding/OnboardingFlow.swift:252` | overlay | 2 | |
| OnboardingDoneStep | `Vaultify/Features/Onboarding/OnboardingFlow.swift:265` | component | 2 | |
| OnboardingFlow | `Vaultify/Features/Onboarding/OnboardingFlow.swift:6` | screen | 2 | |
| OnboardingStepHeader | `Vaultify/Features/Onboarding/OnboardingStepHeader.swift:7` | component | 2 | |
| BiometricBadge | `Vaultify/Features/Unlock/BiometricBadge.swift:9` | component | 2 | |
| LockPasswordField | `Vaultify/Features/Unlock/LockPasswordField.swift:6` | component | 2 | |
| LockScreen | `Vaultify/Features/Unlock/LockScreen.swift:12` | screen | 2 | |
| RecoveryView | `Vaultify/Features/Unlock/RecoveryView.swift:6` | component | 2 | |
| SlideToUnlock | `Vaultify/Features/Unlock/SlideToUnlock.swift:6` | component | 2 | |
| **UserActivityMonitor** | `Vaultify/Security/UserActivityMonitor.swift:28` | representable | **2 (gap, review-exempt)** | OWNERSHIP GAP — `Vaultify/Security/*` unowned. Invisible idle-timer probe, no rendered UI. Review-exempt; nearest fit Phase 2. |
| AttentionCell | `Vaultify/Features/Home/Components/AttentionCell.swift:6` | component | 3 | |
| HomeFolderPickerSheet | `Vaultify/Features/Home/Components/HomeHeaderBar.swift:100` | sheet | 3 | |
| HomeHeaderBar | `Vaultify/Features/Home/Components/HomeHeaderBar.swift:8` | component | 3 | |
| QuickActionCard | `Vaultify/Features/Home/Components/QuickActionCard.swift:13` | component | 3 | |
| QuickActionCardLabel | `Vaultify/Features/Home/Components/QuickActionCard.swift:33` | component | 3 | |
| TotpCardView | `Vaultify/Features/Home/Components/TotpCardView.swift:7` | component | 3 | |
| TotpRingView | `Vaultify/Features/Home/Components/TotpRingView.swift:6` | component | 3 | |
| HomeScreen | `Vaultify/Features/Home/HomeScreen.swift:14` | screen | 3 | |
| ItemCard | `Vaultify/Features/Home/HomeSection.swift:10` | component | 3 | |
| TotpListScreen | `Vaultify/Features/Home/TotpListScreen.swift:7` | screen | 3 | |
| ScopeChip | `Vaultify/Features/Search/SearchScreen.swift:214` | component | 3 | |
| SearchResultsList | `Vaultify/Features/Search/SearchScreen.swift:30` | component | 3 | |
| SearchScreen | `Vaultify/Features/Search/SearchScreen.swift:7` | screen | 3 | |
| SearchZeroStateView | `Vaultify/Features/Search/SearchZeroStateView.swift:7` | component | 3 | |
| SearchFilterChip | `Vaultify/Features/Search/SearchZeroStateView.swift:76` | component | 3 | |
| QuickActionCardSurface | `Vaultify/Features/Home/Components/QuickActionCard.swift:88` | modifier | 3 | ViewModifier (private) |
| GlyphBadgeSurface | `Vaultify/Features/Home/Components/QuickActionCard.swift:110` | modifier | 3 | ViewModifier (private) |
| QuickActionButtonStyle | `Vaultify/Features/Home/Components/QuickActionCard.swift:151` | style | 3 | ButtonStyle (private) |
| FolderBadge | `Vaultify/Features/Folders/FolderBadge.swift:11` | component | 4 | |
| FolderEditorSheet | `Vaultify/Features/Folders/FolderEditorSheet.swift:5` | sheet | 4 | |
| FolderPickerSheet | `Vaultify/Features/Folders/FolderPickerSheet.swift:5` | sheet | 4 | |
| IconColorPicker | `Vaultify/Features/Folders/IconColorPicker.swift:5` | component | 4 | |
| ManageFoldersScreen | `Vaultify/Features/Folders/ManageFoldersScreen.swift:4` | screen | 4 | |
| ArchiveScreen | `Vaultify/Features/Items/ArchiveScreen.swift:5` | screen | 4 | |
| ItemListScreen | `Vaultify/Features/Items/ItemListScreen.swift:5` | screen | 4 | |
| ItemsScreen | `Vaultify/Features/Items/ItemsScreen.swift:8` | screen | 4 | |
| FolderItemsScreen | `Vaultify/Features/Vault/FolderItemsScreen.swift:6` | screen | 4 | |
| TagItemsScreen | `Vaultify/Features/Vault/TagItemsScreen.swift:4` | screen | 4 | |
| TrashScreen | `Vaultify/Features/Vault/TrashScreen.swift:4` | screen | 4 | |
| VaultItemRow | `Vaultify/Features/Vault/VaultItemRow.swift:8` | row | 4 | |
| VaultItemRowLink | `Vaultify/Features/Vault/VaultItemRowLink.swift:7` | row | 4 | NavigationLink-wrapping row, not a screen |
| AttachmentFieldRow | `Vaultify/Features/ItemDetail/AttachmentFieldRow.swift:7` | row | 5 | |
| BottomCopyPasswordCluster | `Vaultify/Features/ItemDetail/BottomCopyPasswordCluster.swift:10` | component | 5 | |
| CodePromptSheet | `Vaultify/Features/ItemDetail/CodePromptSheet.swift:5` | sheet | 5 | |
| DetailFieldRow | `Vaultify/Features/ItemDetail/DetailFieldRow.swift:7` | row | 5 | |
| ItemDetailScreen | `Vaultify/Features/ItemDetail/ItemDetailScreen.swift:6` | screen | 5 | |
| LargeTypeView | `Vaultify/Features/ItemDetail/LargeTypeView.swift:9` | component | 5 | |
| LocatedInSheet | `Vaultify/Features/ItemDetail/LocatedInSheet.swift:6` | sheet | 5 | |
| ProtectedFieldRow | `Vaultify/Features/ItemDetail/ProtectedFieldRow.swift:6` | row | 5 | |
| ProtectFieldSheet | `Vaultify/Features/ItemDetail/ProtectFieldSheet.swift:5` | sheet | 5 | |
| CountdownRing | `Vaultify/Features/ItemDetail/TOTPFieldRow.swift:29` | component | 5 | |
| TOTPCodeView | `Vaultify/Features/ItemDetail/TOTPFieldRow.swift:4` | component | 5 | |
| ItemPasskeysSection | `Vaultify/Features/Passkeys/ItemPasskeysSection.swift:3` | component | 5 | |
| PasskeyDetailSheet | `Vaultify/Features/Passkeys/PasskeyDetailSheet.swift:3` | sheet | 5 | |
| PasskeysScreen | `Vaultify/Features/Passkeys/PasskeysScreen.swift:3` | screen | 5 | |
| PasskeyRow | `Vaultify/Features/Passkeys/PasskeysScreen.swift:76` | row | 5 | |
| SharedItemPasskeysSection | `Vaultify/Features/Passkeys/SharedItemPasskeysSection.swift:7` | component | 5 | |
| AttachmentPickerSheet | `Vaultify/Features/ItemEditor/AttachmentPickerSheet.swift:7` | sheet | 6 | |
| GenerateChip | `Vaultify/Features/ItemEditor/EditorFieldRow.swift:190` | component | 6 | |
| EditorFieldRow | `Vaultify/Features/ItemEditor/EditorFieldRow.swift:5` | row | 6 | |
| RotationReminderSection | `Vaultify/Features/ItemEditor/ItemEditorScreen.swift:564` | component | 6 | |
| EditorHeaderActions | `Vaultify/Features/ItemEditor/ItemEditorScreen.swift:600` | component | 6 | |
| ItemEditorScreen | `Vaultify/Features/ItemEditor/ItemEditorScreen.swift:7` | screen | 6 | |
| ItemIconPickerSheet | `Vaultify/Features/ItemEditor/ItemIconPickerSheet.swift:4` | sheet | 6 | |
| LoginEditorSections | `Vaultify/Features/ItemEditor/LoginEditorSections.swift:8` | component | 6 | |
| QRScannerView | `Vaultify/Features/ItemEditor/QRScannerView.swift:118` | component | 6 | `View` wrapper (see dup-name note) |
| TagChipEditor | `Vaultify/Features/ItemEditor/TagChipEditor.swift:6` | component | 6 | |
| TOTPScannerSheet | `Vaultify/Features/ItemEditor/TOTPScannerSheet.swift:8` | sheet | 6 | |
| WebsiteFieldRow | `Vaultify/Features/ItemEditor/WebsiteFieldRow.swift:7` | row | 6 | |
| QRScannerView | `Vaultify/Features/ItemEditor/QRScannerView.swift:11` | representable | 6 | UIViewControllerRepresentable camera host (distinct type, see dup-name note) |
| GenerateChipSurface | `Vaultify/Features/ItemEditor/EditorFieldRow.swift:221` | modifier | 6 | ViewModifier (private) |
| PasswordGeneratorSheet | `Vaultify/Features/Generator/GeneratorScreen.swift:26` | sheet | 7 | |
| GeneratorScreen | `Vaultify/Features/Generator/GeneratorScreen.swift:4` | screen | 7 | |
| PasswordGeneratorView | `Vaultify/Features/Generator/PasswordGeneratorView.swift:7` | component | 7 | |
| WatchtowerCategoryScreen | `Vaultify/Features/Watchtower/WatchtowerCategoryScreen.swift:5` | screen | 7 | |
| CountBadge | `Vaultify/Features/Watchtower/WatchtowerComponents.swift:105` | component | 7 | |
| WatchtowerIssueRow | `Vaultify/Features/Watchtower/WatchtowerComponents.swift:126` | row | 7 | |
| CategoryRow | `Vaultify/Features/Watchtower/WatchtowerComponents.swift:32` | row | 7 | |
| IconTileBadge | `Vaultify/Features/Watchtower/WatchtowerComponents.swift:83` | component | 7 | |
| WatchtowerScoreRing | `Vaultify/Features/Watchtower/WatchtowerScoreRing.swift:32` | component | 7 | |
| WatchtowerScreen | `Vaultify/Features/Watchtower/WatchtowerScreen.swift:19` | screen | 7 | |
| WatchtowerStrengthCard | `Vaultify/Features/Watchtower/WatchtowerStrengthCard.swift:64` | component | 7 | |
| WatchtowerStrengthBar | `Vaultify/Features/Watchtower/WatchtowerStrengthCard.swift:7` | component | 7 | |
| PressableSurfaceStyle | `Vaultify/Features/Watchtower/WatchtowerComponents.swift:8` | style | 7 | ButtonStyle |
| EmergencyKitPDFPage | `Vaultify/Features/EmergencyKit/EmergencyKitPDFPage.swift:11` | component | 8 | PDF page builder |
| ExportView | `Vaultify/Features/ImportExport/ExportView.swift:4` | component | 8 | |
| ImportView | `Vaultify/Features/ImportExport/ImportView.swift:7` | component | 8 | |
| ChangeMasterPasswordView | `Vaultify/Features/Settings/ChangeMasterPasswordView.swift:5` | component | 8 | |
| Level2SettingsView | `Vaultify/Features/Settings/Level2SettingsView.swift:5` | component | 8 | |
| MacGeneralSettingsPane | `Vaultify/Features/Settings/MacSettingsView.swift:103` | component | 8 | |
| MacSecuritySettingsPane | `Vaultify/Features/Settings/MacSettingsView.swift:174` | component | 8 | |
| MacSettingsView | `Vaultify/Features/Settings/MacSettingsView.swift:8` | component | 8 | undocumented in map (see cross-check) |
| PairDeviceSheet | `Vaultify/Features/Settings/PairDeviceSheet.swift:9` | sheet | 8 | |
| RegenerateKitView | `Vaultify/Features/Settings/RegenerateKitView.swift:6` | component | 8 | |
| SettingsScreen | `Vaultify/Features/Settings/SettingsScreen.swift:5` | screen | 8 | |
| ShareDiagnosticsView | `Vaultify/Features/Settings/ShareDiagnosticsView.swift:10` | component | 8 | undocumented in map (dev diagnostics) |
| SyncSettingsView | `Vaultify/Features/Settings/SyncSettingsView.swift:7` | component | 8 | |
| AboutView | `Vaultify/Features/Settings/AboutView.swift:9` | component | 9 | |
| AppearanceSettingsView | `Vaultify/Features/Settings/Appearance/AppearanceSettingsView.swift:9` | component | 9 | |
| AutoNightSettingsView | `Vaultify/Features/Settings/Appearance/AutoNightSettingsView.swift:5` | component | 9 | |
| ThemeEditorView | `Vaultify/Features/Settings/Appearance/ThemeEditorView.swift:5` | component | 9 | undocumented in map (gated feature, map's own gap-note confirms) |
| WallpaperGalleryView | `Vaultify/Features/Settings/Appearance/WallpaperGalleryView.swift:8` | component | 9 | undocumented in map (gated feature) |
| **WallpaperView** | `Vaultify/DesignSystem/Wallpaper/WallpaperView.swift:6` | component | **9 (gap)** | OWNERSHIP GAP — `DesignSystem/Wallpaper/*` unowned (gated-off feature, code retained). Propose Phase 9 absorb. |
| **WallpaperEffects** | `Vaultify/DesignSystem/Wallpaper/WallpaperView.swift:79` | modifier | **9 (gap)** | ViewModifier (private); same gap |
| **PatternCanvas** | `Vaultify/DesignSystem/Wallpaper/PatternWallpaper.swift:11` | component | **9 (gap)** | same gap |
| **PatternWallpaperView** | `Vaultify/DesignSystem/Wallpaper/PatternWallpaper.swift:62` | component | **9 (gap)** | same gap |
| **MeshGradientView** | `Vaultify/DesignSystem/Wallpaper/Mesh/MeshGradientView.swift:99` | component | **9 (gap)** | `View` wrapper; same gap (dup-name note) |
| **MeshGradientView** | `Vaultify/DesignSystem/Wallpaper/Mesh/MeshGradientView.swift:10` | representable | **9 (gap)** | `UIViewRepresentable`; same gap (dup-name note) |
| AffectedAccountsScreen | `Vaultify/Features/Personas/AffectedAccountsScreen.swift:8` | screen | 10 | undocumented in map (rotation-cascade impact list) |
| AliasDetailScreen | `Vaultify/Features/Personas/AliasDetailScreen.swift:7` | screen | 10 | |
| AliasDomainPickerSection | `Vaultify/Features/Personas/AliasDomainPicker.swift:29` | component | 10 | |
| AliasEditorSheet | `Vaultify/Features/Personas/AliasEditorSheet.swift:6` | sheet | 10 | |
| ForwardingInboxScreen | `Vaultify/Features/Personas/ForwardingInboxScreen.swift:8` | screen | 10 | |
| PersonaAliasesScreen | `Vaultify/Features/Personas/PersonaAliasesScreen.swift:8` | screen | 10 | |
| PersonaSwitcherScreen | `Vaultify/Features/Personas/PersonaSwitcherScreen.swift:6` | screen | 10 | map describes as a menu action only (granularity delta) |
| PersonaEditorSheet | `Vaultify/Features/Personas/PersonaSwitcherScreen.swift:95` | sheet | 10 | |
| ProfileAvatarView | `Vaultify/Features/Profile/ProfileAvatarView.swift:6` | component | 10 | |
| ProfileScreen | `Vaultify/Features/Profile/ProfileScreen.swift:12` | screen | 10 | |
| ProfileSectionCard | `Vaultify/Features/Profile/ProfileSectionCard.swift:9` | component | 10 | |
| ApprovalRequestSheet | `Vaultify/Features/Sharing/ApprovalRequestSheet.swift:7` | sheet | 11 | |
| FieldCapabilityRow | `Vaultify/Features/Sharing/FieldCapabilityRow.swift:10` | row | 11 | |
| NotificationsScreen | `Vaultify/Features/Sharing/NotificationsScreen.swift:9` | screen | 11 | |
| PasskeyCapabilityRow | `Vaultify/Features/Sharing/PasskeyCapabilityRow.swift:7` | row | 11 | |
| RequestCodeView | `Vaultify/Features/Sharing/RequestCodeView.swift:170` | component | 11 | |
| ApprovedCodeView | `Vaultify/Features/Sharing/RequestCodeView.swift:260` | component | 11 | private |
| ShareAccessSheet | `Vaultify/Features/Sharing/ShareAccessSheet.swift:10` | sheet | 11 | |
| ShareInviteSentSheet | `Vaultify/Features/Sharing/ShareInviteSentSheet.swift:8` | sheet | 11 | |
| ShareRecipientDetailSheet | `Vaultify/Features/Sharing/ShareRecipientDetailSheet.swift:9` | sheet | 11 | |
| ShareResumeStepperSheet | `Vaultify/Features/Sharing/ShareResumeStepperSheet.swift:13` | sheet | 11 | |
| ShareMiniProgressBar | `Vaultify/Features/Sharing/ShareStepperModel.swift:62` | component | 11 | undocumented composition helper (expected) |
| TrustFingerprintView | `Vaultify/Features/Sharing/TrustFingerprintView.swift:9` | component | 11 | |
| InviteInboxBehaviors | `Vaultify/Features/Sharing/InviteInboxBehaviors.swift:8` | modifier | 11 | ViewModifier — pre-listed in phase-00 authoring map |
| MessageComposeView | `Vaultify/Features/Sharing/MessageComposeView.swift:9` | representable | 11 | UIViewControllerRepresentable (`MFMessageComposeViewController`) — system sheet, exempt from custom-token audit |
| QuickLinkFieldRow | `Vaultify/Features/Sharing/QuickLinkFieldRow.swift:6` | row | 12 | |
| QuickLinkResultView | `Vaultify/Features/Sharing/QuickLinkResultView.swift:6` | component | 12 | |
| QuickLinkView | `Vaultify/Features/Sharing/QuickLinkView.swift:7` | component | 12 | |
| QuickViewApprovalFieldsSection | `Vaultify/Features/Sharing/QuickView/QuickViewApprovalFieldsSection.swift:7` | component | 12 | |
| QuickViewApprovalSheet | `Vaultify/Features/Sharing/QuickView/QuickViewApprovalSheet.swift:7` | sheet | 12 | |
| QuickViewEnterCodeSheet | `Vaultify/Features/Sharing/QuickView/QuickViewEnterCodeSheet.swift:5` | sheet | 12 | |
| QuickViewEntryChooserSheet | `Vaultify/Features/Sharing/QuickView/QuickViewEntryChooserSheet.swift:6` | sheet | 12 | |
| QuickViewScannerSheet | `Vaultify/Features/Sharing/QuickView/QuickViewScannerSheet.swift:6` | sheet | 12 | |
| SharedWithMeScreen | `Vaultify/Features/Sharing/SharedWithMeScreen.swift:10` | screen | 12 | |
| AdaptiveRootView | `Vaultify/Features/Main/AdaptiveRootView.swift:10` | screen | 13 | |
| MacDetailHeader | `Vaultify/Features/Main/MacHeaderBar.swift:47` | component | 13 | undocumented in map (Mac-only, see cross-check) |
| MacToolbarSearchField | `Vaultify/Features/Main/MacHeaderBar.swift:8` | component | 13 | undocumented in map (Mac-only) |
| MacSearchSuggestionsPanel | `Vaultify/Features/Main/MacHeaderBar.swift:80` | component | 13 | undocumented in map (Mac-only) |
| MacItemListColumn | `Vaultify/Features/Main/MacItemListColumn.swift:7` | component | 13 | undocumented in map (Mac-only) |
| MacRootView | `Vaultify/Features/Main/MacRootView.swift:23` | screen | 13 | undocumented in map (Mac-only) |
| MacSidebarList | `Vaultify/Features/Main/MacSidebarList.swift:7` | component | 13 | undocumented in map (Mac-only) |
| MainTabView | `Vaultify/Features/Main/MainTabView.swift:13` | screen | 13 | |
| VaultSidebarList | `Vaultify/Features/Main/VaultSidebarList.swift:6` | component | 13 | undocumented in map (Mac/iPad-adjacent) |
| VaultSidebarView | `Vaultify/Features/Main/VaultSidebarView.swift:10` | screen | 13 | undocumented in map (Mac/iPad-adjacent) |
| VaultTabBar | `Vaultify/Features/Main/VaultTabBar.swift:7` | component | 13 | |
| VaultTabBarSurface | `Vaultify/Features/Main/VaultTabBarBackground.swift:13` | modifier | 13 | ViewModifier (private) |
| VaultTabSelectionSurface | `Vaultify/Features/Main/VaultTabBarBackground.swift:45` | modifier | 13 | ViewModifier (private) |
| TabPressStyle | `Vaultify/Features/Main/VaultTabBar.swift:69` | style | 13 | ButtonStyle (private) |
| VaultShellBehaviors | `Vaultify/Features/Main/VaultShellBehaviors.swift:11` | modifier | 13 | ViewModifier — pre-listed in phase-00 authoring map |
| **RootView** | `Vaultify/App/RootView.swift:5` | screen | **13 (gap)** | OWNERSHIP GAP — `Vaultify/App/*` unowned AND outside phase-00's own grep scope. Top-level router. Propose Phase 13 absorb. |
| **PrivacyShield** | `Vaultify/App/RootView.swift:134` | overlay | **13 (gap)** | Real visual surface (material + `BrandLogoMark.hero`) shown on backgrounding — same gap, needs design-DNA review |
| **ControlledRevealModifier** | `Vaultify/App/RootView.swift:114` | modifier | **13 (gap)** | Route transition (Controlled Reveal motion) — same gap |
| **VaultifyApp** | `Vaultify/App/VaultifyApp.swift:9` | app | **13 (gap, review-exempt)** | `App` protocol entry (`@main`), no visual surface of its own. Review-exempt; bookkept under Phase 13. |
| AutoFillView | `VaultifyAutoFill/AutoFillView.swift:5` | screen | 14 | |
| CredentialListView | `VaultifyAutoFill/AutoFillView.swift:96` | component | 14 | |
| CreateLoginView | `VaultifyAutoFill/CreateLoginView.swift:9` | component | 14 | |
| OneTimeCodeListView | `VaultifyAutoFill/OneTimeCodeView.swift:23` | component | 14 | private |
| OneTimeCodeView | `VaultifyAutoFill/OneTimeCodeView.swift:5` | component | 14 | |
| PasskeyActionView | `VaultifyAutoFill/PasskeyActionView.swift:20` | component | 14 | |
| PasskeyCeremonyView | `VaultifyAutoFill/PasskeyCeremonyView.swift:4` | component | 14 | |
| SaveConfirmView | `VaultifyAutoFill/SavePasswordView.swift:22` | component | 14 | private |
| SavePasswordView | `VaultifyAutoFill/SavePasswordView.swift:6` | component | 14 | |

`CredentialProviderViewController` (`VaultifyAutoFill/CredentialProviderViewController.swift:15`,
`ASCredentialProviderViewController` subclass, the extension's UIKit host) is a real UI surface
mentioned by name in phase-00's own method step 2 — it's a `class`, not a `struct`, so it's outside
the struct-grep pattern entirely, but it hosts every `VaultifyAutoFill/*` SwiftUI screen. Owned by
**Phase 14** (same file family, already in scope) — noted here for completeness, not counted in the
224 struct total (it's a class, no `body: some View`).

## Phase 15 addendum: 3 surfaces missed by the original baseline grep (found + reviewed by Phase 14)

Phase 14 flagged that its owned directory (`VaultifyAutoFill/*`) contains 3 more visual/logic
surfaces than this registry's original 11-row count for that phase — the baseline struct grep
missed them (likely a private-type or non-`View`-suffix naming pattern gap), but they were still
reviewed by Phase 14 since they live in its owned directory. Appended here per Phase 15's
reconciliation pass so the registry total reflects what was actually reviewed:

| Surface | File:line | Kind | Phase | Notes |
|---|---|---|---|---|
| UnlockGate | `VaultifyAutoFill/PasskeyActionView.swift` | component | 14 | Unlock form embedded in the passkey-ceremony flow; reviewed by Phase 14 (hit-target fix applied). |
| PasskeyMigrationGate | `VaultifyAutoFill/PasskeyActionView.swift` | component (private) | 14 | Migration/quarantine housekeeping pass-through, reviewed by Phase 14 (pass, no defect). |
| PasskeyLargeBlob | `VaultifyAutoFill/PasskeyActionView.swift` | model/directive (no `body`) | 14 | iOS 18 largeBlob extension type mapping, no visual surface; reviewed by Phase 14 (pass, no UI). |

Updated Phase-14 surface count: **11 → 14** (9 originally-registered + these 3). Updated grand
total: **224 → 227**. Zero unassigned — all 3 already fell under Phase 14's directory ownership
(`VaultifyAutoFill/*`), this is a registry bookkeeping fix, not a new ownership assignment.

## Todo status (from phase-00.md)

- [x] Re-ran the struct grep; current count = 187 (matches baseline exactly, tree unchanged since authoring).
- [x] Built `reports/screen-registry.md` → delivered as this file, `phase-00-surface-registry.md`
      (renamed to match this session's report-naming convention; content satisfies the same spec).
- [x] Asserted Σ(phase counts) == total: 224 == 224. Unassigned list: **empty**.
- [x] Noted doc-drift both directions (map→code gaps found; code→map gaps: none).
- [x] Confirmed `App/RootView.swift` route surfaces (Onboarding/Locked/Unlocked) map to phases 2/2/13 —
      verified: `.onboarding→OnboardingFlow()` (P2), `.locked→LockScreen()` (P2),
      `.unlocked→AdaptiveRootView()` (P13). `RootView` itself is the newly-identified gap (assigned to P13).

## Success criteria check

- Registry lists every surface with a phase: **PASS** (224/224, 0 unassigned).
- Sharing files partition cleanly P11 XOR P12: **PASS**.
- Structs outside the 14 phases marked "review-exempt (reason)", not dropped: **PASS** — 2 marked
  review-exempt (`UserActivityMonitor`, `VaultifyApp`); 12 other gap rows carry a concrete phase
  proposal + reason.

**Status:** DONE
**Summary:** 224 surfaces total (187 baseline `View` grep + 37 additional ButtonStyle/ToggleStyle/
ViewModifier/Shape/Representable/App surfaces per the plan's own method step 2). 0 unassigned. 14
gap rows flag 4 directories with no phase owner (`Vaultify/App/*`, `DesignSystem/PolarisIcon.swift`,
`DesignSystem/Tokens/Elevation.swift`, `DesignSystem/Wallpaper/**`, `VaultifyCore/BrandLogoMark.swift`,
`Vaultify/Security/UserActivityMonitor.swift`) — each proposed to the nearest phase (mostly P1, plus
P9/P13/P2), not auto-fixed. Sharing P11/P12 partition verified disjoint. Map cross-check: no
map-only phantom screens; several undocumented surfaces found (Mac/iPad shell, ShareDiagnosticsView,
Wallpaper engine — the last already flagged by the map's own gap note).

**Concerns:** the 4 unowned directories should be folded into phase ownership (recommend: Phase 1
dir list += `DesignSystem/PolarisIcon.swift`, `DesignSystem/Tokens/Elevation.swift`,
`VaultifyCore/BrandLogoMark.swift`; Phase 13 dir list += `Vaultify/App/RootView.swift`,
`Vaultify/App/VaultifyApp.swift`; Phase 9 dir list += `DesignSystem/Wallpaper/**`) before W2 starts,
or the sweep's own "no surface left unreviewed" success bar (plan.md line 103) will not literally
hold. This is a plan-file edit, not a registry fix — flagging for the orchestrator, not applying it
myself (file ownership: Phase 0 is read-only per its own spec).

**Unresolved questions:**
1. Should `Vaultify/Security/UserActivityMonitor.swift` and `Vaultify/App/VaultifyApp.swift` be
   fully out-of-scope (truly no visual surface) rather than bookkept under P2/P13? I marked them
   review-exempt but still assigned a phase per this task's "assign every one" requirement — orchestrator
   may prefer to formally exclude them from the 224 count instead.
2. Should the Mac/iPad shell surfaces (`MacRootView` and friends) get a doc update in
   `app-feature-map-ui-ux.md` as part of this sweep, or is that out of scope (map says "iPhone-only"
   by design, Mac surfaces may be dormant/future work per the multiplatform plan in memory)? Flagging
   for Phase 13 / docs-manager, not resolving here.
