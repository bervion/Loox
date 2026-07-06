# P4A Phase 2 — Canonical signed RelayCommand + parity vectors

**Priority:** P1 · **Status:** pending · **Effort:** ~3h · **Blocks on:** P1 (principalID/epoch/sign/verify).

## Context links
- Decisions: D2 (P256 signing), D5 (rotation command: epoch-N key signs "rotate to N+1, newPubKey"),
  INV-R02 (Principal layer ≠ App Attest layer — DO NOT fold them).
- Blueprints: `Vaultify/Features/Sharing/LooxLink/LooxLinkCanonical.swift:17-54` (frozen magic +
  length-prefixed BE transcript + parity-vector shape), `VaultifyTests/LooxLinkCanonicalTests.swift`
  (frozen-fixture parity test pattern), `VaultifyCore/Sharing/ApprovalCanonical.swift:119-152`
  (`FieldCapability` tag-byte discriminated-union encoding — mirror for command kinds),
  `VaultifyTests/Fixtures/app-attest-create-share-vectors-v1.json` (vector JSON shape).

## Overview
A `RelayCommand` covering `principalID + epoch + nonce + issuedAt + kind + kind-payload`, encoded
via `CanonicalWriter` under MAGIC `LOOX-RELAY-AUTHZ-V1` (length-prefixed, version + type tag).
`sign(command:using:)` → `(transcript, signature)`; `verify`. Ship a frozen parity-vector JSON so
the future worker (P4B) can be cross-checked byte-for-byte. NO network — sign/verify only.

## Key insights
- **Reuse `CanonicalWriter`** (do NOT reinvent framing — D2/note4). Follow the `ApprovalWire`
  convention: leading `version` byte + `TypeTag` byte domain-separate signatures, so a `createAlias`
  transcript can never verify as a `rotatePrincipal` or a `disableAll`.
- **Rotation is a command kind**, not a parallel rail (KISS/DRY, mirrors `ApprovalRequest` folding
  passkey into a v2 field rather than a new artifact). `rotatePrincipal` carries `newPublicKey`
  (x963). Semantics (old epoch authorizes the next) are a backend CAS concern (INV-R04) — the client
  only produces bytes; the SIGNER is the current identity from P1.
- **INV-R02 note in header:** this signature is the Principal-authorization layer ONLY. App Attest
  admission (D9, per-service state, `LooxLinkAttestation` pattern) is a SEPARATE layer added at
  network time in P4B. The two MUST NOT be merged.
- Parity vectors are FROZEN — changing the layout requires a new version tag on both sides.

## Architecture
```
RelayCommandKind (UInt8 tag, nonisolated enum): createAlias=1, disableAlias=2, rotateDestination=3,
    deleteAlias=4, disableAll=5, rotatePrincipal=6
RelayCommand (nonisolated struct, Sendable, Equatable)
  ├─ principalID: Data        ├─ epoch: UInt64      ├─ nonce: Data (anti-replay, single-use)
  ├─ issuedAtUnixMs: Int64    ├─ kind: RelayCommandKind
  └─ payload: aliasID: String? · destination: String? · newPublicKey: Data?  (kind-gated)
RelayCommandCanonical (nonisolated enum)
  ├─ magic = "LOOX-RELAY-AUTHZ-V1"  ├─ version: UInt8 = 1
  ├─ static transcript(_ cmd) -> Data
  ├─ static func sign(_ cmd, using RelayPrincipalIdentity) throws -> (transcript: Data, signature: Data)
  └─ static func verify(_ cmd, signature:, publicKeyRaw:) -> Bool
```
Transcript layout (CanonicalWriter, all length-prefixed except leading magic/version/tag):
`Data(magic.utf8)` (no prefix) ‖ `byte(version)` ‖ `byte(kind.rawValue)` ‖ `blob(principalID)` ‖
`u64(epoch)` ‖ `blob(nonce)` ‖ `i64(issuedAtUnixMs)` ‖ then kind-gated fields in fixed order:
`optionalString(aliasID)` ‖ `optionalString(destination)` ‖ `optionalBlob(newPublicKey)`.
(Use a 0/1 flag byte for each optional — add `optionalBlob`/`optionalString` helpers if absent, or
encode empty-as-present per a documented rule; state the rule in the header and vector `note`.)
Signature covers the transcript bytes; `sign` calls `identity.signature(for: transcript)`.

## Related code files
**Create**
- `VaultifyCore/Relay/RelayCommand.swift` (<90 LOC)
- `VaultifyCore/Relay/RelayCommandCanonical.swift` (<120 LOC)
- `VaultifyTests/Fixtures/relay-authz-command-vectors-v1.json`
- `VaultifyTests/RelayCommandCanonicalTests.swift`
**Read** — LooxLinkCanonical.swift, ApprovalCanonical.swift, LooxLinkCanonicalTests.swift

## Implementation steps
1. `RelayCommand` + `RelayCommandKind`. Optional-field discipline: exactly which optionals are
   non-nil per kind (createAlias→aliasID; disableAlias/deleteAlias→aliasID; rotateDestination→
   aliasID+destination; disableAll→none; rotatePrincipal→newPublicKey). Document; do NOT enforce at
   type level V1 (KISS) — the transcript encodes whatever is set, deterministically.
2. `RelayCommandCanonical.transcript` per layout. Fixed field order regardless of kind (each optional
   flag-gated) so encoding is a single code path (mirrors `LooxLinkCanonical`).
3. `sign` (P1 identity) + `verify` (P1 `RelayPrincipalIdentity.verify`).
4. Generate parity vectors: write a tiny throwaway Swift/`swift` snippet OR hand-compute using the
   frozen KAT key from P1 — produce ≥5 vectors (one per kind incl. rotatePrincipal + one disableAll
   with all-nil optionals). Each vector: `name, principal_id_hex, epoch, nonce_b64, issued_at_ms,
   kind, alias_id?, destination?, new_public_key_b64?, canonical_bytes_hex, signature_note`.
   NOTE: ECDSA is non-deterministic → store `canonical_bytes_hex` (byte parity, the real gate) and
   verify signatures dynamically, NOT a frozen signature hex. Mirror `app-attest-...vectors-v1.json`.
5. `RelayCommandCanonicalTests`: load fixture (Bundle-for-class pattern from `LooxLinkCanonicalTests`),
   assert `hex(transcript(cmd)) == canonical_bytes_hex` for every vector.
6. `tuist generate --no-open` (fixture auto-added via `resources: ["VaultifyTests/Fixtures/**"]`,
   `Project.swift:227`); `make check`.

## Todo
- [ ] RelayCommand + kinds
- [ ] RelayCommandCanonical (transcript/sign/verify)
- [ ] relay-authz-command-vectors-v1.json (≥5 vectors, all kinds)
- [ ] RelayCommandCanonicalTests (byte-parity)
- [ ] tuist generate + make check green

## Success criteria (concrete crypto assertions)
- **Byte parity:** every fixture vector's `hex(transcript) == canonical_bytes_hex` (the worker gate).
- **Sign/verify roundtrip:** `verify(cmd, sign(cmd, id).signature, id.signingPublicKey) == true`.
- **Tamper rejection:** mutate epoch (or nonce/aliasID) after signing → `verify == false`.
- **Domain separation:** a `createAlias` transcript signed for cmd A does not verify against a
  `rotatePrincipal` cmd with identical scalar fields (type tag differs → transcript differs).
- **Wrong-epoch surfaces in bytes:** two commands differing only in `epoch` produce different
  `canonical_bytes_hex` (models D5 "old epoch rejected" at the byte level).
- **disableAll all-nil:** encodes deterministically with three 0-flag optionals; roundtrips.

## Risk assessment
| Risk | L×I | Mitigation |
|------|-----|-----------|
| Transcript diverges from future worker | Med×High | Frozen `_hex` vectors are the contract; parity test fails loudly on drift |
| Optional-encoding ambiguity (nil vs empty) | Med×Med | Explicit flag-byte rule documented in header + vector `note`; test all-nil case |
| Someone folds App Attest into this signature | Low×High | Header states INV-R02 two-layer rule; App Attest deferred to P4B |
| ECDSA non-determinism baked into a frozen sig | Med×Med | Vectors freeze transcript bytes only; verify sigs dynamically |

## Security considerations
Nonce is single-use anti-replay (backend consumes authoritatively, INV-R04 — client just includes
it). `issuedAtUnixMs` is absolute Unix ms (kernel time convention, `ApprovalModels.swift:5`). MAGIC +
version + type tag give injective domain separation. No secrets in a command — it is signed, not sealed.

## Next steps
P3 uses `rotated()` (P1) + `sign` (here) to produce the escrow-overwrite rotation flow.
P4B worker imports these vectors to verify its TS/Rust encoder byte-for-byte.
