# Phase 8 — Settings core + Security + Data: Findings

Scope: 13 owned surfaces (`SettingsScreen`, `ChangeMasterPasswordView`, `Level2SettingsView`,
`RegenerateKitView`, `SyncSettingsView`, `PairDeviceSheet`, `ShareDiagnosticsView`, `MacSettingsView` +
its 2 private panes `MacGeneralSettingsPane`/`MacSecuritySettingsPane`, `ExportView`, `ImportView`,
`EmergencyKitPDFPage`) plus 2 non-View support files owned by the same dirs (`EmergencyKitInfo.swift`,
`EmergencyKitPDF.swift`), per `reports/phase-00-surface-registry.md` phase-8 rows. `Settings/Appearance/*`
and `AboutView.swift` are Phase 9's — excluded here even though they matched the directory grep.
Method: `docs/design-dna-standard.md` adversarial protocol Q1-5 + the 6 audit greps.

Protagonist for the cluster: "change one behavior and get out" (Settings), "confirm before doing
something irreversible" (destructive/export/regen flows), "get through the state machine without a
wrong guess" (Pair Device).

## Findings table

| Surface(s) | File | Q1 protagonist | Q2 text | Q3 controls/haptics | Q4 space/shape | Q5 states | Finding | Fix | Severity | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| SettingsScreen | SettingsScreen.swift | One job per row, sectioned; Erase demoted to bottom, destructive-styled, confirmed | all row labels + footers calm, no `!`/`—`/`·`; Online Features footer honestly separates preference-toggle from operator-availability text | native `Form`/`List` rows (system ≥44pt); Erase→destructive confirmationDialog + honest "cannot be undone" copy | `.listRowBackground(VaultColors.surface)` (token) throughout; no numeric literals | biometric-available/unavailable, iCloud sync configured/not, relay-teardown offline-block alert, DEBUG section gated — all intentional, none stranded | none | — | — | pass |
| ChangeMasterPasswordView | ChangeMasterPasswordView.swift | Re-key unlock path in one form; Save disabled until valid | "Your Vault Key doesn't change..." honest reassurance; "Passwords don't match" calm | Save gated by `canSubmit`; `Haptics.success()`/`.error()` on completion — correct vocabulary | tokens (`Space.s2` n/a here — no literals); strength meter reused | empty/typing/mismatch/busy-overlay/server-error — all intentional | none | — | — | pass |
| Level2SettingsView | Level2SettingsView.swift | Set/change the 2nd password; irreversible-if-forgotten warning upfront | "If you forget it, those fields cannot be recovered." honest, no banned punctuation | Save gated by `canSubmit`; haptics correct | **raw `.font(.footnote)` on the intro Label text (should be `vaultType`)** | first-time-set vs change-existing (current-password field conditionally shown) both correct | 1 typography defect | `.font(.footnote)` → `.vaultType(.footnote)` | medium | fixed |
| RegenerateKitView | RegenerateKitView.swift | View/regenerate the recovery key; regen is destructive-confirmed | "Your previous recovery key will stop working." honest; key shown once | `Font.vaultCode` correctly used for the secret key (not raw font — false-positive on the blanket grep); PDF-export failure had a haptic, **but the actual kit-generation failure (`try?` swallowed the throw) had NO error surfaced and NO `Haptics.error()`** — a silent failure on a security-critical action | `Space.s2` token used | has-kit/no-kit, key-just-generated, PDF-export success/fail, regen-confirm dialog — regen-failure path was the one un-intentional dead-end (busy just clears, no feedback) | **HIGH: silent failure on kit regeneration** — user taps Regenerate/Generate, spinner clears, nothing happens, no explanation | Surfaced the swallowed throw: added `generateError` state + inline error `Text` (mirrors the existing `ChangeMasterPasswordView`/`Level2SettingsView` inline-error pattern already used elsewhere in this same phase), `Haptics.error()` on catch. Also added missing `Haptics.error()` on the PDF-export failure branch (success branch already had it — asymmetric before). No auth/key-derivation logic touched — `generateRecoveryKit()` call itself unchanged, only its already-possible failure is now shown instead of swallowed | high (fixed) | fixed |
| SyncSettingsView | SyncSettingsView.swift | Toggle iCloud sync, see status, pair devices; toggle ≠ availability status (verified untouched) | footer honest about metadata-vs-secrets scope; Pair footer explains E2E | Sync Now disabled while syncing; Pair disabled while locked — correct | **2× raw `.font(.footnote)` in production code paths** (not-configured info banner; sync-error status text) — DEBUG-only `approvalSpikeSection`/`inviteInboxDebugSection` raw fonts are pre-documented exemptions ("Plain unlocalized strings on purpose — DEBUG-only") and left alone | idle/syncing/success/error status rows, configured/not-configured, sync-on/off, DEBUG panels gated — all intentional; **verified**: `iCloudSyncEnabled` toggle mutates only the preference, `syncNow()` is a separate explicit action — no coupling to `approvalModeEnabled` (ADR-2 intact, confirmed by reading, not altered) | 2 typography defects (production only) | `.font(.footnote)` → `.vaultType(.footnote)` at both production sites; also swapped one DEBUG-only diagnostic string's stray em dash (`"vault is locked — unlock first"` → `"...locked, unlock first"`) for copy-rule hygiene, still intentionally unlocalized per the section's own documented exemption | medium (fixed) | fixed |
| PairDeviceSheet | PairDeviceSheet.swift | Approve or scan a device pairing, one explicit confirm step before the key ever seals | "Only approve a device that belongs to you." honest gate copy; all 5 phase-machine strings calm | Approve/Cancel/Try Again all `.controlSize(.large)` full-width (≥44pt) | `Space.*` tokens throughout; scanner overlay `.white`/`.black` = documented camera-surface exemption | scanning→confirm→publishing→done→failed, macOS fallback — each phase a distinct screen, confirm never auto-sends (verified: `approve()` only runs after the explicit Approve tap) | none | — | — | pass |
| ShareDiagnosticsView | ShareDiagnosticsView.swift | DEBUG-only dev diagnostic viewer, reachable only behind `#if DEBUG` NavigationLink in SettingsScreen | placeholder values used raw `"—"` (em dash) as a "not set"/"empty" marker — copy-rule violation even though this is a dev tool, trivial to fix | Copy/Clear toolbar buttons plain, fine | raw `.font(.system(.caption2, design: .monospaced))` on the log dump — same class as the SyncSettingsView DEBUG diagnostic dumps (raw monospace for a text log, not a themed UI element) | state row / log-empty / log-populated all intentional | 3 trivial em-dash placeholders | replaced `"—"` → `"unknown"`/`"not set"`, `"— no diagnostics yet —"` → `"No diagnostics yet."` (still plain `Text(verbatim:)`, not localized, matching the file's own dev-tool convention — this view isn't user-facing prose, so EN+VI is not required here, same reasoning already applied to `SyncSettingsView`'s DEBUG sections) | low (fixed) | fixed |
| ShareDiagnosticsView (font) | ShareDiagnosticsView.swift:30 | n/a | n/a | n/a | raw `.font(.system(.caption2, design: .monospaced))` on the diagnostic log text | n/a | dev-tool log dump, not a themed UI surface; documented exemption, consistent with `SyncSettingsView`'s DEBUG monospace dumps | not fixed — exempt | low | exempt (documented) |
| MacSettingsView + MacGeneralSettingsPane + MacSecuritySettingsPane | MacSettingsView.swift | Sidebar+detail Settings idiom; Security pane mirrors iOS minus iOS-only rows | all copy already reviewed identically in the iOS panes (shared strings); no new copy here | segmented pickers (documented macOS menu-popup-bridge workaround, not a mobile ergonomics concern); Lock/Erase `.buttonStyle(.borderless)` — desktop convention, not a hit-target regression (macOS pointer target, not touch) | tokens throughout (`Space.s4/s6`), no raw colors, no numeric literals | locked-placeholder vs unlocked-detail, each pane's own states — all intentional | none | — | — | pass |
| ExportView | ExportView.swift | Export encrypted (default) or CSV (friction-gated); create disabled until valid | CSV warning "not encrypted... Passkeys are never included" honest, bold-emphasis not shouty; unencrypted-confirm dialog honest | **Create Export / Create Unencrypted Export had NO haptic on completion or failure** — every sibling security/data flow in this phase (`Import`, `ChangeMasterPassword`, `Level2`, `RegenerateKit`) fires `Haptics.success()`/`.error()`; Export was the one silent outlier | tokens throughout, no literals | encrypted/csv mode, empty-vault (disabled), passphrase-mismatch (disabled), working-overlay, error, share-after-success — all intentional except the missing haptic feedback | missing haptic parity | added `Haptics.success()` after `exportURL` is set, `Haptics.error()` in the `catch` — no export logic touched, purely feedback | medium (fixed) | fixed |
| ImportView | ImportView.swift | Import CSV/backup; preview "N records" before commit; per-case errors | **8 error-path strings assigned as raw Swift literals to `@State private var error: String?`, never routed through `appString()`** — `Text(error)` where `error: String` resolves the `StringProtocol` verbatim initializer (not `LocalizedStringKey`), so these messages **rendered in English even when the app's language was set to Vietnamese**, regardless of whether a catalog entry existed. Confirmed against `Vaultify/Localizable.xcstrings`: 2 keys existed with EN comment but **no VI value** (`Couldn't open the file.`, `Couldn't read the file.`), 2 keys were **entirely missing** (`No items found in that file.`, `Unsupported file format.`), 3 keys already had EN+VI translated but were unreachable at runtime because of the missing `appString()` wrapper (`Backup contained no records.`, `Unlock your vault before importing passkeys.`, `Import failed before all records could be saved.`), and 1 string also had a stray em dash (`"Couldn't decrypt — check the password."`) | also: none of the 8 error paths fired `Haptics.error()` (only the final `performImport()` success path had `Haptics.success()`) — inconsistent with every sibling screen in this phase | raw `.font(.footnote)` on the "and N more…" preview caption | tokens elsewhere | file-picker-cancelled / open-fail / read-fail / encrypted-detected / CSV-empty / unsupported-format / decrypt-fail / backup-empty / passkeys-locked / partial-save-fail / success — every failure state now has matching visible+haptic feedback | HIGH: broken VI localization on all 8 error paths + missing haptic feedback + 1 typography defect + 1 em dash | wrapped all 8 literals in `appString(...)`; added `Haptics.error()` to each failure path; fixed the em dash (`"Couldn't decrypt, check the password."`); `.font(.footnote)`→`.vaultType(.footnote)`. New/changed catalog keys listed in `strings-manifest-phase-08.md` | high (fixed) | fixed |
| EmergencyKitPDFPage, EmergencyKitPDF, EmergencyKitInfo | EmergencyKit/*.swift | PRINT ARTIFACT: single fixed-size A4 page rasterised off-screen to PDF — not a responsive UI screen, no device-width/Dynamic-Type/theme-switch matrix applies | all copy already localized via `appString(...)`; honest security warning ("no master password needed. Keep it offline and private.") already present, no banned punctuation in any *user-facing* string (doc-comment em dashes are not UI copy) | n/a — not interactive (no buttons/taps on the print page itself) | **raw `.font(.system(size:))` (13×), numeric `.padding()`/`cornerRadius:`/`frame(width:)` (10×), raw `Color.white`/`Color(white:)`/fixed RGB — ALL pre-documented in the file's own header comment as the deliberate PRINT ARTIFACT exemption** (fixed ink-on-paper page rendered via `ImageRenderer`, same class as the QR-tile/favicon exemption) | single fixed layout, no empty/loading/error states (pure data→page render) | none (all flagged items are the documented print exemption) | not fixed — exempt per file's own header comment, consistent with phase brief's explicit note | — | exempt (documented) |

## Verified untouched (security-critical wiring)

- **Online Features rows** (`SettingsScreen.onlineFeatureRow`): toggle binds only to `env.capabilities.setUserPreference`; the subtitle binds only to `env.capabilities.availability(...)`. Two independent reads/writes — confirmed no coupling introduced or existing.
- **`iCloudSyncEnabled` / `approvalModeEnabled`**: `SyncSettingsView` only ever reads/writes `env.settings.iCloudSyncEnabled`; `ShareDiagnosticsView` only *reads* `env.settings.approvalModeEnabled` for a debug status row (no write). ADR-2 (the two flags must never gate each other) intact — confirmed by reading, not modified.
- **Pair Device confirm**: `approve(qrPayload:)` only runs on the explicit "Approve" tap in `confirmView`; no auto-seal on scan.
- **Erase Vault**: `SettingsScreen`/`MacGeneralSettingsPane` both require the destructive confirmation dialog before `eraseWithRelayTeardown()`/`env.eraseEverything()` runs; copy is honest ("permanently deletes... cannot be undone"). Not modified.
- **Change Master Password / Extra Protection / Recovery-kit generation call itself**: none of the underlying `env.session.*` crypto/key-derivation calls were changed — only their already-existing failure paths gained visible+haptic feedback (RegenerateKitView) or existing feedback was left as-is (ChangeMasterPassword, Level2, both already correct).

## Haptics vocabulary — final state

All `Haptics.*` call sites in owned files now match the vocabulary (destructive-confirm/auth-failure →
`.error`, successful mutation → `.success`, no doubling of a service-fired event):

- `ChangeMasterPasswordView`, `Level2SettingsView`: unchanged, already correct.
- `RegenerateKitView`: added `.error()` on kit-generation failure (previously silent) and on PDF-export
  failure (previously only success fired).
- `ExportView`: added `.success()`/`.error()` — previously had neither (only Import had them).
- `ImportView`: added `.error()` to all 8 failure paths (previously only the final success had a haptic).

## 6 audit greps — final state (owned files, post-fix)

```
1. SE-width / GeometryReader / minimumScaleFactor / lineLimit(1): only in EmergencyKitPDFPage (fixed
   A4 print page, exempt — see table). No responsive-UI clipping risk found elsewhere in owned files.
2. Typography `.font(.`: fixed 4 raw sites (Level2SettingsView intro label, SyncSettingsView×2,
   ImportView preview caption) → `.vaultType(_:)`. Remaining raw `.font(` hits are: `Font.vaultCode(...)`
   (correct token API, false-positive on the blanket grep), 2× DEBUG-only diagnostic log dumps
   (SyncSettingsView, ShareDiagnosticsView — documented dev-tool exemption), and EmergencyKitPDFPage's
   13 fixed-size print fonts (documented PRINT ARTIFACT exemption).
3. Radius: zero numeric literals outside EmergencyKitPDFPage's exempt print layout.
4. Spacing `.padding(`: zero numeric literals outside EmergencyKitPDFPage's exempt print layout.
5. Hit targets: no owned-file violations — all buttons are native Form/List rows or explicit
   `.controlSize(.large)` full-width buttons (PairDeviceSheet), all ≥44pt.
6. Haptics: 4 fixes applied (RegenerateKitView×2, ExportView×2, ImportView×8) — see above. All now
   vocabulary-correct, none doubled.
```

## Shared-component requests

None. No shared `DesignSystem/Components/*` change was needed for this phase's fixes.

## Deferred / not fixed (documented rationale)

- **`ShareDiagnosticsView`'s raw monospace log font** and **`SyncSettingsView`'s two DEBUG-gated raw
  fonts** (`approvalSpikeSection`, `inviteInboxDebugSection`) — dev-diagnostic log dumps, not themed UI;
  left as-is, consistent with the file's own pre-existing "DEBUG-only, unlocalized on purpose" comment.
- **`EmergencyKitPDFPage`/`EmergencyKitPDF`/`EmergencyKitInfo`** raw fonts/colors/padding/radius — all
  covered by the file's own documented PRINT ARTIFACT exemption (fixed-size page rasterised to PDF, no
  responsive/theme matrix applies). Verified copy and layout only, per the phase brief's explicit note.
</content>
