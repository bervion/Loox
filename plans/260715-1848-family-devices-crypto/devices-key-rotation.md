# Project B — Devices revoke via Vault-Key rotation

Goal: truly revoke a device — rotate the 32-byte Vault Key so a removed device can no longer decrypt **future** ciphertext **or** write accepted mutations, without losing data on kept devices. Highest-risk work in the app; strictly phased + gated.

Grounded by scout `plans/reports/scout-260715-1955-crypto-surface-map.md`. Review incorporated: P0-B1..B7, P1-B8..B10, INV-ROT-01..06.

## Current (verified)
One 32-byte VK seals data (`AESGCM`), wrapped under password (Argon2id) + recovery + biometric KEKs (`KeyHierarchy` / `VaultKeyBundle`); synced only as a recovery envelope; provisioned to devices via QR pairing or Emergency Kit. **No rotation exists**; deleting a device record does nothing. **No epoch/version on any record** (scout §4; no SwiftData `VersionedSchema` — `ModelContainer` built directly). Merge = LWW in `VaultStore.upsertFromRemote` via the `CloudSyncService.pull()` dispatch (scout §5). Sharing grants carry **no VK-derived material** → VK rotation does **not** invalidate published shares (scout note 4): **A and B are crypto-decoupled.**

## THE CENTRAL CORRECTION (review P0-B1 + scout §1)
Rotation is NOT "re-encrypt ItemRecords." Two hard truths the first plan missed:
1. **It must change the authoritative WRITE epoch and reject old-epoch mutations.** Else a revoked, offline device holding `K1` keeps creating/uploading `K1` ciphertext that kept devices — still holding `K1` in the dual-key read window — decrypt and merge (LWW). Write access would survive revocation. Re-encryption alone is necessary but not sufficient.
2. **VK seals 12+ non-`ItemRecord` surfaces, several device-LOCAL** (scout §1). Rotation therefore runs on **every kept device**, not server-side — a pure remote re-encrypt cannot reach attachments, passkeys, shared caches, or UI-state.

---

## B0 — CONTRACT FREEZE (before B1; no code until frozen)

### 1. `VaultCiphertextInventoryV1` — the complete re-seal set (scout §1)
**Synced CK records** (owner rotates + pushes): `ItemRecord.sealed` (a), `avatarSealed` (a′), `PersonaRecord` (f), `FolderRecord` (f′), `EmailAliasRecord` (f″), `ForwardingInboxRecord` (f‴), `AuditReportRecord` + `FindingStateRecord` (k), `ParticipantIdentity` escrow (h), `RelayPrincipalIdentity` escrow (k″ — keep its own inner relay epoch).
**Device-LOCAL** (each kept device re-seals after adopting `K'`): `Attachments/*.enc` (c), Passkeys `PasskeyRecord.sealed` + `largeBlobSealed` + `envelopePrivateKeySealed` (e), `SharedCredentialsCache` (h′), `SharedItemsProjection` snapshot (h″), `UIStateStore` (k′), `BiometricKeyStore` raw-VK copy (k⁗), `ExtensionSessionStore` (scout note 5).
**Re-WRAP not re-seal**: `VaultKeyBundle` (k‴) — regenerate `wrappedByPassword`, `wrappedByRecovery`, `wrappedL2SK`, re-seal `envelopePrivateKeySealed`.
**DO NOT TOUCH** (inner layers, non-VK): `SecretGuard` `v2g:` payloads (L2SK / custom-code) inside items — re-seal the **outer** item only; inner bytes stay byte-identical; `L2SK` itself persists (its wrapper `wrappedL2SK` is re-wrapped). **Out of scope**: `VaultBackup` (passphrase KEK), `AuditLocalCache` (own keychain secret), `InviteLinkService` (ephemeral link key).
**B1 is not complete until a KAT covers EACH synced record family + each device-local surface.**

### 2. `VaultEpochAuthority` — owner-signed control record (INV-ROT-01)
```
VaultEpochAuthority {
  vaultId, currentEpoch, rotationId,
  authorizedDeviceSetHash, state, committedAtUnixMs,
  ownerSignature   // P256, over all fields above
}
```
Signed by the vault-owner identity key (same P256 signing identity family used for `AccessGrant`/pairing; **B0 freezes exactly which key + how each device pins it**). Synced singleton in the `Vault` zone. Kept devices read it; a revoked device cannot forge an epoch bump or roll it back (signature + monotonic `currentEpoch`).

### 3. Write-rejection gate (INV-ROT-01) — at the pull choke point (scout §5)
Add plaintext `keyEpoch: Int` to every synced record (write side `CloudSyncService.ckRecord(from:)` `:182-200` + siblings). Gate at the `CloudSyncService.pull()` dispatch closure (`:156-168`) — the **single funnel** every record type passes through before per-type `apply*`: reject/quarantine any record with `keyEpoch < authority.currentEpoch`. This advisory (plaintext) gate PLUS the cryptographic backstop (post-teardown, `K1` records simply won't open under `K'`). Both layers — the gate closes the dual-key window before teardown.

### 4. State machine (review P0-B3) — security commit ≠ migration done
```
IDLE(E)
 → PREPARING(E→E+1): mint rotationId, generate K', persist compact journal, compute kept/revoked set
 → DISTRIBUTING:      publish K' envelope to each kept device (sealed to its pinned pubkey); collect adoption PROOFS
 → COMMITTED(E+1):    ── SECURITY CUT POINT ── authority record signed+committed; currentEpoch=E+1;
                         revoked devices excluded; old-epoch writes rejected; new writes seal under K'
 → MIGRATING:         background re-seal E→E+1 (per-record CAS), resumable
 → FINALIZING:        verify new recovery + Emergency Kit; disable/delete OLD escrow+kit; drop K1 (ends dual-key window)
 → COMPLETE(E+1)
```
Revocation takes effect at **COMMITTED** (before migration finishes). Teardown (drop `K1`) only at **FINALIZING**, after kept-device proofs. Offline kept device temporarily loses access at COMMITTED and recovers when it adopts `K'`.

### 5. Adoption = proof of possession (INV-ROT-03), not a boolean
A kept device proves it holds `K'` before teardown: sign `{ rotationId, vaultId, epoch, deviceId, challenge, K'commitment }` with its **pinned device key**, where `K'commitment` = HMAC/known-answer under `K'` (proves possession, not a flag), **and** assert its local re-seal (contract 1) complete. Teardown blocked until every kept device's proof lands (or an explicit, warned grace path for a lost device).

### 6. Key lifetime (INV-ROT-02, -04, -05)
- Previous key = **decrypt-only**; every new/updated record seals under **current** (never write under previous).
- **At most one rotation active**; do not start E+2 until E→E+1 is finalized (only current + previous retained).
- Raw VK **never** syncs in plaintext or under a shared/global wrap; a **device-targeted** envelope (`K'` sealed to a specific pinned device pubkey) **may** sync. (Honest restatement of "Vault Key never syncs".)

### 7. Journal — compact, record-is-truth (review P0-B7)
```
RotationJournal { rotationId, fromEpoch, toEpoch, phase, cursor, counts, startedAtUnixMs, newKeyWrappedState }
```
**Not** a persisted set of migrated record IDs (unbounded, corruption-prone). Resume by querying `keyEpoch < toEpoch`; the record's own `keyEpoch` is the migrated flag.

### 8. Recovery honesty (INV-ROT-06)
Rotation protects the **current online vault epoch**. It does NOT erase cached plaintext, old exported backups, or pre-rotation ciphertext an attacker already holds. Wording: "the old Emergency Kit no longer recovers the current vault after rotation" — **never** "old kit can no longer decrypt any old data."

---

## Phases (each gated on its checklist)
- **B0 — Contract freeze**: the 8 contracts above. *No code.*
- **B1 — Multi-epoch crypto kernel (UNIT-TESTABLE)**: `keyEpoch` across ALL synced record types; current/previous keyring; decrypt-fallback read; encrypt-current-only; full-inventory coverage (contract 1); single-rotation guard. **KATs per record family + each device-local surface.** *(The one large chunk verifiable headless.)*
- **B2 — Crash-safe local rotation**: compact journal; background migrator with per-record CAS (read rev R → decrypt `K1` → seal `K2` → write iff still R, else retry latest); no global long write-freeze; kill-injection tests. *Device: rotate on A → all decrypt; kill mid-migration → relaunch resumes, zero loss.*
- **B3 — KEK / recovery artifacts**: re-wrap `K'` under password + biometric + a NEW recovery KEK; regenerate Emergency Kit; atomic KEK switch; old kit rejected for the CURRENT epoch; rollback tests. *Device: unlock via password + biometric post-rotation; new kit recovers, old kit rejected for current vault.*
- **B4 — Device reprovision + epoch authority**: device-targeted `K'` envelope to kept devices; possession-proof adoption; sign + commit `VaultEpochAuthority`; reject old-epoch writes at the pull gate; teardown after proofs. *2-device: B (kept) adopts + decrypts; C (revoked, offline) can't decrypt NEW writes AND its old-epoch writes are rejected after it syncs; teardown blocked until B proves.*
- **B5 — UX + rollout**: Devices → select device → **Remove Access** → explain rotation → choose kept devices → **preflight** (N ready / M offline / kit will be replaced / record count) → master password + biometric → **phase-based progress** (Preparing new protection / Updating this device / Securing vault items / Waiting for <device> / Finishing) → backgroundable after a local safety checkpoint. Feature flag; telemetry.

## Invariants (INV-ROT-01..06)
- **INV-ROT-01** — after epoch E+1 is committed, writes authored under E must not be accepted into live vault state (E stays available only for read-only migration fallback).
- **INV-ROT-02** — the previous epoch key is decrypt-only; every new/updated record seals under the current epoch.
- **INV-ROT-03** — kept-device adoption requires cryptographic proof of possession of the new key, signed by the pinned device identity key.
- **INV-ROT-04** — at most one rotation active; a new rotation must not start until the previous is finalized.
- **INV-ROT-05** — raw Vault Keys never sync; only device-targeted, public-key-sealed key envelopes may be transported.
- **INV-ROT-06** — rotation revokes future/current-vault access; it does not erase historically cached plaintext or old ciphertext.

## Threat model
Rotation protects FUTURE ciphertext + rejects post-commit old-epoch writes from a removed device; it does NOT reclaim cached plaintext or an old Emergency Kit (teardown MUST delete old escrow + kit). Offline kept device loses access from COMMITTED until it adopts `K'` (warn explicitly). Crash mid-migration → dual-key + compact journal + CAS. Device-local surfaces (attachments, passkeys, shared caches, UI-state) must be re-sealed on each kept device before its adoption proof, or they become permanently undecryptable. **Never** weaken key-sync honesty (INV-ROT-05).

## Test matrix (2 devices + crash/race injection)
rotate on A → all items + attachments + passkeys + personas/folders/aliases/audit decrypt on A · kill app mid-migration → relaunch resumes, zero loss · **revoked device uploads old-epoch edit after commit → rejected/quarantined** · kept device acks wrong epoch → rejected · kept device acks without possession of `K'` → rejected · second rotation starts while one active → blocked · record edited concurrently with re-seal → no lost update (CAS) · new item created during migration → sealed only under `K'` · attachment/passkey migration killed mid-chunk → resumes · cache/extension holds old key → zeroized/invalidated · old pairing envelope replay → rejected by rotationId/epoch · owner device dies after commit before migration done → kept device resumes · all kept devices offline → explicit recovery path · biometric + password unlock post-rotation · new kit recovers, old kit rejected for current epoch · teardown blocked until B proves.

## Risks
Data loss is the dominant risk — every phase gated on the crash/offline/race matrix; old escrow/key deleted only after kept-device possession proofs. Device-local re-seal multiplies the surface (attachments/passkeys/caches) and must run on each kept device. Large: estimate multiple sessions. `/ak:security` review before B4/B5 ship.
