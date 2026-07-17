# Phase 3 — Restore verification, backup-status honesty, docs

**Context:** `plan.md` acceptance criteria; audit report `plans/reports/audit-260717-0900-restore-share-autolock.md` (restore fixes already merged: envelope decoupled, push isolated, honest errors).

## Requirements
- Prove the acceptance criteria end-to-end on devices.
- The "Backed up" label on passkeys stops overpromising when sync is off.
- Docs reflect the new plane.

## Steps
1. **Backup-status copy** (`VaultifyCore/Passkey/PasskeyBackupStatus.swift`, `Vaultify/Features/Passkeys/PasskeyDetailSheet.swift`):
   - Today the label derives from WebAuthn BE/BS flags alone — true for the RP protocol, misleading for the user when `iCloudSyncEnabled` is off (file backup was the only path; the audit called this out).
   - Change the DISPLAY (not the RP-visible flags — ecosystem contract, do not touch `newCredentialFlags`): sync on → "Backed up with iCloud Sync"; sync off → "On this device. Included in encrypted exports." Strings EN + VI in `Localizable.xcstrings`; follow copy rules (no "!", no "—", no "·").
   - Keep `PasskeyBackupStatus` pure; feed it the sync-enabled bit from the caller.
2. **Device checklist** (two devices, TestFlight or dev builds, iCloud sync ON, Production schema deployed):
   - A: register passkey in-app and via AutoFill on a real site → B foreground+unlock → passkey present, QuickType offers it, assertion signs in.
   - A: delete the passkey → B next sync → gone (no resurrection after B's further syncs).
   - A: iOS 18 silent locked registration (extension, vault locked) → unlock app on A (envelope migration) → syncs to B.
   - Fresh-install restore: delete app on A → reinstall → restore by recovery key → passkeys restored and usable; Watchtower/identities intact.
   - Erase Vault on A → B loses zone (existing behavior) — passkeys gone everywhere, Emergency Kit can no longer resurrect (matches `eraseRemote` doc).
   - Regression sweep: large blob read/write after sync; shared-passkey (Approval Mode) rows unaffected.
3. **Docs**: update `docs/codebase-summary.md` (sync planes list + passkey storage paragraph) and add one line to the audit report's follow-ups marking RC-2 closed by this plan.
4. Full suite + `make check`; sync plan files' status; conventional commits, PR per repo workflow.

## Tests
- Unit: `PasskeyBackupStatusTests` — extend for the sync-aware display mapping.
- Everything else is the device checklist above (CloudKit-touching methods follow the repo's two-account device-checklist convention, same as the sharing transport).

## Risks / rollback
- Copy change is display-only; rollback trivial.
- If restore returns passkeys but QuickType is stale: `CredentialIdentityService.refresh` runs on reload — re-check step 6 of phase 2 before debugging elsewhere.
