---
name: vaultify-kdf-securebytes-review-patterns
description: KDF param-recording invariant, CoW secureZero trap, assertionFlags call-site sweep — from autofill-hardening review 260712
metadata:
  type: project
---

Patterns from `feat/autofill-extension-hardening` review (260712). Related: [[vaultify-concurrency-audit-review-patterns]].

**KDF migration safety invariant (verified sound):** any writer diverging `VaultKeyBundle.kdf` from the recovery envelope's wrap params MUST record `recoveryKdf` first, inside the same atomic save. Readers use `recoveryKdf ?? kdf`. Escrow push dedup by SHA256(wrapped) is safe because migration never touches `wrappedByRecovery`. When reviewing future profile changes, re-trace: create/join/recover/changeMasterPassword/escrow-push/rollback.
**Why:** params must be RECORDED per envelope, never assumed from the password path — divergence without recording = paper-kit lockout.
**How to apply:** grep all `KdfParams` writers + `bundle.save()` sites; check backfill-before-divergence ordering and old-binary Codable key-drop on rollback (unknown JSON keys are DROPPED on old-binary re-save → narrow rollback kit-lockout, accepted residual M1).

**CoW secureZero trap:** `var bytes = param; SecureBytes(bytes); secureZero(&bytes)` zeroes a CoW COPY when the array is shared — original buffer freed un-scrubbed (JoinVaultFlow.adoptKey). Only uniquely-owned arrays zero in place (fresh return values, `.bytes` copies). Also: SecureBytes overloads doing `Array($0)` inside withUnsafeBytes (AESGCM, PasskeyVault) leak an un-zeroed heap copy per call — prefer `SymmetricKey(data: $0)` direct.

**assertionFlags sweep rule:** once any stored credential can have flags WITHOUT UP/UV (conditional/silent registration, `conditionalCredentialFlags = BE|BS`), EVERY `WebAuthn.assertion(...)` call site must use `assertionFlags(stored:)`, never `secret.flags ?? legacyAssertionFlags` — RPs reject UP=0 assertions. Found missed site: ApprovalCeremonyService.swift:192 (H1).
