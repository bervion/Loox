# Phase 14 — AutoFill extension UI

**Status**: pending · **Wave**: W2 · **Owns**: `VaultifyAutoFill/*` (11 surfaces).
Method = canonical protocol, with the EXTENSION rule variance below.

## Protagonist
"Unlock, then fill the right credential/passkey/code into the host app — fast, in a cramped sheet."

## RULE VARIANCE (read first)
The extension uses **system material**, NOT the app's design tokens (map §14). So the token/radius/spacing
greps DO NOT apply the same way — the acceptance bar here is: system-native look, correct behavior, honest
localized copy, ≥44 hit targets, single correct haptics, and the compact-sheet layout survives SE width.
Still audit: **copy honesty (no `!`/`—`/`·`)**, **EN+VI**, **haptics vocabulary**, **hit targets**, and
**no invisible content in dark mode** (system materials handle theme, but custom text colors must not break).

## Cluster hotspots
- **UnlockGate**: Face ID auto → fallback password form (logo + SecureField + red error "Incorrect master
  password." + Unlock + optional "Unlock with Face ID" + Cancel). Already-unlocked path must NOT re-prompt
  Face ID. Error copy honest, no `!`.
- **AutoFillView**: login list — "＋ Create new login", sections "For this app"/"Other logins", empty "No
  logins found"; shared items "· Shared" (replace `·` with real layout/marker per rule 8); OFFLINE hides all
  shared rows + footnote "Shared items need an internet connection."
- **CreateLoginView / SavePasswordView**: Website/Username/Password(mono)/Regenerate → Save & fill; iOS 26.2
  native save confirm; error "Couldn't save the login." honest.
- **OneTimeCodeView**: auto-fill single match; else picker (codes NOT shown in list, generated on tap); empty
  "No 2FA codes found."
- **PasskeyActionView / PasskeyCeremonyView / PasskeyLargeBlob**: register (Create Passkey, spinner, error keeps
  sheet) + sign-in (>1 → picker; 1 → auto; shared ask-each-time → "Waiting for the owner to approve…" + Cancel;
  decline/expire honest; no-passkey → password fallback WITHOUT re-Face-ID).
- **CredentialProviderViewController (+SilentPasskeys)**: host controller — verify presented SwiftUI views get
  correct sizing in the extension sheet; no layout overflow at SE.

## Deliverables / Todo
`reports/findings-phase-14.md` · `strings-manifest-phase-14.md` · fixes.
- [ ] Protocol answers (11). [ ] Copy/EN-VI/haptics/hit-target/dark-mode audits (token grep N/A).
- [ ] Verify no double Face ID prompt across unlock→fill. [ ] `·`/`—`/`!` sweep. [ ] Offline shared-row hide.
- [ ] Fixes + manifest.

## Success / Risk
Success: extension reads system-native; all states honest+localized; ≥44 targets; single Face ID; no dark-mode
invisible text; SE-width safe. Risk: extension has a strict memory/size budget + shared VaultifyCore
(High×Med) — presentational only; do not change unlock/fill/passkey logic; test compiles into BOTH targets.
</content>
