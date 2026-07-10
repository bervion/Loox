# Phase 8 — Settings core + Security + Data

**Status**: pending · **Wave**: W2 · **Owns**: `Settings/*` (excl `Appearance/`), `ImportExport/*`,
`EmergencyKit/*` (16 surfaces). Method = canonical protocol + 6 greps (`phase-01`).

## Protagonist
Settings = "change one behavior and get out". Each sub-screen = one setting task.

## Cluster hotspots
- **SettingsScreen**: sectioned list (Security/AutoFill/Organization/Online/Privacy/Icons/Appearance/
  Watchtower/Data/Lock-Erase/About). Verify row labels EN+VI, no `·`/`—`/`!`; "Erase Vault" red = role,
  → dialog "Erase Everything" honest irreversible copy; offline-alias erase-block alert intentional.
- **Online Features rows**: subtitle status (Available/Offline/Maintenance/Unavailable) — status changes
  subtitle only, NEVER auto-flips the toggle (verify wiring unchanged; presentational fixes only).
- **ChangeMasterPasswordView / Level2SettingsView / RegenerateKitView**: strength meter reused; Save disabled
  until valid; no-recovery warnings honest; regenerate dialog "previous recovery key will stop working."
  (no `!`); busy overlay + inline error states intentional.
- **SyncSettingsView / PairDeviceSheet**: iCloud toggle + footer (ciphertext only); Sync Now / Last-sync /
  error states; Pair 5-step machine (scanning→confirm→publishing→done→failed) — each state a real screen,
  confirm never auto-sends key. Amber "not configured" info banner (reuse `CapabilityBannerView`, read-only).
- **ImportView / ExportView**: Import preview "N records", per-case errors honest; Export segmented
  Encrypted/CSV, CSV red warning "not encrypted… Passkeys are never included" (role red, honest). Create
  disabled until valid; Share-export appears on success.
- **EmergencyKitPDFPage**: always-light print surface — RAW colors EXEMPT here; still verify layout/copy
  (logo, recovery key mono, QR, amber banner, footer) and EN+VI where user-visible.
- **ShareDiagnosticsView**: developer/diagnostic surface — still token-clean and localized if user-reachable.
- **MacSettingsView**: Mac variant — verify parity + no raw colors (coordinate shell with Phase 13 by
  ownership: this file is P8's; Mac shell chrome is P13's).

## Deliverables / Todo
`reports/findings-phase-08.md` · `strings-manifest-phase-08.md` · fixes.
- [ ] Protocol answers (16). [ ] 6 greps. [ ] Verify Online-toggle-vs-status wiring untouched.
- [ ] Pair/import/export state machines walked. [ ] PDF exemption noted. [ ] Fixes + manifest.

## Success / Risk
Success: audit-grep clean (PDF exempt); every sub-screen one-task; destructive copy honest+confirmed; state
machines intentional; EN+VI. Risk: touching Online-features rows could accidentally couple status↔toggle
(Med×High) — presentational only, do not alter capability wiring; ADR-2 (approval flag ≠ iCloud flag) intact.
</content>
