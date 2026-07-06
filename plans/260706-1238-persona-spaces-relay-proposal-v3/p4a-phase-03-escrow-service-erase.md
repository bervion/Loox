# P4A Phase 3 — RelayPrincipalEscrowService + rotation + erase wiring

**Priority:** P1 · **Status:** pending · **Effort:** ~3h · **Blocks on:** P1 (identity/escrow codec, rotated()), P2 (sign rotate cmd).

## Context links
- Decisions: D3 (dedicated CloudKit singleton `RelayPrincipalEscrow`, clone `ParticipantEscrowService`
  verbatim: transactional first-writer-wins, Keychain fast-cache, self-creates zone, independent of
  `iCloudSyncEnabled`, gate on `CloudSyncService.isConfigured`), D4 (Erase Vault → principal dies with
  the zone; disable-all orchestration is P4B, NOT here), D5 (rotation = escrow overwrite).
- Blueprints (clone): `Vaultify/Services/Sharing/ParticipantEscrowService.swift:17-108` (whole file),
  `Vaultify/Services/Sync/CloudSyncService.swift:74-84` (`eraseRemote` drops `CKRecordZone("Vault")`),
  `Vaultify/App/AppEnvironment.swift:112-137` (`eraseEverything` teardown; `ParticipantEscrowService.clearLocalCache()` at :132).

## Overview
Wrap the P1 identity in a CloudKit escrow service that mirrors `ParticipantEscrowService`
byte-for-byte in structure: cache → cloud → transactional first-writer-wins create, self-creating the
`"Vault"` zone, gated on `CloudSyncService.isConfigured` (VAULTIFY_ICLOUD). Add `rotate(vaultKey:)`
(P1 `rotated()` + P2 signed rotate command + CAS-style escrow overwrite). Wire erase teardown.
NO network beyond CloudKit escrow; no worker.

## Key insights
- **Same `"Vault"` zone as sync + participant escrow** (`ParticipantEscrowService.swift:27`,
  `CloudSyncService.swift:22`, `VaultKeyEscrowService.swift:34`). Because `eraseRemote()` deletes
  `zone.zoneID` (`CloudSyncService.swift:74-84`), the RelayPrincipalEscrow record dies automatically —
  this is exactly how D4 "principal dies with the zone" is satisfied. No new erase-remote code needed;
  only add `clearLocalCache()` to the local teardown.
- **No-op gracefully when `isConfigured == false`** (non-VAULTIFY_ICLOUD builds): the ensure/rotate
  methods throw `Failure.notConfigured` exactly like the blueprint (`ParticipantEscrowService.swift:34`).
  Callers must tolerate this (P4A ships nothing that calls it in a user path yet — `RelayFeature.activeAliasesEnabled` stays false).
- **First-writer-wins** on multi-device first create (blueprint :58-73) — the principalID a device may
  already have pinned can never be silently replaced; a losing device adopts the winner's identity.
- **Rotation overwrite** must NOT use first-writer-wins — rotation deliberately REPLACES. Use
  `.changedKeys`/fetch-then-save with the current change tag (last-writer-wins for the overwrite), and
  cache the new envelope. The signed rotate command is produced but NOT sent anywhere in P4A (backend
  CAS is P4B) — store/return it for the future client; unit-test that it verifies under the OLD key.
- App target file (CloudKit + MainActor), so `@MainActor final class` like the blueprint.

## Architecture
```
@MainActor final class RelayPrincipalEscrowService
  ├─ container = CKContainer(ApprovalConfig.containerID); database = privateCloudDatabase
  ├─ zone = CKRecordZone("Vault")
  ├─ cacheAccount = RelayConfig cache account
  ├─ func ensurePrincipal(vaultKey:) async throws -> RelayPrincipalIdentity   [cache→cloud→create]
  ├─ func rotate(vaultKey:) async throws -> (RelayPrincipalIdentity, rotateCommandSignature: Data)
  │       (load current → id.rotated() → P2.sign(rotatePrincipal cmd, using OLD id) → overwrite escrow → cache)
  ├─ private adoptExisting / fetchEscrowEnvelope / escrowRecordID   [verbatim from blueprint]
  └─ static func clearLocalCache()
```
Escrow record: type `RelayConfig.escrowRecordType` ("RelayPrincipalEscrow"), name
`RelayConfig.escrowRecordName` ("relay-principal-escrow"), field `ApprovalRecordMapping.Field.sealed`
carrying `identity.escrowSealed(vaultKey:)` (P1). Reuse the existing `sealed` field constant.

## Related code files
**Create**
- `Vaultify/Services/Relay/RelayPrincipalEscrowService.swift` (<150 LOC)
- `VaultifyTests/RelayPrincipalRotationTests.swift` (pure-rotation + escrow-codec level; CloudKit paths not unit-testable)
**Edit**
- `Vaultify/App/AppEnvironment.swift` — add `RelayPrincipalEscrowService.clearLocalCache()` in
  `eraseEverything()` next to `:132`.
- `VaultifyCore/Relay/RelayConfig.swift` (P1) — confirm escrow record type/name/cache account present.
**Read** — ParticipantEscrowService.swift, CloudSyncService.swift, ApprovalRecordMapping.swift.

## Implementation steps
1. Clone `ParticipantEscrowService` into `RelayPrincipalEscrowService`; swap: identity type →
   `RelayPrincipalIdentity`, record type/name/cache account → `RelayConfig.*`, `escrowSealed`/
   `fromEscrow` calls → P1. Keep `isExistingRecordCollision`, `adoptExisting`, zone self-create,
   `isConfigured` gate VERBATIM.
2. `ensurePrincipal(vaultKey:)` — identical control flow to `ensureIdentity` (blueprint :33-74):
   cache hit → cloud hit → transactional create with `.ifServerRecordUnchanged` + collision→adopt.
3. `rotate(vaultKey:)` — load current identity; `let next = current.rotated()`; build
   `RelayCommand(kind: .rotatePrincipal, principalID: current.principalID, epoch: current.epoch,
   nonce: CryptoRandom.bytes(16), issuedAtUnixMs: now, newPublicKey: next.signingPublicKey)`;
   `sig = try RelayCommandCanonical.sign(cmd, using: current).signature`; fetch existing record,
   overwrite `sealed` with `next.escrowSealed(vaultKey:)` using the fetched record's change tag
   (last-writer-wins); update cache; return `(next, sig)`.
4. `clearLocalCache()` → `KeychainStore.delete(account: RelayConfig cacheAccount)`.
5. Wire `AppEnvironment.eraseEverything()`: add `RelayPrincipalEscrowService.clearLocalCache()` after
   `ParticipantEscrowService.clearLocalCache()` (`:132`). Add a comment that the remote escrow dies
   with the `"Vault"` zone via `eraseRemote()` (no extra remote call). NO offline-block-erase (D4 UX)
   — that only applies once active aliases exist (P4B); note it as deferred.
6. Tests (`RelayPrincipalRotationTests`): drive the PURE rotation + escrow-codec path (no CloudKit):
   `id → rotated() → escrowSealed → fromEscrow` preserves principalID, bumps epoch; the produced
   rotate command verifies under the OLD `signingPublicKey` and FAILS under the NEW one.
7. `tuist generate --no-open`; `make check`; `make test`.

## Todo
- [ ] RelayPrincipalEscrowService (clone + swap)
- [ ] ensurePrincipal (cache/cloud/first-writer-wins create)
- [ ] rotate (rotated() + signed cmd + overwrite + cache)
- [ ] clearLocalCache + AppEnvironment erase wiring
- [ ] RelayPrincipalRotationTests
- [ ] tuist generate + make check + make test green

## Success criteria
- `make check` + `make test` green; new files globbed (app target `Vaultify/**`).
- **isConfigured=false no-op:** on a non-VAULTIFY_ICLOUD build `ensurePrincipal` throws
  `.notConfigured` and never touches CloudKit (compile + reason-through; matches blueprint).
- **Erase:** `clearLocalCache()` present in `eraseEverything()`; escrow record is in the `"Vault"`
  zone that `eraseRemote()` deletes (traced to `CloudSyncService.swift:74-84`).
- **Rotation (unit):** rotate path preserves principalID, `epoch+1`, new pubkey; rotate command
  verifies under OLD key only.
- **Structural parity:** first-writer-wins create + collision→adopt identical to
  `ParticipantEscrowService` (diff should be type/name swaps only).

## Risk assessment
| Risk | L×I | Mitigation |
|------|-----|-----------|
| Rotation uses first-writer-wins → overwrite silently fails | Med×High | rotate uses fetch-then-save w/ change tag (last-writer-wins), explicitly NOT the create path |
| Escrow survives erase (zone mismatch) | Low×High | Use `"Vault"` zone verbatim; traced that `eraseRemote` drops it (:74-84) |
| Service called on non-iCloud build crashes | Low×Med | `isConfigured` gate throws early; no P4A user path calls it (flag off) |
| Two devices race genesis → divergent principalID | Low×High | First-writer-wins adopt (blueprint) — losing device adopts winner |

## Security considerations
Escrow envelope is Vault-Key-sealed (AESGCM-256); CloudKit sees only ciphertext in the `sealed` field
and an opaque singleton record name. Private key never leaves the device in plaintext. Rotation
signature proves the CURRENT key authorized the next epoch (D5) — produced here, enforced by backend
CAS in P4B. Erase drops both the local cache and the remote zone.

## Next steps → P4B (backend/worker) — DEFERRED
Live `RelayAPIClient`, worker verification of these transcripts/signatures, `disable-all` durable ack
+ offline-block-erase UX (D4), App Attest per-service admission (D9), rate-limit/kill-switch/cron
(INV-R04), alias activation (`RelayFeature.activeAliasesEnabled` → true).
