# Adversarial UI/UX Sweep — Consolidated Findings & Fixes Report

Merges all 15 phase reports (`phase-00` through `phase-14-findings.md` + this Phase 15 pass) for
`plans/260711-0024-adversarial-ui-sweep-all-screens/`. Scope: 227 surfaces (224 original registry
+ 3 reconciled in Phase 15, see `phase-00-surface-registry.md` addendum), 100% reviewed against
`docs/design-dna-standard.md`.

## 1. Totals per phase

| # | Phase | Surfaces | Findings | Fixed | Deferred | Severity mix (fixed) |
|---|---|---|---|---|---|---|
| 0 | Registry (no code) | 224→227 | — | — | 4 dir-ownership gaps (all absorbed: 3→P1, 1→P9/P13/P2 split) | — |
| 1 | Shared primitives | 40 | 19 (9 pass1 + 10 geometry-ripple) | 17 | 2 declined (caption2 tier, PolarisIcon default) | 1 high, ~10 medium, ~6 low |
| 2 | Onboarding + Unlock | 24 | 21 (16 defects + 5 AX-XXL scroll fixes) | 21 | LockScreen AX-XXL scroll-safety (regression-risk, flagged for device QA) | 2 high, ~17 medium, 2 low |
| 3 | Home + Search | 18 | 12 | 12 | TotpCardView 14pt inset, shadow-bleed padding, divider inset (all documented, zero-risk) | 2 high, 6 medium, 4 low |
| 4 | Items + Folders + Vault | 20 | 20 | 17 | 30pt/50pt tokens un-named (values consistent, just unlabeled) | 3 high, 9 medium, 5 low |
| 5 | Item Detail + Passkeys | 17 (16+1) | 17 | 15 | ThemedCompactButtonStyle request; cross-phase toggle-haptic gap (resolved below) | 4 high, 7 medium, 4 low |
| 6 | Item Editor | 12 (+2) | 10 | 9 | Space-pill hit-target (cross-phase w/ P5); multiline-protected masking; `.padding(.vertical,2)` convention; `PasswordAudit.swift` unlocalized string (out of ownership) | 4 high, 4 medium, 2 low |
| 7 | Watchtower + Generator | 10 | 13 | 11 | micro-padding + accent-flash-timing conventions (cross-phase, documented); `PasswordAudit.swift` dup of P6's flag | 3 high, 7 medium, 1 low |
| 8 | Settings core + Data | 13 (+2) | 10 | 10 | DEBUG diagnostic fonts (documented dev-tool exemption); EmergencyKitPDFPage (print-artifact exemption) | 2 high, 6 medium, 2 low |
| 9 | Appearance + About | 11 | 13 | 13 | ThemeEditorView/WallpaperGalleryView (dormant, unreachable — confirmed by grep, review-light per scope); `vaultDisplayNumeral` shared-component request | 1 high, 8 medium, 4 low |
| 10 | Personas + Profile | 14 | 8 | 8 | Activate/Confirm-email/Check-verification haptics — deferred to P15, **resolved as "no haptic" convention** (§3) | 5 medium, 3 low |
| 11 | Sharing owner/approval | 13 | 9 | 8 | NotificationsScreen compact-button-style (2nd ask for ThemedCompactButtonStyle) | 2 high (button-wall), 3 medium, 3 low |
| 12 | Sharing QuickLink/QuickView | 9 | 8 | 8 | none | 1 high (button-wall, user-named hotspot), 7 low |
| 13 | Main shell + Mac | 16 | 3 | 3 | ControlledRevealModifier bespoke constants (YAGNI, single call site); Mac hit-target sizing (pointer, not touch); Mac/iPad doc-map gap (docs follow-up) | 1 medium, 2 low |
| 14 | AutoFill extension | 11 (+3 reconciled) | 5 | 5 | apostrophe style (straight vs curly, non-rule); "Request code" List-row accessory sizing | 1 high, 3 medium, 1 low |
| 15 | Verification + button-wall cross-audit | — | 1 new (button-wall) | 1 | — | 1 high |

**Grand total: ~169 findings, ~163 fixed, 6 declined-by-orchestrator, remainder deferred with
documented reason** (every deferral has a rationale in its phase's report — see §4). Severity
histogram (fixed only): **~28 high, ~85 medium, ~50 low**.

## 2. Cross-cutting themes

- **Unlocalized-interpolation bug class**: raw Swift-string error messages assigned to `@State
  String?` and rendered via `Text(_:)`'s verbatim `StringProtocol` initializer instead of
  `appString(...)` — silently broke VI localization even when a catalog key existed. Found in
  `ImportView` (8 sites), `AttachmentPickerSheet` (2), `WatchtowerScreen.runHIBP` +
  `Services/Watchtower/PasswordAudit.swift` (the latter flagged twice, P6 and P7, both out of
  file-ownership — still open, see §4). All in-scope instances fixed; the `PasswordAudit.swift`
  instance needs a small follow-up task (same shape as the fixes already applied).
- **Hit-target class**: small glyph buttons (reveal toggle, biometric retry, "…" menu triggers,
  remove-tag ×, accent swatches, camera-overlay Cancel) rendered below the 44pt minimum with no
  padded hit area — the single most repeated defect (10+ instances across P1/P2/P4/P5/P6/P9/P10).
  Fixed uniformly via the same `.contentShape(Rectangle().inset(by: -(Metric.hitMin - visual)/2))`
  technique everywhere (visual size never grew, only the tap region).
- **Haptic vocabulary class**: missing haptics (destructive confirms with no `.error`, selection
  rows with no `.tap`, custom sliders with no drag-tick) across P2/P8/P9/P10; one doubled haptic
  (`TotpCardView`'s manual `.tap()` stacked on `ClipboardService`'s own `.success()`, P3); one
  misclassified haptic (`Haptics.selection()` on a dormant tab bar vs the app's `.tap()` convention,
  P13; `Haptics.success()` reused for a cosmetic non-copy action, P12). All fixed. The
  Activate/Confirm/Check-verification "no haptic" question (deferred by P10) is now resolved as
  the app's deliberate convention — see §3.
- **Button-wall class** (mid-sweep addition): 3 real violations found across the whole app —
  `ShareAccessSheet` `.waiting` state (P11), `ShareResumeStepperSheet` (P11, 3 non-active
  statuses), `QuickLinkResultView` (P12, the user-named hotspot), plus **one more found by this
  Phase 15 cross-audit**: `JoinByRecoveryView` (Onboarding, a pre-rule phase) stacked Scan Setup
  Code / Continue / Back as 3 always-visible full-width buttons. All 4 fixed by the same pattern:
  rank by frequency, one filled primary, demote the rest to a toolbar menu, a paired quiet-utility
  row, or (JoinByRecoveryView) a compact trailing field accessory matching the app's existing
  scan-icon convention (`EditorFieldRow`'s scan-QR glyph). The other pre-rule phases (Items,
  ItemDetail, ItemEditor, Watchtower, Generator, Settings, ImportExport, Appearance, EmergencyKit)
  were swept and found already-compliant on inspection (single-primary CTAs, Form/List action rows,
  or paired quiet-utility rows like `EmergencyKitView`'s Copy/Share) — see §5 for the full audit.
- **Raw-token class**: raw `.font(.system(...))`, numeric `cornerRadius`/`padding`, and raw colors
  found and converted to `vaultType`/`Radius`/`Space`/`Metric`/theme-role tokens throughout, with a
  consistent, cross-phase-verified exemption list (camera/QR surfaces, native-switch chrome,
  ambient shadows, proportional avatar/tile radii, generated-avatar white monogram, decorative
  quick-action tints, print-artifact PDF page, DEBUG-only diagnostic dumps, dormant
  Wallpaper/ThemeEditor engine). One residual instance was found during this Phase 15 re-grep and
  is **not fixed** (outside the delegated scope of this phase — see §4): `AppearanceSettingsView`'s
  theme-card selection ring (`Color.accentColor` at line ~78) matches the same "static
  asset-catalog accent, not the live per-preset theme" bug class that P1/P4/P5 already fixed
  elsewhere in this exact file family — Phase 9 reviewed and fixed the file's *accent-swatch* ring
  but missed this second, separate ring on the *theme* card. Low risk (the root app view does set
  `.tint(env.theme.uiTint)`, so `Color.accentColor` mostly resolves correctly at runtime; the
  established app convention nonetheless routes through `env.theme.active.color(.accent)` explicitly
  everywhere else to avoid environment-propagation edge cases). Flagged for a fast follow-up, not
  fixed here since it falls outside Phase 15's delegated button-wall/haptics/reporting scope and
  Phase 9's file ownership already closed with its own explicit findings table.

## 3. Haptic convention decision (deferred from Phase 10, resolved here)

**Convention, confirmed by grep across the whole app**: buttons whose action is a routine
confirm/activate/check-status tap — "Activate Sharing", "Approve with Face ID" (view-level; the
ceremony service owns the actual haptic), "Check Now", persona "Confirm email"/"Check
verification"-class actions — fire **no haptic** anywhere in the codebase. This is the app's
deliberate, consistent convention: the vocabulary table's 4 rows are exhaustive (copy → `.success`
fired once by `ClipboardService`, never the view; destructive confirm/auth failure → `.error`;
selection/toggle/minor action → `.tap`; scroll/navigation/appear → none) — a constructive-but-
non-destructive confirm that isn't a selection/toggle and isn't a copy simply has no vocabulary
row, and the codebase treats that as "none" everywhere, not as a gap. **No haptics were added** to
this button class (Personas' "Pause forwarding" keeps its `.tap()` because it IS a
selection/toggle-class action; that is unrelated and unchanged).

## 4. Deliberately deferred (not fixed, with reason)

| Item | Phase | Reason |
|---|---|---|
| LockScreen AX-XXL scroll-safety | 2 | Security-critical, recently-shipped screen; restructuring its root layout without on-device AX-XXL verification was judged out of scope for a presentational pass. → manual QA checklist. |
| `ThemedCompactButtonStyle` (inline pill button) | 5, 11 | No compact themed button style exists yet (all 3 themed styles force `maxWidth: .infinity`); 2 independent call sites now want it (`LocatedInSheet`, `NotificationsScreen`). Filed in `shared-component-requests.md`, not built (Phase 1 owns `DesignSystem/Components/*`, frozen for W2). |
| Multiline-protected field masking (SSH key, Recovery Codes) | 6 | Needs its own masked multi-line editor UI, larger scope than this pass; values still encrypted at rest, only the on-screen editor is unmasked (pre-existing, not a regression). |
| `Services/Watchtower/PasswordAudit.swift` unlocalized string | 6, 7 | Same bug class as the fixed `WatchtowerScreen.runHIBP` string, but the file is outside both phases' `Features/*` ownership. Small, well-scoped follow-up (`appString(...)` + 1 manifest entry). |
| `vaultDisplayNumeral` type role | 9 | Only 1 current call site (`AboutView`'s promise-card numeral); already Dynamic-Type-scalable via `.largeTitle` text style, so no accessibility gap — only a grep-cleanliness gain. Filed, not built (YAGNI for a single call site). |
| Mac/iPad hit-target sizing (10-16pt icons) | 13 | The 44pt rule is an iOS/touch HIG constant; Mac is pointer-driven — not a defect there. |
| `ControlledRevealModifier` bespoke blur/scale constants | 13 | Single call site; introducing a token for one use is YAGNI. Recently shipped, scoped as verify-not-redesign. |
| Mac/iPad surfaces missing from `docs/app-feature-map-ui-ux.md` | 0, 13 | Doc-drift, not a code defect — follow-up docs task. |
| Apostrophe style inconsistency (straight vs curly) | 14 | Not a rule-8 violation (only `!`/`—`/`·` are banned); fixing would orphan a working translated catalog key for a cosmetic-only gain. |
| "Request code" List-row accessory hit-target | 14 | Standard system List-row accessory-button pattern (same as Apple's own Settings/Mail); enlarging needs custom hit-padding inside a `List` row, risk of visual regression without device QA. |
| `AppearanceSettingsView` theme-card ring `Color.accentColor` | 15 (new) | Found during this phase's re-grep; same bug class already fixed elsewhere, but outside Phase 15's delegated scope and Phase 9's file ownership closed. See §2. |

## 5. Cross-app button-wall audit (Phase 15, task 1)

Swept every named pre-rule cluster (Onboarding, Unlock, Items, Folders, ItemDetail, ItemEditor,
Watchtower, Generator, Settings, ImportExport, Appearance, EmergencyKit) for 3+ stacked buttons or
rank-inconsistent adjacent buttons, excluding `confirmationDialog` (system) and `Menu` content
(demotion mechanism itself) and List/Form action rows (system-sized, not competing CTAs) per the
rule's own carve-outs.

**1 new violation found and fixed:**

`Vaultify/Features/Onboarding/JoinVaultFlow.swift` → `JoinByRecoveryView` stacked 3 always-visible
full-width buttons: **Scan Setup Code** (`.themedTinted`) / **Continue** (`.themedProminent`,
primary) / **Back** (`.bordered`). Fix: demoted "Scan Setup Code" from a full-width button into a
compact trailing field accessory (44pt hit target, same pattern as `EditorFieldRow`'s scan-QR
glyph) — the recovery-key input row now carries the scan trigger inline, and the bottom action
stack drops to 2 (Continue primary + Back secondary), matching this flow's own sibling screens
(`JoinMethodChoiceView`, `JoinByQRView`) which already show at most 2. Zero flow/logic change —
same `showScanner`/`onKey`/`onBack` callbacks, same sheet.

**Everything else swept clean on inspection** (already compliant, no fix needed):

| Cluster | Files checked | Result |
|---|---|---|
| Onboarding | `OnboardingFlow`, `CreateMasterPasswordView`, `NameStepView`, `ChooseThemeView`, `EnableBiometricView`, `JoinVaultFlow` (other states), `EmergencyKitView` | WelcomeStep's 2-button pair (Get Started primary + Sync-from-device bordered secondary) correctly ranked; `EmergencyKitView`'s Copy/Share paired-quiet-utility row + separate savePDFCard action-row + bottom Continue primary is already the accepted 1-primary + demoted-utility-row shape (matches P12's own fix pattern). |
| Unlock | `LockScreen`, `RecoveryView`, `LockPasswordField`, `BiometricBadge`, `SlideToUnlock` | Single primary submit + 1 text-link ("Forgot password?") per screen; no stacking. |
| Items/Folders/Vault | `ItemsScreen`, `ArchiveScreen`, `TrashScreen`, `FolderEditorSheet`, `FolderPickerSheet`, `IconColorPicker`, `ManageFoldersScreen` | Destructive actions live in menus/confirmationDialogs (exempt); no stacked CTAs found. |
| ItemDetail/Passkeys | `ItemDetailScreen`, `ProtectFieldSheet`, `CodePromptSheet`, `LocatedInSheet`, `LargeTypeView`, `PasskeysScreen`, `PasskeyDetailSheet` | All multi-button hits are Menu content or confirmationDialogs; single real CTA per sheet elsewhere. |
| ItemEditor | `ItemEditorScreen`, `LoginEditorSections`, `TOTPScannerSheet`, `AttachmentPickerSheet` | Toolbar Save/X + confirmationDialog only; no stacked walls. |
| Watchtower/Generator | `WatchtowerScreen`, `WatchtowerCategoryScreen`, `GeneratorScreen`, `PasswordGeneratorSheet`, `PasswordGeneratorView` | Toolbar regenerate/use actions + a single tap-to-copy row; no walls. |
| Settings/ImportExport | `SettingsScreen`, `ChangeMasterPasswordView`, `Level2SettingsView`, `RegenerateKitView`, `ExportView`, `ImportView`, `SyncSettingsView` | Form/List action rows (Copy/Share/Save-PDF, exempt) + 1 mode-exclusive primary CTA (`ExportView`'s Create Export vs. destructive-styled Create Unencrypted Export never render simultaneously). |
| Appearance/EmergencyKit | `AppearanceSettingsView`, `AutoNightSettingsView`, `AboutView`, `RegenerateKitView` | No custom stacked buttons — theme/accent pickers are tap-to-select tiles, not CTA stacks. |

Already-fixed pre-existing button-walls (found and fixed by their own owning phase, post-rule,
carried forward for completeness): `ShareAccessSheet` `.waiting` (P11), `ShareResumeStepperSheet`
(P11), `QuickLinkResultView` (P12, the user's original named hotspot).

## 6. Registry cross-check (Phase 0 ⇄ Phase 15 closeout)

`reports/phase-00-surface-registry.md` originally listed 224 surfaces, 0 unassigned. Phase 14
flagged 3 more surfaces in its own owned directory that the baseline grep missed
(`UnlockGate`, `PasskeyMigrationGate`, `PasskeyLargeBlob` — all in
`VaultifyAutoFill/PasskeyActionView.swift`) — all 3 were already reviewed by Phase 14 (1 fix,
2 pass), just not counted in the registry's row total. **Appended to the registry as a Phase 15
addendum** (see the file's new closing section): grand total now **227 surfaces, 227 reviewed,
0 unreviewed, 0 unassigned.**

## 7. Compile + tests

- `tuist generate --no-open` + `xcodebuild -workspace Vaultify.xcworkspace -scheme Vaultify
  -configuration Debug -destination 'generic/platform=iOS Simulator'
  -derivedDataPath /tmp/vaultify-dd-p15 CODE_SIGNING_ALLOWED=NO` → **BUILD SUCCEEDED** (app +
  embedded `VaultifyAutoFill.appex`), run after this phase's `JoinVaultFlow.swift` fix.
- Full unit test suite and prior 14 phases' individual compiles were already verified green by the
  orchestrator before this phase started (per the phase-15 assignment brief) — not re-run here
  since no test-affecting logic changed in this phase (presentational-only fix).
- Global audit re-grep (raw font/radius/padding/color, banned copy glyphs) re-run app-wide: zero
  new regressions; all remaining hits trace to each phase's own documented exemption (camera/QR,
  native-switch chrome, ambient shadow, proportional tile radii, print-artifact PDF page, DEBUG
  diagnostic dumps, dormant Wallpaper/ThemeEditor engine) except the one residual color-token item
  noted in §2/§4 (flagged, not fixed, outside this phase's delegated scope).

## 8. Strings

No new/changed catalog strings this phase — the `JoinByRecoveryView` fix reuses the existing
`"Scan Setup Code"` key (already EN source + VI `"Quét Mã thiết lập"` translated) as an
accessibility label instead of visible button text. No `strings-manifest-phase-15.md` needed.

## Unresolved questions

1. `Services/Watchtower/PasswordAudit.swift`'s unlocalized "Used by N items" string (flagged twice,
   P6 and P7) — needs a small follow-up task; falls outside every phase's `Features/*` file
   ownership as currently scoped.
2. `AppearanceSettingsView`'s theme-card ring `Color.accentColor` (§2/§4) — same bug class as 3
   already-fixed instances elsewhere; recommend a 1-line follow-up fix, not done here (scope).
3. Whether to build `ThemedCompactButtonStyle` now (2 independent call sites already want it,
   P5 + P11) or keep deferring — orchestrator/user call, not a Phase 15 decision.
