# Phase 0 — Screen Inventory Verification & Registry

**Priority**: P1 (blocking) · **Status**: pending · **Parallel**: W0, alone, before everything.

## Protagonist
Prove the plan cannot fail its own standard: EVERY renderable surface (screen, sheet, row,
component-surface) in the app maps to exactly ONE later phase. An unassigned surface = plan FAIL.

## Deliverable
`reports/screen-registry.md` — one row per `View` struct: `struct | file:line | cluster/feature | owning phase`.
Plus a **coverage assertion** at the bottom: `total structs = Σ(per-phase counts)`, and an explicit
list of any struct NOT covered by phases 1–14 (must be empty to pass).

## Method (no code changes)
1. Enumerate every surface:
   ```
   grep -rnE 'struct [A-Za-z0-9_]+ *:.*\bView\b' Vaultify/Features Vaultify/DesignSystem/Components VaultifyAutoFill
   ```
   (baseline count at authoring time = **187** structs; re-run — the tree may have moved.)
2. Also capture non-View interactive surfaces that render UI: `ButtonStyle`, `ToggleStyle`,
   `ViewModifier`, `Shape`, PDF page builders, and any `UIViewControllerRepresentable`
   (`QRScannerView`, camera, `CredentialProviderViewController` host). Assign each to a phase.
3. Cross-check `docs/app-feature-map-ui-ux.md` sections 2–14 against the struct list. Flag:
   - screens in the map with NO struct (doc drift), and
   - structs with NO map entry (undocumented surface) — e.g. Mac-only surfaces, `ShareDiagnosticsView`,
     `InviteInboxBehaviors`, `VaultShellBehaviors`, `ShareStepperModel` view extensions.
4. Assign each struct to its owning phase per the map below. Verify DISJOINT ownership (no struct in
   two phases; every `Sharing/` file lands in P11 XOR P12; `Settings/Appearance/` → P9, rest → P8).

## Authoring-time assignment map (verify, then freeze in registry)

| Phase | Dirs owned | View-struct files (from `grep -rl`) |
|---|---|---|
| 1 | `DesignSystem/Components/*`, `Features/Components/*`, `Capabilities/*` | ThemedButtonStyles, GlyphResolveText, LooxGateShape, VaultStatusBadge, CopyMorphIcon, ThemedComponents, ThemedToggleStyle, VaultInfoBanner, VaultSheetScaffold, VaultScreenHeader · CopyToastOverlay, RevealableSecureField, ItemThumbnail, VaultComponents, PasswordStrengthMeter, FaviconView, SpoilerText, QRCodeView · CapabilityBannerView |
| 2 | `Onboarding/*`, `Unlock/*` | EnableBiometricView, EmergencyKitView, OnboardingStepHeader, OnboardingFlow, ChooseThemeView, NameStepView, CreateMasterPasswordView, JoinVaultFlow · BiometricBadge, SlideToUnlock, LockPasswordField, LockScreen, RecoveryView |
| 3 | `Home/*`, `Search/*` | TotpListScreen, TotpCardView, HomeScreen, HomeSection, QuickActionCard, TotpRingView, HomeHeaderBar, AttentionCell · SearchZeroStateView, SearchScreen |
| 4 | `Items/*`, `Folders/*`, `Vault/*` | ItemsScreen, ItemListScreen, ArchiveScreen · FolderEditorSheet, FolderBadge, FolderPickerSheet, IconColorPicker, ManageFoldersScreen · TagItemsScreen, VaultItemRowLink, FolderItemsScreen, VaultItemRow, TrashScreen |
| 5 | `ItemDetail/*`, `Passkeys/*` | AttachmentFieldRow, ItemDetailScreen, LocatedInSheet, ProtectedFieldRow, ProtectFieldSheet, SharedAccessGateView, CodePromptSheet, DetailFieldRow, BottomCopyPasswordCluster, TOTPFieldRow, LargeTypeView · ItemPasskeysSection, PasskeyDetailSheet, SharedItemPasskeysSection, PasskeysScreen |
| 6 | `ItemEditor/*` | EditorFieldRow, ItemEditorScreen, QRScannerView, AttachmentPickerSheet, LoginEditorSections, TagChipEditor, TOTPScannerSheet, ItemIconPickerSheet, WebsiteFieldRow |
| 7 | `Watchtower/*`, `Generator/*` | WatchtowerCategoryScreen, WatchtowerStrengthCard, WatchtowerScreen, WatchtowerComponents, WatchtowerScoreRing · PasswordGeneratorView, GeneratorScreen |
| 8 | `Settings/*` (not `Appearance/`), `ImportExport/*`, `EmergencyKit/*` | SettingsScreen, ShareDiagnosticsView, SyncSettingsView, ChangeMasterPasswordView, Level2SettingsView, MacSettingsView, RegenerateKitView, PairDeviceSheet · ExportView, ImportView · EmergencyKitPDFPage |
| 9 | `Settings/Appearance/*`, `Settings/AboutView.swift` | WallpaperGalleryView, AutoNightSettingsView, ThemeEditorView, AppearanceSettingsView · AboutView |
| 10 | `Personas/*`, `Profile/*` | AliasDetailScreen, AliasDomainPicker, PersonaAliasesScreen, AffectedAccountsScreen, PersonaSwitcherScreen, ForwardingInboxScreen, AliasEditorSheet · ProfileScreen, ProfileSectionCard, ProfileAvatarView |
| 11 | `Sharing/*` (not `QuickView/`, `QuickLink*`, `SharedWithMeScreen`) | ShareInviteSentSheet, PasskeyCapabilityRow, ShareAccessSheet, NotificationsScreen, ApprovalRequestSheet, InviteInboxBehaviors, TrustFingerprintView, RequestCodeView, ShareRecipientDetailSheet, FieldCapabilityRow, ShareResumeStepperSheet, ShareStepperModel |
| 12 | `Sharing/QuickLink*`, `Sharing/QuickView/*`, `Sharing/SharedWithMeScreen.swift` | QuickLinkView, QuickLinkResultView, QuickLinkFieldRow · QuickViewApprovalFieldsSection, QuickViewApprovalSheet, QuickViewScannerSheet, QuickViewEntryChooserSheet, QuickViewEnterCodeSheet · SharedWithMeScreen |
| 13 | `Main/*` | MainTabView, VaultTabBarBackground, MacRootView, VaultTabBar, VaultSidebarList, MacSidebarList, VaultShellBehaviors, MacItemListColumn, VaultSidebarView, MacHeaderBar, AdaptiveRootView, VaultTabItem |
| 14 | `VaultifyAutoFill/*` | SavePasswordView, CreateLoginView, PasskeyActionView, PasskeyLargeBlob, UnlockGate, PasskeyCeremonyView, OneTimeCodeView, AutoFillView, CredentialProviderViewController (+SilentPasskeys host) |

## Todo
- [ ] Re-run the struct grep; record exact current count (baseline 187).
- [ ] Build `reports/screen-registry.md` (struct | file:line | phase).
- [ ] Assert Σ(phase counts) == total; list unassigned (must be empty).
- [ ] Note doc-drift: map screens missing structs, and structs missing map entries.
- [ ] Confirm `App/RootView.swift` route surfaces (Onboarding/Locked/Unlocked) map to phases 2/2/13.

## Success criteria
- Registry lists every surface with a phase; unassigned list is EMPTY.
- Sharing files partition cleanly between P11 and P12 (no overlap).
- Any struct outside the 14 phases (e.g. a stray preview-only helper) is explicitly marked
  "review-exempt (reason)" — not silently dropped.

## Risk
| Risk | L×I | Mitigation |
|---|---|---|
| Tree moved since authoring (structs added/renamed) | Med×Med | Registry is generated from live grep, not this file; this map is a checklist not the source of truth |
| A struct legitimately spans two features | Low×Med | Assign to the phase that owns its FILE; the other phase reads it |
| Preview-only / dead structs inflate count | Med×Low | Mark `#Preview`/`_Previews` structs review-exempt |

## Next
Unblocks Phase 1 (which must land before W2). Phase 0 gates the whole sweep: no W2 phase starts until
the registry shows zero unassigned surfaces.
</content>
