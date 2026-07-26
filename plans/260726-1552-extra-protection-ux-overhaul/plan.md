# Extra Protection UX Overhaul

Status: phases 1-3 implemented + verified on simulator (260726); phase 4 shipped separately as PR #175
Owner ask: audit + redesign the field-protection UX (enable/remove protection, level-2 password setup), rebuild the setup form to match the app vibe with the one-shot radiating-dots logo intro, and stop the "Vaultify Quality" simulator leak on the CI runner.

## Findings (evidence: hands-on iPhone 11 walkthrough + code recon, reports below)

Correctness (must fix before UX polish makes sense):
- iOS AutoFill hands off raw `v2g:` ciphertext as the password (`VaultifyAutoFill/AutoFillView.swift:91,215`); QuickType identities register on any non-empty value (`CredentialIdentityService.swift:83`). Safari path already fails closed.
- Bottom "Copy Password" cluster copies ciphertext (`ItemDetailScreen.swift:72-82` — no guard2 check).
- Home persona subtitle, item list rows, and search rows render raw ciphertext after protecting an email/username field (seen live on Home).
- Encrypted backup never carries `wrappedL2SK/l2Salt/l2Kdf` (Keychain-only) → restore on a new device permanently strands level-2 fields; CSV exports ciphertext as the password (`VaultBackup.swift`).
- Wrong extra password reports "Incorrect master password." (`AuthError.wrongPassword` mapping); `"Couldn’t protect this field."` is hardcoded EN.
- Watchtower grades/breach-checks ciphertext as if it were the password.

UX (walkthrough):
- Setup form is a bare `Form`: no brand hero, broken-looking empty strength bar, placeholder-as-label, disabled chip "Set" top-right, zero feedback on success (pops back silently), no set/not-set state on the Security row.
- No way to remove the level-2 password — ever (no UI, no API path clears `wrappedL2SK`).
- Protect sheet: near-empty full sheet, doesn't name the field, doesn't explain Extra Password vs Custom code, dead-ends when no password set ("Settings → Security first" with no link).
- Reveal prompt: title "Extra Password", body "Level-2 password", field placeholder "Code" — three names, one concept; keyboard doesn't auto-focus; swipe-only dismiss.
- Remove Protection: hidden until after a reveal, then instant with no confirmation.
- Level-2 session silently stays unlocked until app lock (reveal works with no prompt, no indicator); custom-code fields prompt every time — asymmetry never explained, locked rows look identical for both schemes.
- Editor can't protect fields at all ("Manage in the item view"); TOTP protection silently kills the live code + autofill.
- VI drift: two strings use "bảo vệ nâng cao" instead of glossary "Mật khẩu cấp 2".

CI simulators ("Vaultify Quality" leak — root causes, verified on runner logs):
- The sweep `xcrun simctl list devices Shutdown` filters by NAME not state on Xcode 26.5 → has never deleted anything (ci.yml comment is wrong).
- `SIMULATOR_UDID` is exported to `GITHUB_ENV` only after boot → cancel-in-progress during boot leaves a Booted orphan the delete step can't see; worker deaths (2 observed in `_diag`) skip `always()` entirely.
- Volume is normal churn otherwise: ~1 sim per CI run on the dev machine (15 creates today), pre-trim was 3 jobs × 2 triggers.

## Phases

- [phase-01](phase-01-correctness.md) — Correctness: guard2 filters (AutoFill/QuickType, copy cluster, subtitles, Watchtower), correct error identity, localize fallback, backup carries wrapped L2SK, CSV stops exporting ciphertext.
- [phase-02](phase-02-setup-screen.md) — Level-2 setup/manage screen rebuilt in the CreateMasterPasswordView idiom with the one-shot `LooxSwirlAnimationView(.reveal)` shield hero; set / change / **turn off** (decrypt-all-in-place with confirmation + affected-field count); status surfaced on the Security row; success feedback.
- [phase-03](phase-03-protect-reveal-flows.md) — Protect sheet redesign (names the field, explains schemes, inline first-time setup), scheme-aware locked rows, reveal prompt rebuilt (per-scheme copy, autofocus, Cancel), Remove Protection confirmation, TOTP caveat, unified terminology EN "Extra Password" / VI "Mật khẩu cấp 2".
- [phase-04](phase-04-ci-simulator-janitor.md) — CI: JSON all-state sweep, export UDID before boot, ERR trap, delete-step fallback, fix stale comment. Separate PR.

## Acceptance
- All P1 leaks verified gone on simulator (protect email/password field → Home/list/search/copy/AutoFill show no `v2g:`).
- Setup/manage screen passes design-DNA bar: light/dark, VI longest labels, Reduce Motion (static settled dots), 44pt targets, EN+VI strings complete.
- Protect → reveal → remove loop walkable without reading docs; every state gives feedback.
- CI run creates exactly one sim and the next run reclaims any orphan in any state.

## Decisions taken (flag if you disagree)
- "Turn off Extra Password" = verify current password → decrypt all level-2 fields in place (listed count shown in the confirm dialog). Custom-code fields are untouched (they don't depend on the L2SK).
- Encrypted backup now includes the *wrapped* L2SK blob (same protection level as before — still needs the extra password to open); old backups without it keep restoring fine.
- CSV export writes an empty value + `[protected]` marker for sealed fields instead of ciphertext.

## Reports
- Recon (3 agents): feature map, animation inventory, CI lifecycle — see workflow output `wf_76b710ab-e2e` (session artifacts).
