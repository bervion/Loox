# Phase 04 — Extension-Safe KDF Profile for New Vaults + Migration of Existing Vaults (P1)

## Context Links

- Audit §P1 + open question 1
- Profiles: `VaultifyCore/Crypto/KdfParams.swift:15` (`.standard` 64 MiB t=3 p=4), `:18` (`.constrained` 32 MiB t=4 p=4, currently unused)
- Bundle: `VaultifyCore/Keychain/VaultKeyBundle.swift` (atomic save `:46`, optional-field precedent `l2Kdf` `:25`)
- Creation/rewrap sites: `Vaultify/Security/VaultSession.swift:61` (create), `VaultSession+Join.swift:16` (join), `VaultSession+Recovery.swift:59` (`rewrapWithPassword` — serves `changeMasterPassword` `:43` and `recover` `:25`)
- Appex derive path: `VaultifyAutoFill/UnlockGate.swift:158` → `VaultReader.deriveVaultKey` (`VaultReader.swift:15`) → `KeyHierarchy.unwrap` (`KeyHierarchy.swift:36`)
- Opportunistic-migration precedent: `migrateBiometricKeyToSharedGroupIfNeeded` `VaultSession.swift:174-189`

## Overview

- **Priority**: P1 — headline item. Real-world crash risk: 64 MiB Argon2 inside the memory-capped appex on the master-password fallback path (no biometrics / Face ID cancel / biometrics invalidated).
- **Status**: done (implemented 2026-07-12; unit tests green via `make test`, on-device memory QA remains phase 6)

## Key Insights (verified)

- KDF params are fixed per-vault at creation and travel INSIDE the bundle (`VaultKeyBundle.swift:13`); the unlocker always uses `bundle.kdf` — so old and new profiles coexist with zero read-side changes. This is what makes rollout and rollback safe.
- **Latent lockout bug found (must fix first)**: `recover()` unwraps the recovery envelope with the CURRENT `bundle.kdf` (`VaultSession+Recovery.swift:33`), but that envelope was wrapped with the params at kit-GENERATION time (`:14`). Today both are `.standard`, so it is invisible. The moment `kdf` migrates to `.constrained`, every existing Emergency Kit stops unwrapping → recovery lockout. Same latent bug already exists in `changeMasterPassword` (mutates `kdf` at `:63` without touching `wrappedByRecovery`).
- We cannot re-wrap the recovery envelope during migration (we don't hold the paper recovery key). Therefore params for the recovery path must be RECORDED, not assumed.
- Face ID paths (app + appex) never run Argon2 (`BiometricKeyStore`, raw key) — unaffected.
- Argon2 KAT is self-contained with its own fixed params (`Argon2.swift:56`: m=65536 t=2 p=1) — unaffected by profile changes.
- Argon2 memory = `m_cost` total; `p` lanes divide it, they don't multiply it — 32 MiB means 32 MiB resident.

### Security analysis: 32 MiB vs 64 MiB

- OWASP 2023 Argon2id floor: m=19 MiB t=2 p=1 (second-choice config). `.constrained` (32 MiB, t=4, p=4) sits well above the floor; time×memory work factor is 128 MiB-iters vs standard's 192 — a ~33% reduction, partially recovered by t=4.
- Threat model: Argon2 here only rate-limits offline brute force of the master password against a stolen `wrappedByPassword` blob (the Vault Key itself is random 256-bit). The blob lives with complete file protection in the App Group (`VaultKeyBundle.swift:36-38`). 32 MiB remains firmly memory-hard against GPU/ASIC scaling.
- Decision: **use `KdfParams.constrained` as the vault-bundle password-wrap profile.** No new tuned profile (YAGNI); it exists, it's tested territory, and 32 MiB halves appex peak. Update its doc comment to say it is the vault-bundle default because the AutoFill extension must be able to run the derivation under its jetsam budget (explain why, no plan refs).

### Scope boundaries (unchanged at `.standard`)

- `VaultBackup.swift:117` — backups decrypt in the app only; params stored in the backup envelope.
- Level-2 (`VaultSession+Level2.swift:16,47`) — never unwrapped in the appex (`VaultReader` touches only `wrappedByPassword`).
- `SecretGuard.sealCustom` (`SecretGuard.swift:42`) — app-side.
- Escrow envelope (`VaultKeyEscrowService.swift:86-93`, `JoinVaultFlow.swift:386`) — carries its own kdf; decode path already honors it.

## Requirements

- New vaults (create/join) wrap the password path with `.constrained`.
- Existing vaults migrate opportunistically on the next successful IN-APP password unlock: re-wrap the same Vault Key under the same password with `.constrained` + fresh salt. One Argon2 re-derive, in the main app, under full memory budget.
- Migration must be: atomic (old bundle intact on any failure), non-blocking (unlock succeeds regardless), retried on later unlocks, silent (no UI).
- Recovery path must keep working before, during, and after migration → `recoveryKdf` field.

## Architecture

```
VaultKeyBundle (v1, JSON, App Group, atomic writes)
  kdf: KdfParams            ← migrates standard → constrained
  kdfSalt                   ← fresh on migration
  wrappedByPassword         ← re-wrapped on migration
  recoverySalt / wrappedByRecovery   ← UNTOUCHED by migration
  + recoveryKdf: KdfParams?  (NEW, optional → old JSON decodes fine)
       set at kit generation; backfilled to the pre-migration kdf during
       migration when a recovery wrap exists and the field is nil
recover():  params = bundle.recoveryKdf ?? bundle.kdf   (correct for all vintages)
```

Migration trigger — `VaultSession.unlock(password:)` (`VaultSession.swift:79-95`), after successful unwrap, before `adoptUnlocked`:

```
if bundle.kdf != .constrained {
    var updated = bundle
    if updated.wrappedByRecovery != nil && updated.recoveryKdf == nil {
        updated.recoveryKdf = updated.kdf          // record BEFORE changing kdf
    }
    fresh salt; wrappedByPassword = wrap(key, password, salt, .constrained)
    updated.kdf = .constrained; updated.kdfSalt = salt
    try updated.save()                              // atomic; failure → log, keep old bundle
}
```

Best-effort like the biometric-key migration (`VaultSession.swift:174`): a throw is caught, logged (non-sensitive), and retried next password unlock. `changeMasterPassword` / `recover` migrate implicitly once `rewrapWithPassword` (`VaultSession+Recovery.swift:59`) uses `.constrained` — and `rewrapWithPassword` must also backfill `recoveryKdf` before overwriting `kdf` (fixes the latent `changeMasterPassword` lockout for users who never hit the unlock-time migration).

## Related Code Files

Modify:
- `VaultifyCore/Crypto/KdfParams.swift` — doc comments only (why `.constrained` is the bundle default)
- `VaultifyCore/Keychain/VaultKeyBundle.swift` — add `recoveryKdf: KdfParams?`
- `Vaultify/Security/VaultSession.swift` — `createVault` `:61` → `.constrained`; migration hook in `unlock(password:)`
- `Vaultify/Security/VaultSession+Recovery.swift` — `rewrapWithPassword` `:59` → `.constrained` + `recoveryKdf` backfill; `recover()` `:33` → `recoveryKdf ?? kdf`; `generateRecoveryKit` `:14` → wrap with `bundle.kdf` as today AND set `recoveryKdf = bundle.kdf`
- `Vaultify/Security/VaultSession+Join.swift:16` → `.constrained`

Create: none (no new files → no `tuist generate` dependency, but run it anyway per workflow).

## Implementation Steps

1. Add `recoveryKdf` to `VaultKeyBundle` (+ round-trip decode test with old JSON missing the field).
2. `generateRecoveryKit`: set `recoveryKdf`; `recover()`: use `recoveryKdf ?? kdf`.
3. `rewrapWithPassword`: switch to `.constrained`, backfill `recoveryKdf` before mutating `kdf`.
4. `createVault` + `VaultSession+Join`: `.constrained`.
5. Migration hook in `unlock(password:)` per architecture above; reuse `Self.wrap` (`VaultSession.swift:221`) so Argon2 runs detached off-main (MainActor project default — keep crypto `nonisolated`, already is).
6. Unit tests (see phase 6 list; the KDF tests land WITH this phase, not after).
7. Compile check + `make test`.

## Todo

- [x] `recoveryKdf` field + backward-compat decode test
- [x] Recovery read/write paths honor `recoveryKdf` (incl. `VaultKeyEscrowService.pushRecoveryEnvelopeIfNeeded` — the PUSH side also sourced `bundle.kdf`, which would have mirrored wrong params to CloudKit post-migration; now `recoveryKdf ?? kdf`)
- [x] Creation/join/rewrap sites → `.constrained`
- [x] Opportunistic migration in `unlock(password:)` (pure step `VaultSession.kdfMigratedBundle` + best-effort save hook)
- [x] Unit tests green (`make test`, iPhone 16 Pro sim — 8/8 in `VaultifyTests/KdfMigrationTests.swift`, full suite passing)

## Success Criteria

- New vault → `bundle.kdf == .constrained` (test-asserted).
- Bundle built with `.standard` + password unlock ⇒ bundle becomes `.constrained`, same password unwraps, `wrappedByRecovery` bytes unchanged, `recoveryKdf == .standard`, recovery key still unwraps (test-asserted).
- Migration failure injection (unwritable URL) ⇒ unlock still succeeds, bundle unchanged.
- Appex master-password unlock peak footprint roughly halves on a migrated vault (phase 6 on-device measurement).

## Risk Assessment

| Risk | L×I | Mitigation |
|---|---|---|
| Recovery lockout via `bundle.kdf` divergence | High×Critical | `recoveryKdf` field ships in the SAME release, ordered before any kdf mutation; regression test recover-after-migrate |
| Migration write corrupts bundle | Low×Critical | `.atomic` write (existing `:46`); failure keeps old bundle; Vault Key never re-generated — only re-wrapped |
| Wrong-password path accidentally migrates | Low×High | hook runs only after successful unwrap (throw exits first) |
| Face-ID-only users never migrate | Medium×Medium | residual: their appex password-fallback stays 64 MiB. Accept for now; phase 6 measurement decides if a one-time password nudge is ever warranted (user decision, do not auto-add) |
| Old app version reads migrated bundle | Low×Low | unknown JSON key ignored by Codable; `kdf` honored generically — old versions still unlock a `.constrained` bundle |

## Rollback

Revert the constant at the creation/rewrap sites and delete the migration hook. Migrated bundles keep working forever (params ride in the bundle). `recoveryKdf` field stays — it is a correctness fix independent of the profile choice.

## Security Considerations

- Never log salts, params-with-context, or wrap material; migration log lines are boolean outcomes only.
- Fresh salt on every re-wrap (no salt reuse across profiles).
- The migration holds the plaintext key only within the existing `unlock` scope (`defer secureZero` already present `VaultSession.swift:93`).

## Next Steps

- Phase 6: on-device appex memory measurement (before/after), plus the full unit-test matrix.
