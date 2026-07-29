# Passkey CloudKit Sync (`VaultPasskey`)

**Status:** IMPLEMENTED (branch `feat/passkey-cloudkit-sync`, 260717) — code + tests done; PENDING: CloudKit Production deploy of `VaultPasskey` (OPS gate) and the phase-3 two-device checklist.
- **260729 — the OPS gate is now a CONFIRMED user-visible bug, not a latent risk.** The owner reports passkeys not syncing between two devices on one iCloud account, and an audit traced it here: the plane pushes, Production rejects the unknown record type, `dirty` never clears, and the other device's delta pull returns zero passkey records. Items and folders keep syncing because `push()` is fault-isolated per plane, which is exactly the reported symptom. No code fix applies. Follow-up work landed on `feat/sf-icons-crash-reporting-260729`: per-plane sync errors are now surfaced and a schema error reads as a configuration problem retrying cannot fix, plus a CKRecord mapping round-trip test that pins the field names/types Production must carry. The deploy step is now in `docs/deployment-guide.md` so this class cannot recur.
- Phase 1 ✓ (columns, tombstone-with-wipe, LWW helpers, `PasskeySyncMergeTests` 11 tests green + all legacy passkey suites)
- Phase 2 ✓ (plane wired into the fault-isolated push + pull switch; post-sync reload verified to refresh passkeys + QuickType) — OPS gate outstanding
- Phase 3 ✓ code (badge honesty via existing localized strings; docs synced) / ☐ device checklist (user)
- Deviation: badge copy reuses existing "This device only" (EN+VI already in catalog) instead of new strings — badge length constraint, zero new localization surface.
- Review (code-reviewer, 260717): all majors fixed before the schema deploy while the wire shape was free — always-written wire fields (`deletedAtMs` Int64, blob empty-Data sentinel; `.changedKeys` can't clear an omitted field: tombstones now wipe the cloud blob and backup re-imports clear the cloud tombstone), envelope-staged `delete()` hard-deletes (silent-registration rollback left no cloud junk), passkey delete/import call `noteLocalMutation()` for the debounced push, remote tombstone apply clears staging/hints, 255-char record-name guard. Revival-upsert + blob-clear pinned by 4 new tests. Deliberately dropped: the phase-02 CK-mapping roundtrip unit test (mapping funcs are private on the CKContainer-owning service; wire semantics covered by store tests + the phase-3 device checklist, which also answers the empty-Data round-trip question) and the phase-03 `PasskeyBackupStatusTests` extension (the sync-aware mapping lives in the view; the pure enum is unchanged).
**Goal:** passkeys survive delete-app → reinstall → restore-by-recovery-key, and sync between the user's devices, closing the last gap from the 260717 audit (`plans/reports/audit-260717-0900-restore-share-autolock.md`, Bug 1/RC-2: `PasskeyRecord` was never part of CloudKit sync — restores mechanically lose passkeys).

## Approach (one paragraph)
Give `PasskeyRecord` the exact sync columns `FolderRecord` already carries (`updatedAt`, `deletedAt` tombstone, `dirty`, `ckRecordName`, `ckChangeTag`), add a `VaultPasskey` plane to `CloudSyncService` mirroring the folder push/apply/LWW pattern (already fault-isolated per plane since the audit fix), and turn `PasskeyVault.delete` into a material-wiping tombstone. Only ciphertext leaves the device: `sealed` and `largeBlobSealed` are AES-256-GCM under the Vault Key, same trust model as items/folders. Records still staged as iOS 18 locked-writes (`envelopeSealed != nil`) never sync — they become syncable when the existing unlock migration re-seals them.

## Locked design decisions (ADRs)
1. **Counter churn is a non-issue:** the sign counter is constant 0 (`WebAuthn.swift:9`), so `sealed` is immutable after creation except large-blob writes. No per-assertion re-seal, no cross-device counter regressions.
2. **`usedAt` stays device-local** (not synced, never marks dirty) — mirrors items preserving local `useCount` on remote apply.
3. **Delete = tombstone that wipes material:** `deletedAt` set, `sealed`/`largeBlobSealed`/`envelopeSealed` cleared, `dirty = true`. Remote apply of a tombstone wipes the other device too. No resurrection (upsert-only sync would resurrect deletes).
4. **Envelope-staged records never sync** (`envelopeSealed != nil` excluded from push): they are lock-time staging only this device can migrate; `deletePending` quarantine keeps hard-deleting them.
5. **Record name = existing `PasskeyRecord.id`** (base64url credentialID) — a random identifier we mint; reveals nothing about the relying party without the sealed payload. Metadata exposure: timestamps only, same class as folders. Accepted nuance (review): the RP also stores the credentialID server-side, so CloudKit-metadata access PLUS RP collusion could link an iCloud account to an RP account; a hashed name buys nothing against that and breaks key-less addressing. Push guards ids > 255 chars (CKRecord name cap; only reachable via iOS 26 credential-exchange imports of foreign ids) — revisit with a hashed-name scheme before credential exchange ships broadly.
6. **Backfill = migration default:** new `dirty` column defaults `true`, so every pre-existing sealed passkey uploads on the first sync after update. No bespoke migration pass.

## Phases
| # | Phase | File | Depends on |
|---|-------|------|-----------|
| 1 | Model + store discipline (columns, tombstone delete, LWW helpers, merge tests) | `phase-01-model-and-store.md` | — |
| 2 | CloudSync plane + CloudKit schema gate | `phase-02-cloud-sync-plane.md` | 1, OPS gate |
| 3 | Restore/E2E verification + backup-status copy + docs | `phase-03-restore-verification-ui.md` | 2 |

## OPS GATE (blocking, user action)
`VaultPasskey` must exist in the **Production** CloudKit schema BEFORE any TestFlight build with phase 2 ships (Production has no just-in-time schema creation; the plane would error — isolated since the audit fix, but never syncing). Console steps in phase-02. Do it in the same Console session as the still-pending audit deploys (`VaultPersona`, `VaultEmailAlias`, `VaultForwardingInbox`, `AuditReport`, `AuditFindingState`).

## Acceptance criteria
1. Fresh install → create vault + passkeys → delete app → reinstall → restore by recovery key → every passkey present and signs in via AutoFill (no file backup involved).
2. Two devices, same account, sync on: passkey registered on A appears on B after B's next sync; deleting on A removes it from B (tombstone, no resurrection).
3. A passkey created by the AutoFill extension while unlocked syncs after the next app foreground; an iOS 18 silent (locked) registration syncs after the app's unlock migration re-seals it.
4. CloudKit only ever holds ciphertext + timestamps for passkeys (`sealed`, `largeBlobSealed`, dates) — no hints, no plaintext, no `envelopeSealed`.
5. `tuist generate` + `make check` green (app + extension share the SwiftData model — additive lightweight migration); full suite green including new merge tests; any new user-facing string lands EN + VI.
6. Erase Vault still removes cloud passkeys (zone delete — no code change, verified in phase 3).

## Risks
- SwiftData additive migration on the shared app-group store (app + extension): additive columns with defaults = lightweight; both targets ship in the same build. Downgrading to an older build after migration is unsupported (same policy as previous model changes).
- LWW granularity is whole-record: concurrent large-blob writes on two devices resolve last-writer-wins per credential (acceptable; blobs are per-RP convenience data).
- Rollback: the plane is additive — reverting the code leaves harmless `VaultPasskey` records in the zone; local columns stay but are inert.
