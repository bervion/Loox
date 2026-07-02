---
phase: 5
title: "Envelope Key & iOS 18 Auto-Upgrades"
status: complete
priority: P2
effort: "8h"
dependencies: [1, 3]
---

# Phase 5: Envelope Key & iOS 18 Auto-Upgrades

## Overview
iOS 18 automatic passkey upgrades with the vault locked, via a write-only HPKE envelope (D2): the extension seals new passkeys to a public key; only an unlocked vault can read them. Zero-knowledge READ model unchanged; truly silent path (no UI, no biometric). Rewritten after red-team RT-1/RT-2/RT-4/RT-5/RT-8 (envelope lifecycle, storage, crypto pinning, dedupe, override name).

## Requirements
- Functional: silent passkey creation on system upgrade requests; envelope-sealed records open transparently and migrate to vault-key sealing at unlock; Settings toggle "Automatic passkey upgrades" (**default ON** — user-confirmed 2026-07-02).
- Non-functional: `#available(iOS 18, *)` guarded; envelope crypto `nonisolated`; no plaintext secret persisted; no rp/userName in logs (marker-only — extension logging policy `CredentialProviderViewController.swift:9`); works when the app hasn't launched since reboot.

## Architecture
**Crypto (RT-4 — pinned):** HPKE with the PREDEFINED ciphersuite `HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly` (the AES-GCM/X25519 combo cited earlier does NOT exist in CryptoKit). Every sealed blob and the key fields carry a **1-byte format version** so a future suite change is detectable instead of producing undecodable garbage.

**Storage (RT-5 — no new file):** two optional fields on the EXISTING `VaultKeyBundle` (`VaultifyCore/Keychain/VaultKeyBundle.swift`, versioned Codable JSON at `SharedConfig.keyBundleURL`, `.completeFileProtection`, established optional-field precedent): `envelopePublicKey: Data?` (plaintext — public) + `envelopePrivateKeySealed: Data?` (AES-GCM under the Vault Key). Erase/reset already wipes the bundle → no separate cleanup hook.

**Key lifecycle (RT-1 — corrected premise):** the Vault Key NEVER rotates on master-password change (`VaultSession+Recovery.swift:43-66` re-wraps the same key; `KeyHierarchy.swift:5-9`) — so the envelope key stays valid across `changeMasterPassword` AND `recover`. There is NO password-change hook. The envelope is invalidated only when the vault itself is destroyed (erase/new vault), which wipes the bundle.

**Provisioning + integrity (RT-2 — verify, don't trust existence):** on every interactive unlock (app `reload()` hook; extension post-`UnlockGate`):
1. Fields absent → generate keypair, seal private under Vault Key, persist both.
2. Fields present → **verify**: unseal the private key with the CURRENT Vault Key and check derived public == stored public. On failure (stale bundle from a restore, tampering): treat every `envelopeSealed` record as unopenable — delete those records + their published identities, record the affected relying parties for a **one-time user notice** (D7, validation S1), log a marker, regenerate the keypair. Never silently keep a pubkey we can't prove we hold the private half of.

**Data flow:** locked write → `envelopeSealed` column on `PasskeyRecord` (exactly one of `sealed`/`envelopeSealed` set); reads open BOTH forms transparently and NEVER write (RT-8 — no migration inside `matching`/assertion); **migration + dedupe run only in the unlock hooks**: open envelope records → re-seal under Vault Key → apply Phase 1 rp+userHandle replace-on-duplicate (newest wins) → prune replaced identities (RT-8: the silent path cannot dedupe — credentialIDs are random, record-id checks never match — so reconciliation happens here).

## Related Code Files
- Create: `VaultifyCore/Passkey/PasskeyEnvelope.swift` (HPKE seal/open + provisioning/verify over VaultKeyBundle fields; ≤200 LOC)
- Modify: `VaultifyCore/Keychain/VaultKeyBundle.swift` (two optional fields)
- Modify: `VaultifyCore/Passkey/PasskeyModels.swift` (`envelopeSealed: Data?` column)
- Modify: `VaultifyCore/Passkey/PasskeyVault.swift` (envelope-aware reads; `saveEnvelope`; unlock-time `migrateEnvelopeRecords(key:)`)
- Modify: `VaultifyAutoFill/CredentialProviderViewController.swift` (silent registration override, iOS 18)
- Modify: `VaultifyAutoFill/UnlockGate.swift` (or its success hook) + app unlock path (`VaultRepository.reload()`): provisioning/verify + migration call
- Modify: `Vaultify/Features/Settings/SettingsScreen.swift` (+ `SharedConfig` key for the toggle)
- Create: `VaultifyTests/PasskeyEnvelopeTests.swift`
- Modify: `Vaultify/Localizable.xcstrings`

## Implementation Steps
1. **PasskeyEnvelope**: `provisionOrVerify(vaultKey:) -> PublicKeyState` (absent→generate / valid / mismatch→cleanup+regenerate per Architecture); `publicKey() -> Data?` (locked-safe read from bundle); `seal(_ secret:, to publicKey:) throws -> Data` (version byte ‖ HPKE `encapsulatedKey` ‖ ciphertext); `open(_ data:, vaultKey:) throws -> PasskeySecret` (reject unknown version byte).
2. **Model**: `envelopeSealed: Data?` (lightweight migration). Invariant: exactly one of `sealed`/`envelopeSealed` meaningful; envelope payloads are UNTRUSTED input on open — strict decode, size cap, non-empty rp/user sanity checks before any promotion (RT-2 poisoning surface).
3. **PasskeyVault**: reads open both forms, never write (RT-8); `saveEnvelope` (single `context.save()`, no dedupe — documented); `migrateEnvelopeRecords(key:)` for unlock hooks: open → validate → re-seal → Phase 1 dedupe → return pruned/replaced identities for the identity store.
4. **Silent registration (iOS 18)**: override `performWithoutUserInteractionIfPossible(passkeyRegistration request: ASPasskeyCredentialRequest)` — the ObjC-style name in the earlier draft does not exist in Swift (`ASCredentialProviderViewController.h:226`, `NS_SWIFT_NAME`); parameter is already typed, no cast gate.
   - Gates: toggle ON + envelope public key present + ES256 ∈ `supportedAlgorithms` + no excluded-credential match (plaintext record ids). Any failure → `cancelRequest(.userInteractionRequired)` (system skips the upgrade; no fallback UI — report Q1).
   - Perform: `WebAuthn.register` → `PasskeyEnvelope.seal` → `saveEnvelope` → build identity via the shared factory (Phase 2) → **`await` `saveCredentialIdentities`** → `completeRegistrationRequest` (RT-10 teardown race).
   - Logging: marker-only ("silent-reg performed/skipped(reason-code)") — never the relying party (RT-15; policy at `CredentialProviderViewController.swift:9`).
5. **Settings toggle**: "Automatic passkey upgrades", default ON (user-confirmed; write-only crypto keeps reads zero-knowledge), stored in `SharedConfig.sharedDefaults`; explanatory footer EN+VI. Note app↔extension suite divergence guard: read via the shared App Group defaults only.
   <!-- Updated: Validation Session 1 - quarantine one-time notice (D7) -->
   **Quarantine notice (D7)**: persist the quarantined relying-party list (SharedConfig defaults key); the Passkeys screen (Phase 4) shows a dismissible one-time banner "Some automatically created passkeys were invalid and removed: {sites}" so the user can clean up at the RP. Strings EN+VI; clearing the banner clears the stored list.
6. **Tests**: envelope roundtrip; wrong-key open fails; unknown version byte rejected; provisioning verify matrix (absent/valid/mismatch→cleanup); migration re-seals + dedupes + reports identity prunes; gate function unit tests (toggle off / no pubkey / non-ES256 / excluded match); oversized/garbage envelope payload rejected.
7. `make check` (17.6 must compile with guards) + `make test`; manual on iOS 18+: Vaultify-filled password sign-in on an upgrade-enabled RP → passkey appears silently → opens + migrates + dedupes on next app unlock. **Time-boxed** (RT effort finding): Apple controls the trigger; if no upgrade is offered within the box, verify via the gate unit tests + a direct invocation harness and move on — "no upgrade offered" is non-bug.

## Success Criteria
- [x] Silent upgrade code path creates envelope-sealed passkeys while locked; iOS 18 RP-trigger smoke remains pre-TestFlight QA
- [x] Envelope records open transparently for assertions pre-migration; migrate + dedupe at next unlock; roundtrip/negative/version tests green
- [x] Provisioning verifies key-pair integrity every unlock; mismatch quarantines records + prunes identities + queues the one-time user notice (test-covered)
- [x] No password-change coupling anywhere; erase/new-vault invalidates via bundle wipe
- [x] Toggle OFF path gates silent upgrade; 17.6 build unaffected; extension logs reason markers only

## Validation Log
- 2026-07-02: post-review hardening applied; `make check` passed; full `VaultifyTests` passed (114 tests, 0 failures). Added `PasskeyEnvelopeTests` for HPKE roundtrip, wrong key, unknown version, oversize, provisioning verify/mismatch, migration/dedupe, quarantine notice, and envelope record-id mismatch quarantine.

## Risk Assessment
- **Public-key substitution residual**: attacker with App Group write access can swap the pubkey; unlock-time verify detects the swap after the fact and quarantines — future silent passkeys are re-keyed; already-exfiltrated envelope blobs from a compromised container are inherently out of scope (that attacker also holds the ciphertext vault + can replace the app). Stated honestly; no backup-exclusion (the bundle must survive legitimate restores).
- **Envelope-record poisoning**: records sealed to the real pubkey can be injected by a container-writing attacker; strict untrusted-input validation + visibility in the Phase 4 UI are the mitigations; residual documented.
- **Suite freeze**: ciphersuite + version byte fixed at first ship; changing later requires a migration path keyed on the version byte (documented in code).
- **Apple trigger non-determinism**: time-boxed manual verification with unit-tested gates as the real safety net.
