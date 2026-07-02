---
phase: 1
title: "Core WebAuthn Correctness & Data Model"
status: completed
priority: P1
effort: "6h"
dependencies: []
---

# Phase 1: Core WebAuthn Correctness & Data Model

## Overview
Bring the shared passkey core (`VaultifyCore/Passkey/`) to WebAuthn L3 correctness — per-credential flags (BE/BS), stable AAGUID, injected store access, atomic dedupe, lifecycle metadata — and put the whole layer under unit tests. Fixes findings F6, F7, F9, F10, F12 (scout report) + red-team RT-3/RT-6/RT-9/RT-11/RT-14.

## Requirements
- Functional: BE/BS flags on NEW credentials (legacy keep UP|UV), Vaultify AAGUID, passkey delete + lastUsedAt, atomic replace-on-duplicate, eraseAll covers passkeys, store injection.
- Non-functional: crypto/data types `nonisolated`; no API above iOS 17.6; SwiftData lightweight migration only (new optional columns/fields); no `try?`-swallowed writes in new code.

## Architecture
`WebAuthn` stays a pure `nonisolated enum` (no store access). `PasskeyVault` remains the only store gateway but **takes an injected `VaultStore`** (RT-3: today it builds a throwaway `ModelContainer` per call over the real container, is un-testable, and `VaultStore()` can `fatalError` mid-ceremony — `PasskeyVault.swift:13,21`, `VaultStore.swift:10-13`). Consumers: app passes its long-lived `AppEnvironment.store`; the extension creates ONE `try VaultStore(recoverable: false)` per ceremony; tests use in-memory. App-facing reads return metadata-only `PasskeyInfo` (never `privateKeyRaw` — RT-11).

## Related Code Files
- Modify: `VaultifyCore/Passkey/WebAuthn.swift`
- Modify: `VaultifyCore/Passkey/PasskeyModels.swift`
- Modify: `VaultifyCore/Passkey/PasskeyVault.swift`
- Modify: `VaultifyCore/Store/VaultStore.swift`
- Modify: `VaultifyAutoFill/CredentialProviderViewController.swift` — **mechanical adaptation only** (RT-9: it is the sole caller of `matching`/`save` at `:169,:188`; adapt call sites to the new signatures so `make check` passes; the real rework of this path is Phase 2)
- Create: `VaultifyTests/WebAuthnTests.swift`
- Create: `VaultifyTests/PasskeyVaultTests.swift`

## Implementation Steps
1. **WebAuthn.swift — flags** (RT-14, user-confirmed): add `flagBackupEligible = 0x08`, `flagBackupState = 0x10`. NEW registrations emit `UP|UV|BE|BS|AT` (`0x5D`) and the base flags (`0x1D`) are RETURNED for storage. `assertion(...)` gains a `flags: UInt8` parameter — callers pass the credential's stored flags. Rationale comment: BE/BS constant 1|1 for new credentials (vault is device-backup-able + exportable; ecosystem parity with iCloud Keychain/1Password); BE immutable per credential ⇒ NEVER change flags of an existing credential; legacy credentials (stored `flags == nil`) keep asserting `UP|UV` (`0x05`) — exactly what they registered with, so nothing breaks at strict RPs.
2. **WebAuthn.swift — AAGUID**: replace zero AAGUID with a fixed Vaultify UUID (generate once with `uuidgen`, hardcode 16 bytes). Spec-legal with none-attestation (best-practices report Q3). Comment: constant is frozen forever after first release.
3. **PasskeyModels.swift**:
   - `PasskeySecret`: add `var flags: UInt8?` (Codable optional — old sealed payloads decode as nil ⇒ legacy `UP|UV`).
   - `PasskeyRecord`: add `var lastUsedAt: Date?` (plaintext metadata column, lightweight migration).
   - Add `nonisolated struct PasskeyInfo: Sendable` — metadata projection for app/UI/identity use: `relyingParty, userName, userHandle, credentialID, createdAt, lastUsedAt`. NO private key (RT-11).
4. **PasskeyVault.swift — injected, throwing, atomic**:
   - All APIs take the store explicitly (e.g. `PasskeyVault(store:)` struct or `store:` parameter) — no internal `VaultStore()` construction anywhere (RT-3).
   - `SecureBytes` overloads alongside `[UInt8]`, mirroring `AESGCM` (`AESGCM.swift:24-30`) — no "bridging accessor" that copies key material out of `SecureBytes` (RT-11).
   - Reshape `save(_:key:)` → throws, performs replace-on-duplicate: decrypt existing records for same `relyingParty`+`userHandle`, delete them and insert the new record **in one `context.save()`** (RT-6 atomicity — a committed delete + failed insert would destroy the user's only working credential). Returns `replaced: [PasskeySecret]` (full secrets, NOT bare IDs — Phase 2 must build accurate removal identities from them, RT-10).
   - Reshape `all`/`matching` (both EXIST today — this is a signature change, not an addition): return `[PasskeyInfo]` for app-facing use; extension signing path gets `secret(credentialID:key:) -> PasskeySecret?` (private key only where signing happens). Sort: lastUsedAt desc, createdAt desc.
   - Add `delete(credentialID:)`, `touchLastUsed(credentialID:)` (column-only). Write-failure policy: throw where the caller can react (save/delete); `touchLastUsed` failure is non-fatal → log marker, never `try?`-silent.
5. **VaultStore.eraseAll()**: add `try context.delete(model: PasskeyRecord.self)` (bug F6).
6. **Tests — WebAuthnTests** (pure): rpIdHash == SHA256(rpId); registration flags byte `0x5D`, new-assertion `0x1D`, legacy-assertion `0x05`; signCount bytes zero; attestationObject CBOR decode (fmt "none", empty attStmt, authData equal); COSE key exact header bytes `A5 01 02 03 26 20 01 21 58 20 … 22 58 20 …` with x/y halves; assertion signature verifies via `P256.Signing.PublicKey.isValidSignature(_:for: authData + clientDataHash)`; CBOR int boundaries 23/24/255/256/65535/65536 + negatives.
7. **Tests — PasskeyVaultTests** (in-memory injected store — now possible via RT-3): save→read roundtrip; replace-on-duplicate returns replaced secrets; distinct userHandle same rp coexists; **induced-failure test**: force insert failure (e.g. in-memory store closed/invalid context) and assert prior records survive (atomicity, RT-6); delete; touchLastUsed ordering; eraseAll clears PasskeyRecord.
8. Adapt `CredentialProviderViewController.swift:166-194` call sites mechanically (one recoverable store per ceremony; new signatures). `tuist generate` → `make check` → `make test`.

## Success Criteria
- [x] New credentials carry UP|UV|BE|BS(|AT); stored `flags` drive assertions; legacy secrets assert UP|UV unchanged
- [x] Fixed non-zero AAGUID emitted; frozen-constant comment present
- [x] `PasskeyVault` fully injected (zero internal `VaultStore()` constructions), throwing, atomic replace verified by induced-failure test
- [x] `eraseAll` deletes PasskeyRecord rows
- [x] App + extension compile (`make check`); new tests pass (`make test`)

## Risk Assessment
- **SwiftData migration**: new optional column is lightweight; verify store opens on an upgraded simulator container before merging.
- **Extension adaptation churn**: Phase 2 rewrites this path next — keep Phase 1 edits mechanical (signatures only) to avoid double manual-testing (RT-9).
- **Phantom credential residual** (RT-6): if the extension dies after `context.save()` but before `completeRegistrationRequest`, a stored passkey exists that the RP never finished registering — harmless orphan, visible/deletable in Phase 4 UI; documented, not solved.
