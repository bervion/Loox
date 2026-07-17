# Passkey CloudKit Sync (`VaultPasskey`)

**Status:** PLANNED — not started
**Goal:** passkeys survive delete-app → reinstall → restore-by-recovery-key, and sync between the user's devices, closing the last gap from the 260717 audit (`plans/reports/audit-260717-0900-restore-share-autolock.md`, Bug 1/RC-2: `PasskeyRecord` was never part of CloudKit sync — restores mechanically lose passkeys).

## Approach (one paragraph)
Give `PasskeyRecord` the exact sync columns `FolderRecord` already carries (`updatedAt`, `deletedAt` tombstone, `dirty`, `ckRecordName`, `ckChangeTag`), add a `VaultPasskey` plane to `CloudSyncService` mirroring the folder push/apply/LWW pattern (already fault-isolated per plane since the audit fix), and turn `PasskeyVault.delete` into a material-wiping tombstone. Only ciphertext leaves the device: `sealed` and `largeBlobSealed` are AES-256-GCM under the Vault Key, same trust model as items/folders. Records still staged as iOS 18 locked-writes (`envelopeSealed != nil`) never sync — they become syncable when the existing unlock migration re-seals them.

## Locked design decisions (ADRs)
1. **Counter churn is a non-issue:** the sign counter is constant 0 (`WebAuthn.swift:9`), so `sealed` is immutable after creation except large-blob writes. No per-assertion re-seal, no cross-device counter regressions.
2. **`usedAt` stays device-local** (not synced, never marks dirty) — mirrors items preserving local `useCount` on remote apply.
3. **Delete = tombstone that wipes material:** `deletedAt` set, `sealed`/`largeBlobSealed`/`envelopeSealed` cleared, `dirty = true`. Remote apply of a tombstone wipes the other device too. No resurrection (upsert-only sync would resurrect deletes).
4. **Envelope-staged records never sync** (`envelopeSealed != nil` excluded from push): they are lock-time staging only this device can migrate; `deletePending` quarantine keeps hard-deleting them.
5. **Record name = existing `PasskeyRecord.id`** (base64url credentialID) — a random identifier we mint; reveals nothing about the relying party without the sealed payload. Metadata exposure: timestamps only, same class as folders.
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
