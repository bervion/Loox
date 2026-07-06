# P4A Phase 1 — Relay Principal crypto core + escrow codec

**Priority:** P1 (blocks P2, P3) · **Status:** pending · **Effort:** ~3h · **Target:** compile + unit-test, no network.

## Context links
- Decisions: `proposal-v3-locked-decisions.md` D2 (P256.Signing only, `principalID = SHA256("LOOX-RELAY-PRINCIPAL-V1" ‖ x963 pub)`), D5 (epoch state), INV-R01.
- Blueprints: `VaultifyCore/Sharing/ParticipantIdentity.swift:13-43` (escrowSealed/fromEscrow, throw-not-regenerate), `VaultifyCore/Sharing/ApprovalCrypto.swift:16-78` (`DeviceSigningIdentity` P256/Keychain/sign/verify), `VaultifyCore/Sharing/ApprovalCanonical.swift:32-61` (`CanonicalWriter`), `VaultifyCore/Crypto/AESGCM.swift:8-31`.

## Overview
Introduce the Relay Principal: a user-owned P256.Signing keypair whose `principalID` is a
frozen SHA-256 fingerprint over its **genesis** X9.63 public key. Carries a `UInt64` epoch.
Private key sealed under the Vault Key (`AESGCM`) into a versioned escrow envelope. This phase
is PURE VaultifyCore (no CloudKit) so it is fully unit-testable.

## Key insights
- **principalID is frozen at genesis** (D5: backend pins `principal_id` stable while
  `current_public_key`/`epoch` rotate). It must be stored in the escrow envelope, NOT recomputed
  from the current key after rotation — otherwise a rotated key would change the identity.
- **X9.63 for the fingerprint** (D2/note4) — deliberate deviation from `DeviceSigningIdentity`
  which uses `.rawRepresentation`. Use `publicKey.x963Representation` for the principalID input;
  use `privateKey.rawRepresentation` (32 B) for escrow storage. Document both.
- **Throw, never silently regenerate** on corrupt escrow/keychain material (mirror
  `ParticipantIdentity.fromEscrow` and `DeviceSigningIdentity.loadOrCreate`) — a silent new key
  changes principalID and breaks every backend pin.
- Types are `nonisolated struct/enum` + `Sendable` (Argon2/crypto isolation rule; MainActor default).

## Architecture
```
RelayPrincipalIdentity (nonisolated struct, Sendable)
  ├─ privateKey: P256.Signing.PrivateKey
  ├─ epoch: UInt64
  ├─ principalID: Data (32) — FROZEN, carried not derived-live
  ├─ var signingPublicKey: Data { privateKey.publicKey.x963Representation }
  ├─ static generate() -> genesis: new key, epoch=1, principalID=derive(pub)
  ├─ static func derivePrincipalID(x963Pub:) -> Data  (CanonicalWriter: string(MAGIC)+blob(pub) → SHA256)
  ├─ func escrowSealed(vaultKey:) throws -> Data       ([ver:1] ‖ AESGCM(body))
  ├─ static func fromEscrow(_:vaultKey:) throws         (throws unknownVersion / invalidKeyMaterial)
  └─ func rotated() -> RelayPrincipalIdentity           (new key, epoch+1, SAME principalID)  [pure]
RelayPrincipalState (nonisolated struct, Codable, Sendable) — D5 public projection
  └─ { principalID: Data, epoch: UInt64, signingPublicKey: Data }; init(from identity:)
RelayConfig (nonisolated enum) — MAGIC strings, escrow record type/name, keychain cache account
```
Escrow envelope body (sealed under Vault Key via AESGCM):
`CanonicalWriter{ blob(principalID) ; u64(epoch) ; blob(privateKey.rawRepresentation) }`.
Outer: `Data([escrowVersion=1]) ‖ AESGCM.seal(body, key: vaultKey)`. (Mirrors
`ParticipantIdentity.escrowSealed` shape: `[version] ‖ AESGCM(...)`.)

## Related code files
**Create**
- `VaultifyCore/Relay/RelayPrincipalIdentity.swift` (<140 LOC)
- `VaultifyCore/Relay/RelayPrincipalState.swift` (<40 LOC)
- `VaultifyCore/Relay/RelayConfig.swift` (<40 LOC)
- `VaultifyTests/RelayPrincipalIdentityTests.swift`
**Read (do not edit)**
- `VaultifyCore/Sharing/ParticipantIdentity.swift`, `.../ApprovalCrypto.swift`, `.../ApprovalCanonical.swift`, `VaultifyCore/Crypto/AESGCM.swift`

## Implementation steps
1. `RelayConfig`: `principalMagic = "LOOX-RELAY-PRINCIPAL-V1"`; escrow keychain cache account
   `"relay_principal_escrow_cache_v1"`; CloudKit `escrowRecordType = "RelayPrincipalEscrow"`,
   `escrowRecordName = "relay-principal-escrow"` (used by P3). Reuse `ApprovalConfig.containerID`.
2. `RelayPrincipalIdentity.derivePrincipalID(x963Pub:)` — `CanonicalWriter`: `.string(RelayConfig.principalMagic)`, `.blob(x963Pub)`, then `Data(SHA256.hash(data: w.data))`.
3. `generate()` — new `P256.Signing.PrivateKey()`, epoch `1`, `principalID = derivePrincipalID(key.publicKey.x963Representation)`.
4. `escrowSealed(vaultKey:)` / `fromEscrow(_:vaultKey:)` per envelope layout above; `fromEscrow`
   recomputes-and-verifies principalID matches the stored one (defence: reject a tampered envelope
   whose stored principalID ≠ derive(currentPub) only when epoch==1/genesis; for epoch>1 the pub has
   rotated so principalID is trusted as stored — document this asymmetry). Throw
   `EscrowFailure.invalidKeyMaterial` on bad key bytes, `.unknownVersion` on bad version byte.
5. `signature(for:)` + `static verify(_:signature:publicKeyRaw:)` — copy `DeviceSigningIdentity`
   ECDSA-P256/SHA-256 64-byte raw-signature pattern verbatim (used by P2).
6. `rotated()` — pure: `let k = P256.Signing.PrivateKey()`; return identity with `k`, `epoch+1`,
   unchanged `principalID`. (P3 wraps this with escrow overwrite; P2 signs the rotate command.)
7. `RelayPrincipalState(from:)` — projection `{principalID, epoch, signingPublicKey}`.
8. `tuist generate --no-open`; `make check`.

## Todo
- [ ] RelayConfig constants
- [ ] RelayPrincipalIdentity (generate/derive/escrow/sign/verify/rotated)
- [ ] RelayPrincipalState projection
- [ ] RelayPrincipalIdentityTests
- [ ] tuist generate + make check green

## Success criteria (concrete crypto assertions)
- **Determinism KAT:** for a fixed private key (hard-coded raw hex in test), `derivePrincipalID`
  yields a fixed 32-byte principalID hex — assert exact value (freeze it as the first parity anchor).
- **Escrow roundtrip:** `fromEscrow(escrowSealed(vaultKey), vaultKey)` returns an identity with equal
  privateKey.rawRepresentation, epoch, and principalID.
- **Wrong key fails:** `fromEscrow(envelope, otherVaultKey)` throws (AESGCM open failure surfaces).
- **Corrupt material throws, not regenerates:** flip a body byte → `fromEscrow` throws
  `.invalidKeyMaterial`/AESGCM error; bad version byte → `.unknownVersion`.
- **Rotation preserves identity:** `id.rotated()` has `epoch == id.epoch+1`,
  `principalID == id.principalID`, `signingPublicKey != id.signingPublicKey`.
- **Sign/verify:** `verify(msg, sign(msg), signingPublicKey) == true`; tampered msg → false.

## Risk assessment
| Risk | L×I | Mitigation |
|------|-----|-----------|
| principalID recomputed post-rotation → identity drift | Low×High | Store principalID in envelope; test rotation preserves it (step 4/6, success criteria) |
| x963 vs raw pubkey mismatch with future worker | Med×High | Freeze in parity vector (P2) + KAT here; document choice in header |
| Silent regen on corrupt keychain breaks pins | Low×High | Throw-not-regenerate (step 4), explicit test |

## Security considerations
Private key only ever exists sealed under the Vault Key (AESGCM-256) or in-memory while unlocked.
No plaintext persistence. `principalID` is a public fingerprint (safe to log/transmit). MAGIC domain-
separates the fingerprint from any other SHA-256 use.

## Next steps
P2 consumes `principalID`, `epoch`, `signature/verify`, `rotated()`. P3 wraps escrow in CloudKit.
