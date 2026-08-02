---
title: "Phase 3: First-Class Secure Artifact Lifecycle"
status: done
---

# Phase 3: First-Class Secure Artifact Lifecycle

## Outcome

Turn device-local attachment pointers into durable encrypted artifacts suitable for SSH keys,
`.p8`, `.p12`, certificates, provisioning profiles, and later Secure File.

## Requirements

- [ ] Transactional stage/commit/rollback; cancelling an editor leaves no orphan ciphertext.
- [ ] Explicit owner/reference graph, tombstones, garbage collection, and erase-all behavior.
- [ ] Size limits before allocation and an independently reviewed AEAD construction; bounded one-shot
  encryption is the fallback when no suitable streaming construction is available.
- [ ] Sealed manifest plus content hash/length; ciphertext is bound to owner, artifact ID, and version.
- [ ] Encrypted backup v2 includes every artifact; optional CloudKit uses a dedicated `CKAsset` plane.
- [ ] Plaintext exports use unique protected temp directories and deterministic cleanup.

## Proposed Storage Contract

`ArtifactRecord` owns stable ID, owner item/field ID, wrapped artifact DEK, sealed manifest,
ciphertext location, byte count, ciphertext hash, dirty/change tag, sync policy, and `deletedAt`.
The manifest contains original filename, UTI/MIME, expected length/hash, and parser metadata.
Use domain-separated AAD including artifact ID, owner item ID, purpose, and schema version.

For v1, every artifact is single-owner. CloudKit-visible records use opaque random names and expose only
transport necessities; filename, MIME, item kind/role, owner identity, and plaintext hash stay sealed.
If an integrity identifier must be visible, use ciphertext hash; plaintext integrity/dedupe uses a keyed
value inside the sealed manifest. Document unavoidable leakage from ciphertext size, timing, and count.

## File Inventory

- Add versioned SwiftData artifact models and a `SchemaMigrationPlan` in `VaultifyCore/Store/`.
- Replace/encapsulate `Vaultify/Services/AttachmentStore.swift` with staged artifact services.
- Modify item editor picker, attachment row/preview/export, repository delete, and erase-vault paths.
- Add CloudKit record mapping and `CKAsset` transport under `Vaultify/Services/Sync/`.
- Add encrypted backup bundle v2 manifest/blob streaming and transactional restore.
- Add janitor, orphan-reconciliation, and metrics that never contain filenames or hashes.
- Add the CloudKit schema deployment/full-refetch runbook before the record type is enabled.

## Implementation Steps

1. Specify state machine and crash-window table: temp write/fsync, recovery-journal append, SwiftData
   commit, final rename, rollback/reconcile, edit-delete race, disk full, and process kill. “Atomic” means
   every state has an idempotent recovery invariant, not a cross-filesystem/database transaction.
2. Run a time-boxed crypto spike and independent review to select an exact iOS 17.3-compatible
   construction/library and wire format. If no reviewed streaming construction fits, use bounded one-shot
   AEAD with a strict small-file ceiling instead of assembling a custom streaming protocol. Then introduce
   a random per-artifact DEK wrapped by
   the vault key. The protocol authenticates header, algorithm/key version, artifact/owner/purpose,
   chunk index, per-chunk/total length, and final manifest. It guarantees a unique nonce per chunk across
   crash/retry/resume and rejects missing, reordered, duplicated, truncated, or cross-artifact chunks.
3. Stage imports outside the committed graph. Commit item/reference/file transitions through the
   recovery journal and idempotent reconciliation; rollback on cancel/failure. Reconcile at launch/unlock
   and cascade cleanup on item delete.
4. Make preview/export explicit actions with re-auth policy. Use one random temp directory per action;
   clean on dismiss, failure, lock/background policy, and cold-launch janitor.
5. Define portable backup v2 with stable item IDs or an explicit two-pass old→new ID remap covering
   artifact owners and every `ItemLink`. Use a backup master key derived from the backup passphrase. Authenticate
   the manifest before allocation; unwrap each artifact DEK from the source vault and rewrap it to the
   backup hierarchy without exporting the vault key. Restore unwraps via backup key then rewraps to the
   destination vault key, validates completeness/free space, and commits all-or-nothing.
6. Add CloudKit artifact record/tombstone mapping and `CKAsset` uploads. Specify single-owner conflict,
   two-phase delete, versioned tombstone/grace period, offline resurrection prevention, and both
   `local-only → synced` and `synced → local-only` transitions. Remote-only bytes show an explicit
   “available on another device”, “downloading”, or “unavailable” state.
7. Prevent upgrade cursor loss: use a per-plane/versioned cursor or a mandatory one-time full artifact
   refetch when artifact support appears. Test an old app consuming an unknown-record event and advancing
   the zone cursor before upgrade. Upload artifact before publishing its item reference; converge item
   tombstone before artifact garbage collection; retry each plane independently.
8. Separate action authorization from cryptographic protection. Vault-key artifacts use UI re-auth as
   policy; Level-2 artifacts wrap the DEK with the Level-2 key/envelope, and preview/export requires both
   an action-bound authorization token and the correct crypto key.
9. Add an idempotent filesystem/SwiftData recovery journal for crash boundaries and key rewrap/rotation.
10. Migrate legacy `att:` pointers lazily: adopt found files, show “file unavailable” for missing bytes,
   never fabricate success, and allow metadata cleanup.

## Verification Matrix

- Unit: state transitions, KATs, nonce uniqueness/reuse regression, AAD swap rejection, and chunk
  truncation/reordering/duplication/cross-artifact mix-and-match/size/hash mismatch.
- Integration: add/save/cancel/edit/remove/item-delete/erase-vault and launch orphan reconciliation.
- Backup: N items plus N artifacts restore atomically into a completely new vault/Keychain; missing or
  corrupt blob aborts without partial items; no source vault key is available to the restore test.
- CloudKit: upload/update/delete/optional-clear/offline retry and two-device convergence.
- Upgrade: old binary consumes unknown artifact change/cursor → new binary full-refetches the artifact.
- Runtime: preview/export temp content is gone after dismiss, vault lock, crash simulation, and relaunch.
- Performance: reject oversized file before full read; memory stays bounded for maximum supported size.

## Risks and Mitigations

- CloudKit schema rollout is irreversible: deploy new record types in development, test, then production
  before enabling the feature flag.
- File sync can consume quota/data: default to explicit policy, show size, and retry independently.
- Streaming AEAD design is security-sensitive: use established primitives/constructions and golden
  vectors; do not invent a custom unaudited format.

## Success Criteria

- [ ] Artifact/file bytes survive cold launch, encrypted backup restore, and enabled two-device sync.
- [ ] Cancel, delete, and erase leave zero reachable or orphan ciphertext after reconciliation.
- [ ] Missing legacy bytes are reported honestly, not presented as a valid attachment.
- [ ] Plaintext temp artifacts are deterministically removed.
