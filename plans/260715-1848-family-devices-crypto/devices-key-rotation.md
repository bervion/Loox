# Project B — Devices revoke via Vault-Key rotation

Goal: truly revoke a device — rotate the 32-byte Vault Key so a removed device can no longer decrypt FUTURE ciphertext, without losing data on kept devices. Highest-risk work in the app; strictly phased + gated.

## Current (verified)
One 32-byte key seals every record (`AESGCM`, `KeyHierarchy`); wrapped under password (Argon2id) + recovery + biometric KEKs; synced only as a recovery envelope (`VaultKeyEscrowService`); provisioned to devices via QR pairing (`VaultKeyPairing`) or Emergency Kit. **No rotation exists.** Deleting a device record does nothing (device keeps the key).

## Design
- **Per-record key epoch**: add a plaintext `keyEpoch: Int` column to `ItemRecord` (which key sealed it). **Dual-key read window**: `VaultReader` tries the current-epoch key, falls back to the previous key — so a partially-migrated vault always reads.
- **Rotation engine**: generate `K'` (epoch+1); for each sealed record, unseal(K)→seal(K'), set `keyEpoch`; a **resumable journal** (persisted set of migrated record ids) makes it idempotent + crash-safe. Runs under an explicit master-password action, single-flight, blocks other writes during migration.
- **Re-wrap KEKs**: `K'` under the password KEK (needs master password), a NEW recovery KEK (→ regenerate Emergency Kit), biometric (Secure Enclave).
- **Re-provision kept devices** (key never syncs): each kept device adopts `K'` via the **pairing channel** — either forced re-pair (QR) OR a per-device escrow drop of `K'` wrapped to that device's pairing key. **Adoption tracking**: a kept device confirms `K'` adoption (writes an ack) before teardown.
- **Teardown**: only AFTER all kept devices ack (or a warned grace window) — delete the OLD recovery escrow, invalidate the OLD Emergency Kit, drop the previous-epoch key + dual-key fallback.

## Phases (each gated on its checklist)
- **B1 — Local re-seal engine (UNIT-TESTABLE, single device)**: `keyEpoch` column + dual-key read + rotation engine + resumable journal, behind a flag. **KAT/unit tests**: rotate → every item still decrypts under `K'`; kill mid-migration → resume → no loss; dual-key reads both epochs. *(This is the one big chunk I can verify headless.)*
- **B2 — Re-wrap + escrow + kit**: re-wrap `K'` under all 3 KEKs; new recovery envelope; regenerate Emergency Kit; mark old kit stale. *Device check: unlock via password + biometric after rotation; new kit recovers, old kit rejected.*
- **B3 — Multi-device re-provision**: pairing-drop of `K'` to kept devices + adoption ack + teardown-after-adoption. *2-device check: device B (kept) re-adopts and decrypts; device C (revoked, offline) can't decrypt post-rotation writes after it syncs; teardown only after B acks.*
- **B4 — UI**: Devices → "Rotate key (removes other devices' access)" with master-password gate, progress, and honest warnings (cached data, offline kept devices, kit regeneration). Replaces any placeholder.

## Threat model
Rotation protects FUTURE ciphertext against a removed device; it does NOT reclaim cached plaintext or an old Emergency Kit (so teardown MUST delete old escrow). Offline kept device fails to decrypt re-sealed records until it re-pairs (warn explicitly). Crash mid-migration is covered by dual-key + journal. **Never** weaken "Vault Key never syncs" — re-provision is pairing/escrow, not a synced key.

## Test matrix (2 devices + crash injection)
rotate on A → all items decrypt on A · kill app mid-migration → relaunch resumes, zero loss · B (kept) adopts `K'` → decrypts · C (revoked) offline → after rotation+sync can't decrypt new writes · old kit rejected, new kit recovers · teardown blocked until B acks · biometric + password unlock post-rotation.

## Risks
Data loss is the dominant risk — every phase gated on the crash/offline matrix; old escrow/key deleted only after kept-device adoption. Large: estimate multiple sessions. `/ak:security` review before B3/B4 ship.
