# CloudKit Artifact Schema Runbook

Status: artifact record mapping and merge logic ship in code with the sync flag OFF
(`SettingsStore.artifactSyncEnabled`, default false). This runbook is the gate for turning it on.
CloudKit schema rollout is irreversible; follow the order exactly.

## Why the flag is off

Artifact CloudKit writes stay disabled until the live two-device convergence gate passes
(plan: Release C). Decode/recovery paths are always enabled — flags gate discovery and
writes, never reading. Turning the flag on before the schema exists in Production would
strand records; deploying schema without the runbook risks a cursor wipe for old clients.

## Rollout order

1. **Development environment**: launch a dev build with the flag ON. CloudKit auto-creates
   the `ArtifactV2` record type from the first write. Verify in CloudKit Console:
   fields `wrappedDEK` (Bytes), `sealedManifest` (Bytes), `byteCount` (Int64),
   `ciphertextHash` (Bytes), `asset` (Asset), `deletedAtMs` (Int64), `updatedAtMs` (Int64).
   Record names are opaque UUIDs; no filename, MIME, owner identity, or plaintext hash is
   visible — only ciphertext size/count leak, which is the documented budget.
2. **Deploy schema to Production** via CloudKit Console (Deploy Schema Changes). Do this
   BEFORE any TestFlight build can write artifact records.
3. **Two-device staging gate** (signed TestFlight builds, two physical devices, same iCloud
   account, named owner runs the session):
   - Device A imports an SSH key file item; artifact uploads; Device B converges: metadata
     AND bytes present, fingerprint matches.
   - Edit on A → B converges. Delete item on A → artifact tombstone converges on B; bytes
     removed after grace period; no resurrection after B goes offline/online.
   - `synced → local-only` transition removes remote bytes and keeps local; `local-only →
     synced` uploads.
   - Old-build device (flag off) receives the unknown `ArtifactV2` change, advances nothing
     it shouldn't: artifact plane uses its OWN cursor key, so the item-plane cursor is
     untouched. After updating, the new build performs its one-time full artifact refetch.
   - Record evidence (screenshots + item ids) in the release PR before tagging.
4. **Enable** the flag default in `SettingsStore` in its own reviewed commit.

## Fix-forward

A shipped binary is never assumed safely downgradable. If artifact sync misbehaves in
production: disable creation/import surfaces first (UI gate), never decode. The
`ArtifactV2` type stays; records are ciphertext and inert. Owner: release owner of the
tag that enabled the flag; SLA: disable-writes decision within 24h of a confirmed
P0 sync defect.

## Leakage budget (accepted)

CloudKit sees: record count, ciphertext sizes, change timing, opaque names. It never sees
filenames, MIME types, item kinds, owner item ids in plaintext, or plaintext hashes.
