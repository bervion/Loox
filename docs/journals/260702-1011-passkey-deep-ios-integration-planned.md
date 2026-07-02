# 260702 — Passkey Deep iOS Integration: plan hardened through red team

**Session:** hard-mode planning (`/ck:plan`) → red team → validation. No code changed; deliverable = `plans/260702-1011-passkey-deep-ios-integration/` (7 phases, tasks hydrated).

## What happened

- Scouted current state: passkey core (WebAuthn ES256, ceremonies, `ProvidesPasskeys`) already ships but is invisible to iOS — no `ASPasskeyCredentialIdentity` published, no Face ID (bespoke master-password form predates `UnlockGate`), no management UI, `eraseAll()` misses `PasskeyRecord`, save failures complete registrations anyway (orphan credentials at RPs).
- 2 researchers: SDK-header verification (excludedCredentials/silent-reg/largeBlob = iOS 18; credential exchange = iOS 26 **swiftinterface**, Swift-only — ObjC-header greps miss it; PRF has no provider surface) + provider best practices (signCount 0, BE/BS semantics, excluded-credential handling).
- User decisions: EXPANSION scope; HPKE write-only envelope for iOS 18 silent upgrades; attach-to-login UI; BE=1|BS=1 for NEW credentials (legacy keep UP|UV via per-credential stored flags); auto-upgrade default ON; passkeys added to encrypted backup; quarantine → one-time notice; single release after Phase 5; cook stops before stretch phases 6–7.

## Key lesson — red team earned its cost (33 raw → 15 applied findings)

1. **All 4 reviewers independently killed the same Critical premise:** I planned envelope-key re-provisioning on master-password change, assuming the Vault Key rotates. It never does (`KeyHierarchy.swift`, `VaultSession+Recovery.swift:43-66` re-wraps the SAME key). Implemented as drafted it would have DESTROYED the only key able to open un-migrated silent passkeys. Grep the key hierarchy before designing key lifecycles.
2. **Fictional API symbols survive until header-grepped:** `HPKE.Ciphersuite.Curve25519_SHA256_AES_GCM_256` doesn't exist (pinned `Curve25519_SHA256_ChachaPoly` + version byte); the silent-registration override's Swift name is `performWithoutUserInteractionIfPossible(passkeyRegistration:)` (NS_SWIFT_NAME), not the ObjC selector spelling.
3. **Testability is a design input:** `PasskeyVault` constructing its own `VaultStore` over the real container made the planned in-memory tests impossible — an eraseAll test would have wiped the developer's actual simulator vault. Store injection became a Phase 1 requirement.
4. Other structural saves: silent-path "dedupe by record id" was a no-op (random credentialIDs) → reconcile at unlock migration; identity-store writes must be awaited before `completeRegistrationRequest` (process teardown drops fire-and-forget saves); reads must never write (no migration inside assertion paths); reuse `VaultKeyBundle` instead of a second key file; host-matching already existed twice in the codebase.
5. **Validation interview caught a blind spot all reviewers missed:** encrypted backup (`VaultBackup.swift`) exports items+folders only — restoring a backup would silently lose every passkey while we assert BS=1 ("backed up") to RPs. Now D6: optional passkeys array in the sealed payload.

## Impact

- Plan: 7 phases (~40h core + 2d stretch), Red Team Review + Validation Log embedded in `plan.md`, consistency sweeps = 0 contradictions. Tasks #1–#7 hydrated with dependency chain.
- Docs note: `docs/codebase-summary.md:78` still lists passkeys as "Deferred" — stale; fix lands with implementation.

## Unresolved questions

- ASCredentialIdentityStore removal-matching semantics (field-exact?) — empirical test scheduled in Phase 2.
- Apple's silent-upgrade trigger cadence is system-controlled — manual verification time-boxed, gates unit-tested instead.
