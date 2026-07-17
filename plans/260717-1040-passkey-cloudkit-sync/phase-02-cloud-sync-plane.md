# Phase 2 — CloudSync plane + schema gate

**Context:** `plan.md` (ADRs, OPS gate); template: folder plane in `Vaultify/Services/Sync/CloudSyncService.swift` (`pushFolders` ~line 139, `ckFolderRecord` ~234, `applyFolder` ~247); push() is fault-isolated per plane since the 260717 audit fix.

## Requirements
- New `VaultPasskey` record plane: push dirty sealed records, pull-apply via the phase-1 LWW helper.
- Envelope-staged records never leave the device.
- Old app versions ignore the new type (existing `default: break` in the pull switch — verified in the audit).

## OPS GATE (user, blocking before this phase ships)
CloudKit Console → container `iCloud.com.bervion.vaultify`:
1. Run a Debug build with this phase once against the **Development** environment (JIT creates `VaultPasskey` with all fields), or create the type manually.
2. Fields: `sealed` (Bytes), `largeBlobSealed` (Bytes, optional), `createdAt` (Date/Time), `updatedAt` (Date/Time), `deletedAt` (Date/Time, optional). No queryable indexes needed (zone delta fetch only — same rationale as the folder plane comment).
3. **Deploy Schema Changes → Production.** Same session: deploy the audit's still-pending types (`VaultPersona`, `VaultEmailAlias`, `VaultForwardingInbox`, `AuditReport`, `AuditFindingState`) if not done yet.

## Files
- Modify: `Vaultify/Services/Sync/CloudSyncService.swift`

## Steps
1. `private let passkeyRecordType = "VaultPasskey"`.
2. `ckPasskeyRecord(from record: PasskeyRecord) -> CKRecord` — recordName = `record.id`, fields per OPS gate list; omit nil optionals (mirror `ckPersonaRecord`'s `deletedAt` handling).
3. `pushPasskeys()` — mirror `pushFolders` exactly:
   - `let dirty = store.allPasskeyRecords().filter { $0.dirty && $0.envelopeSealed == nil }` (ADR-4 exclusion, with a comment naming the invariant),
   - snapshot `updatedAt` before the await, `savePolicy: .changedKeys`, `markPasskeySynced` per save result.
4. `applyPasskey(_ record: CKRecord)` — guard-decode fields → `store.upsertPasskeyFromRemote(...)` (all LWW lives in the tested store helper).
5. Wire in: add `do { try await pushPasskeys() } catch { firstError = firstError ?? error }` to `push()`, and `case self.passkeyRecordType: self.applyPasskey(record)` to the pull switch.
6. Verify the post-sync reload closes the loop: `CloudSyncService.sync(reload:)` → `repository.reloadAfterRemoteSync()` must re-read `passkeyVault.all` and call `CredentialIdentityService.refresh(items:passkeys:)` (the unlock reload at `VaultRepository.swift:70-71` already does — confirm the remote-sync reload shares that path; if not, extend it).
7. Compile check (`make check`), then full suite.

## Tests
- Phase 1's `PasskeySyncMergeTests` already cover the merge core (plane is thin mapping).
- Add one mapping roundtrip test: `ckPasskeyRecord(from:)` → `applyPasskey`-equivalent decode reproduces the record on a second in-memory store (construct the `CKRecord` directly in the test, folder-test precedent permitting; otherwise assert field-for-field on the built `CKRecord`).
- Manual (sim, two containers not required): DEBUG file-based self-test unnecessary — device pass happens in phase 3.

## Risks / rollback
- Shipping before the Production deploy: plane errors are isolated (items/envelope unaffected) and surface in Settings → iCloud Sync status; passkeys simply don't sync until the deploy lands. Still: treat the OPS gate as blocking.
- Rollback = remove the plane wiring; stray `VaultPasskey` records in the zone are inert and die with zone deletion (Erase Vault).
