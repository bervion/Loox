# Phase 14 findings — AutoFill extension UI

Scope: `VaultifyAutoFill/*` (system material, RULE VARIANCE — no design tokens; acceptance bar =
native look, copy honesty, EN+VI, ≥44 hit targets, single haptics, dark-mode safe). Protagonist:
"fill the right credential/passkey/code into the host app, fast, in a cramped sheet."

Registry gap noted: `UnlockGate`, `PasskeyMigrationGate` (private, in `PasskeyActionView.swift`),
and `PasskeyLargeBlob` are not listed in `reports/phase-00-surface-registry.md` (11 rows registered
vs these 3 extra files reviewed here since they live in the owned directory). Flagged for Phase 15
registry reconciliation — not a phase-14 defect, just an omission upstream.

| surface | Q1-5 condensed | finding | fix | severity | status |
|---|---|---|---|---|---|
| `UnlockGate` (unlock form) | Protagonist: unlock fast, Face ID first. Copy honest ("Incorrect master password.", "Couldn't unlock the vault."). Already-unlocked path (`presetKey`) skips re-Face-ID — verified in code. | "Unlock with Face ID" fallback button had no `buttonStyle`, so its tappable area could collapse to the label's intrinsic size instead of a guaranteed ≥44pt row. | Added `.buttonStyle(.bordered)` (matches the primary "Unlock" button's `.controlSize(.large)` sizing contract). | medium | fixed |
| `AutoFillView` + `CredentialListView` | Protagonist: pick a login and fill. "For this app"/"Other logins" sections correct; empty "No logins found"; offline hides all shared rows (`reachability.hasSatisfiedNetworkPath` gate) + honest footnote — verified, no `·` in the rendered UI (Shared tag is a separate `Text`, not interpunct-glued). | Doc comment above `CredentialListView` was stale — described the shared-tag as `"· Shared"` when the actual render already uses a real second `Text` label (correct implementation, wrong comment). | Updated comment to describe the real (compliant) layout. No functional change. | low | fixed |
| `CreateLoginView` | Protagonist: register a new login, fill it. Site prefilled from host, username from default identity, password fresh. "Save & fill" honest, error "Couldn't save the login." honest. | Generated-password `Text` used `minimumScaleFactor(0.6)`, below the standard's explicit floor (never below 0.7). | Bumped to `0.7`. | medium | fixed |
| `SavePasswordView` + `SaveConfirmView` | Protagonist: confirm the OS-handed credential, save once. | `LabeledContent` used a literal em-dash `"—"` as the empty-value placeholder for Website/Username — a direct rule-8 violation (banned punctuation in UI copy) and not stated honestly (a dash implies "nothing to see" rather than "not provided"). | Replaced with `appString("Not provided")` (EN/VI in manifest). | high | fixed |
| `OneTimeCodeView` + `OneTimeCodeListView` | Protagonist: fill the right TOTP code. Codes never shown in list, generated on tap only — verified. Empty "No 2FA codes found" honest. | None. | — | — | pass |
| `PasskeyActionView` + `PasskeyMigrationGate` | Protagonist: get to the post-unlock ceremony; migration/quarantine housekeeping runs invisibly behind a plain spinner. | None — presentational surface is a thin pass-through; no user-facing copy of its own beyond the shared spinner. | — | — | pass |
| `PasskeyCeremonyView` | Protagonist: register or sign in with a passkey in one tap when there's exactly one match; picker when >1; shared askEachTime shows "Waiting for the owner to approve…" + Cancel; decline/expire/no-match all keep the sheet up with honest copy, no flash-dismiss — verified against `PasskeyActionView`/`CredentialProviderViewController` wiring (no double Face ID). | "Cancel" button during the askEachTime wait had no `buttonStyle` — same sub-44pt hit-target risk as the UnlockGate case, and this Cancel is reachable during a multi-second wait (F0-level urgency). | Added `.buttonStyle(.bordered)`. | medium | fixed |
| `PasskeyLargeBlob` | No `body: View` — pure directive/output mapping (iOS 18 largeBlob extension types). Not a visual surface. | None. | — | — | pass (no UI) |
| `CredentialProviderViewController` (+`SilentPasskeys` extension) | Hosts every SwiftUI screen above; applies the app's theme (`.tint`, `.preferredColorScheme`) and in-app language (`.environment(\.locale,...)`) before presenting — both already correct and already respect dark mode + EN/VI. Silent-passkey extension has no view of its own (never shows UI by design — `performWithoutUserInteractionIfPossible`). | None found. Security-critical wiring — left untouched per phase scope. | — | — | pass |

## Copy sweep (`!` / `—` / `·`)
Grep across all 11 owned `.swift` files for the three banned characters found exactly one real hit
(the `SavePasswordView` em-dash placeholders, fixed above); every other `—`/`!` match was inside a
`guard`/comment (`!x.isEmpty`, `!=`, log line) — not UI copy.

## Apostrophe style (straight `'` vs curly `’`) — reviewed, no fix
Three error strings use a straight apostrophe (`"Couldn't verify access right now."` ×2,
`"Couldn't reach the owner right now."`) while most others use curly (`’`). Checked
`Vaultify/Localizable.xcstrings`: the straight-quote keys already exist with VI translations in
place. Normalizing to curly would orphan a working translated key for a purely cosmetic gain — not
a rule-8 violation (only `!`/`—`/`·` are banned) — so left as-is per the "verified decisions are
sticky" rule; a bigger unifying stringcheck for style pass belongs to phase 15's catalog
reconciliation, not a one-off rewrite here.

## Haptics
`grep -rn "Haptics\." VaultifyAutoFill/*.swift` → zero matches. The extension never imports the
app's Haptics service (VaultifyCore-only linkage), so there is no risk of doubling with system
feedback (Face ID sheet, system alert) — confirmed pass, nothing to fix.

## Hit targets
- Fixed: UnlockGate Face ID retry button, PasskeyCeremonyView askEachTime Cancel button (both now
  `.buttonStyle(.bordered)`, guaranteeing the `.controlSize`/system-default ≥44pt row).
- Reviewed, left as-is: `AutoFillView`'s inline "Request code" icon-only accessory button
  (`.buttonStyle(.borderless)`, `.labelStyle(.iconOnly)`) sits inside a standard `List` row (row
  height already ≥44 via system List sizing) — this is the same accessory-button-in-row pattern
  Apple's own Settings/Mail use; enlarging its own frame would require custom hit-area padding
  inside a `List` row and risks visual regression without device QA. Low severity, deferred.
- All Form/List rows in `CreateLoginView`, `SavePasswordView`, `OneTimeCodeView`,
  `PasskeyCeremonyView` rely on system Form/List row sizing (≥44 by default) — pass.

## Dark mode / theme
`CredentialProviderViewController.host(_:)` applies `.tint(theme.accent)` +
`.preferredColorScheme(theme.isDark ? .dark : .light)` from the app's shared theme before any
screen renders. All `foregroundStyle` calls in the 11 files use system-semantic roles
(`.primary`/`.secondary`/`.red`) — these are SwiftUI dynamic colors that already adapt light/dark;
this is the CORRECT pattern for the extension (no app tokens available) and not a defect. No raw
`.white`/`.black` found. Pass.

## No double Face ID
Traced `UnlockGate` (Face ID → password fallback), `AutoFillView`/`OneTimeCodeView`/
`PasskeyActionView` (all accept a `presetKey`/pass the unlocked key forward), and
`PasskeyCeremonyView.onNoPasskey` (passkey assert with zero matches → hands the already-unlocked
`vaultKey` to the password picker via `presetKey`, no second prompt). Verified in code — pass, no
fix needed.

## Fixes applied (summary)
1. `SavePasswordView.swift` — em-dash placeholder → `appString("Not provided")` (high).
2. `UnlockGate.swift` — Face ID retry button `.buttonStyle(.bordered)` (medium, hit target).
3. `PasskeyCeremonyView.swift` — askEachTime Cancel button `.buttonStyle(.bordered)` (medium, hit target).
4. `CreateLoginView.swift` — `minimumScaleFactor` 0.6 → 0.7 (medium, floor violation).
5. `AutoFillView.swift` — stale doc comment corrected (low, no functional change).

## Deferred (low, no fix)
- Apostrophe style inconsistency (straight vs curly) — not a rule violation, would orphan a
  translated catalog key; leave for phase 15's broader string-catalog pass if desired.
- "Request code" icon-only accessory button sizing — standard List-row accessory pattern, deferred
  pending device QA.

## Compile
See phase completion message for `tuist generate` + `xcodebuild` (app + appex) result.
