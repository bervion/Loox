# Design — Devices revoke (vault-key rotation) + threat model

Status: **Design / decision pending.** Grounds plan phase 06 ADR-D. No code here.

## Current architecture (verified)
- **One 32-byte Vault Key** seals every record via AES-256-GCM (`AESGCM.seal(_, key: vaultKey)` — `VaultWriter.swift:48` / `VaultReader.swift:94`). Generated + wrapped in `KeyHierarchy.swift`.
- The key is **wrapped under three KEKs**: password (Argon2id), recovery key (Argon2id), biometric (Secure Enclave). It **never appears in plaintext in CloudKit** — only as a recovery envelope (`VaultKeyEscrowService`), itself encrypted under the recovery passphrase.
- Devices obtain the key by **QR pairing** (HPKE to an ephemeral key, `VaultKeyPairing.swift`) or **Emergency-Kit recovery**. **The Vault Key never syncs.**
- **No key-rotation mechanism exists.**
- The device registry (shipped this PR) lists devices; "revoke" = cutting a listed device's ability to read the vault.

## What "revoke a device" actually requires
Deleting a device's `OwnerDevice` record does **nothing** — it still holds the Vault Key in its Keychain and can unseal any synced ciphertext. True revoke ⇒ make the old key useless to it ⇒ **rotate the Vault Key**:
1. Generate a new key `K'`.
2. **Re-seal EVERY sealed record** (items, folders, personas, aliases, inboxes, audit reports) `K → K'`. Must be crash-safe (see risks).
3. Re-wrap `K'` under all three KEKs on this device.
4. Re-publish the recovery envelope under a NEW recovery passphrase → **the printed Emergency Kit goes stale** (regenerate + reprint).
5. Re-provision `K'` to KEPT devices — but the key never syncs, so each must **re-pair (QR) or recover**. There is no secure silent push channel for `K'`.
6. The revoked device keeps `K` — useless against re-sealed records, but see below.

## Threat model
**Rotation protects:** a lost / stolen / retired / untrusted device can no longer decrypt FUTURE synced ciphertext, once all records are re-sealed under `K'` and it never receives `K'`.
**Rotation CANNOT protect:**
- **Cached plaintext** — anything the device already unsealed or exported is unrecoverable; crypto can't claw it back.
- **Old Emergency Kit** — whoever holds the OLD kit can recover the OLD snapshot from any surviving escrow copy until it is deleted/overwritten. Rotation must also delete old escrow.
- **Local ciphertext snapshot** — a revoked device offline keeps reading its pre-rotation cache forever. Revoke ≠ remote wipe.

## Risks (why this is dangerous)
- **Data loss (highest):** re-sealing every record is not atomic. A crash mid-rotation leaves a mix of `K`- and `K'`-sealed records; without a per-record key tag + resumable journal, the vault becomes partially unreadable. Requires a **dual-key read window** (try `K'`, fall back to `K`) until migration completes, plus idempotent resume.
- **Offline / never-returning kept devices:** a kept device offline during rotation can't get `K'` and fails to unseal the re-sealed records after it next syncs — indistinguishable from data loss to the user until it re-pairs/recovers.
- **Recovery-kit invalidation:** silently invalidating a printed kit is a support/UX landmine.

## Recommendation (honest)
Full cryptographic revoke is **high-risk, high-effort, and only partially effective** (cached plaintext survives) in this single-symmetric-key design. Options, safest first:

- **R0 — "Sign out this device" (no rotation, ship-able, honest).** Self sign-out clears THIS device's session/biometric wrap + deletes its registry record. For OTHER devices it can only remove the record + warn; it must be **clearly labeled as not retroactively revoking access.** Low risk, no false security.
- **R1 — Master-password change (existing lever, `ChangeMasterPasswordView`).** Re-wraps `K` under a new password KEK. Does NOT rotate `K` → a device with `K` cached still reads. Useful UX ("secure my vault") but **not true revoke.**
- **R2 — Full key rotation (real revoke, standalone reviewed project).** Steps 1–6 with a per-record key-epoch tag, dual-key read window, resumable journal, forced re-pair of kept devices, kit regeneration, and old-escrow deletion only after kept devices confirm `K'`. Ships only after a written threat-model sign-off + a two-device crash/offline test matrix.

**Proposed decision:** ship **R0** (honest "sign out / lost device" UX — no button that implies revocation it doesn't deliver); schedule **R2** as its own security-reviewed effort. **Do NOT** ship a "Remove device" that fakes revocation.

## R2 guardrails (if chosen)
Per-record key-epoch tag · dual-key read (K' then K) until fully migrated · resumable journal in the store · rotation gated behind an explicit master-password action + single-flight · old escrow deleted only after kept-device adoption or a warned grace window · new Emergency Kit generated + old invalidated · tests: crash-injection mid-migration, offline kept device, revoked-device offline snapshot.
