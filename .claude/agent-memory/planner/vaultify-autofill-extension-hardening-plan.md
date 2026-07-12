---
name: vaultify-autofill-extension-hardening-plan
description: Plan 260712-1500 — appex hardening: recoverable stores, SecureBytes key, one container/presentation, KdfParams.constrained + migration (recoveryKdf field!), silent-passkey UV=0
metadata:
  type: project
---

Plan dir: `plans/260712-1500-autofill-extension-hardening/` (7 phases, phase 7 deferred/product-gated).

Key verified facts + decisions (2026-07-12):
- **Latent recovery lockout bug**: `recover()` unwraps recovery envelope with CURRENT `bundle.kdf` (VaultSession+Recovery.swift:33), not generation-time params; `changeMasterPassword` already mutates kdf (:63). Invisible while everything is `.standard`; diverging KDF profiles WITHOUT a new optional `recoveryKdf` field on VaultKeyBundle = Emergency Kit lockout. Field must ship in same release as migration, backfilled before kdf mutation.
- KDF decision: `KdfParams.constrained` (32 MiB t=4 p=4, KdfParams.swift:18) for the key-bundle password wrap only. Backups/L2/SecretGuard stay `.standard` (never unwrapped in appex). Migration = opportunistic re-wrap in `VaultSession.unlock(password:)`, best-effort like biometric-key migration (VaultSession.swift:174). Params travel in bundle → rollout/rollback safe.
- S2 UV trap: registration flags are stored on the secret and REPLAYED as assertion flags (PasskeyCeremonyView.swift:260,172). Naive UV=0 silent fix breaks future assertions → decouple via `WebAuthn.assertionFlags(stored:) = UP|UV|(stored & BE|BS)`; all assertions run behind UnlockGate so UV=1 is truthful.
- `VaultReader`/`VaultWriter`/`VaultSpaceReader`/`SharedCredentialsCache` have NO app-target callers (grep-verified) → signatures change to SecureBytes/store-injection directly, no dual overloads. PasskeyVault/AESGCM already have SecureBytes overloads.
- Conditional-create spec: UP=0 UV=0 expected (web.dev, FIDO dev thread); `userVerificationPreference == .required` on silent path ⇒ skip to userInteractionRequired.

**How to apply:** when executing/reviewing this plan or any KDF/passkey-flags work in Vaultify, check these traps first.
