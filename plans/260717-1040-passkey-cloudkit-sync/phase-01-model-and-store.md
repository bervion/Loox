# Phase 1 — Model + store discipline

**Context:** `plan.md` ADRs 1–6; templates: `VaultifyCore/Store/FolderRecord.swift` (sync columns), `VaultifyCore/Store/VaultStore.swift` folder helpers, `VaultifyTests/CloudSyncMergeTests.swift` (merge-test shape).

## Requirements
- `PasskeyRecord` carries folder-parity sync metadata; existing rows migrate additively and auto-backfill (`dirty` default true).
- Every mutation path sets `dirty`/`updatedAt` correctly; `usedAt` never does.
- Delete becomes a material-wiping tombstone; every read filters tombstones.
- Pure store helpers implement LWW so phase 2's plane is thin mapping only.

## Files
- Modify: `VaultifyCore/Passkey/PasskeyModels.swift` (PasskeyRecord columns)
- Modify: `VaultifyCore/Passkey/PasskeyVault.swift` (+`PasskeyVault+Envelope.swift` migration path)
- Modify: `VaultifyCore/Store/VaultStore.swift` (passkey sync helpers)
- Create: `VaultifyTests/PasskeySyncMergeTests.swift`

## Steps
1. `PasskeyRecord` — add, mirroring `FolderRecord` comments/style:
   - `var updatedAt: Date = .now` (migration default; no cloud copies exist yet so LWW is unaffected)
   - `var deletedAt: Date?`
   - `var dirty: Bool = true`  ← backfill: pre-existing sealed records upload on first sync
   - `var ckRecordName: String?`, `var ckChangeTag: String?`
   Keep init defaults consistent (`dirty = true`, `updatedAt = createdAt` at creation).
2. `PasskeyVault` mutation discipline:
   - `save(_:key:)` (both overloads + replacement path): `updatedAt = .now`, `dirty = true`.
   - `saveEnvelope(_:envelopeSealed:)`: `dirty = false` (locked staging must not sync); unlock migration that re-seals envelope → `sealed` sets `dirty = true`, `updatedAt = .now`, clears `envelopeSealed`.
   - `setLargeBlob`: `dirty = true`, `updatedAt = .now` (blob is synced).
   - `touchLastUsed`: unchanged — must NOT touch `dirty`/`updatedAt` (assert in tests).
   - `delete(credentialID:)` → tombstone: `deletedAt = .now`, `updatedAt = .now`, `dirty = true`, wipe `sealed = Data()`, `largeBlobSealed = nil`, `envelopeSealed = nil`, clear hint fields.
   - `deletePending` (envelope quarantine): keep HARD delete — envelope records never sync (ADR-4).
   - Every read API (`all`, `secrets`, `matching`, `secret`, `hasRecord`, `record(credentialID:)`, `largeBlob`, `secretsForReplacement`, `records()` callers) filters `deletedAt == nil`. Audit `records()` call sites — sync needs tombstones INCLUDED, so add a separate accessor rather than changing `records()` semantics silently.
3. `VaultStore` sync helpers (folder parity, same file section):
   - `allPasskeyRecords() -> [PasskeyRecord]` (includes tombstones, excludes nothing)
   - `passkeyRecord(id:) -> PasskeyRecord?`
   - `markPasskeySynced(_:changeTag:snapshotUpdatedAt:)` — clears `dirty` only when `updatedAt == snapshot` (edit-mid-flight stays dirty; mirror `markFolderSynced`).
   - `upsertPasskeyFromRemote(id:sealed:largeBlobSealed:deletedAt:createdAt:updatedAt:changeTag:)` LWW:
     - no local → insert clean (`dirty = false`, store changeTag).
     - same `changeTag` → skip (no-op reapply).
     - local `updatedAt` newer → keep local, re-mark `dirty = true` (local winner must re-push).
     - remote newer → apply fields; ALWAYS preserve local `usedAt` and any local `envelopeSealed`; a remote tombstone wipes material exactly like local delete.
4. Run the narrowest tests first (`PasskeySyncMergeTests`, `PasskeyVaultTests`), then `make check`.

## Tests (`PasskeySyncMergeTests.swift` — mirror CloudSyncMergeTests style, in-memory `VaultStore`)
- remote-newer applies; local-newer keeps local AND re-marks dirty; same changeTag skips.
- tombstone apply wipes `sealed`/`largeBlobSealed` and hides the credential from `PasskeyVault.all`.
- `markPasskeySynced` clears dirty only when snapshot matches (edited-after-snapshot stays dirty).
- `usedAt` survives a remote apply; `touchLastUsed` leaves `dirty` false.
- envelope-staged record (`envelopeSealed != nil`) is `dirty == false` after `saveEnvelope`, `dirty == true` after unlock migration.
- `delete` tombstone hides from `all/matching/secret/hasRecord` and wipes material.

## Risks / rollback
- SwiftData additive columns on the shared store = lightweight migration; app + AutoFill ship together. Rollback = revert commit (columns disappear from the model; store re-migrates additively next run — data intact).
- Watch `records()` semantics: `PasskeyVault+Envelope` quarantine and DEBUG surfaces use it — keep their current view (decide include/exclude per call site during step 2 audit).
