# Code Review: AutoFill Extension Hardening (`feat/autofill-extension-hardening`)

Reviewed diff `main...HEAD` (6 commits, 23 files, +491/-82). Compile check (`make check`, app + appex) PASSED. Read-only review; no code modified.

## Verdict up front

**The KDF migration is lockout-safe. No Critical findings.** All seven requested paths (a)-(g) traced below; every persisted state reachable on the current binary keeps both the password wrap and the recovery envelope openable with params that exactly match what each envelope was wrapped with. 1 High (functional passkey regression at an untouched call site), 2 Medium, 3 Low.

---

## 1. KDF migration lockout trace (paths a-g)

Ground truth verified by grep against `main`: `KdfParams.constrained` was **never** used for the key bundle or recovery wrap before this branch (only hits on main are unrelated `Capability.constrained`). So the `recoveryKdf ?? kdf` fallback claim — "pre-field bundles always shared the password-path params" — is exact, not assumed.

Core invariant (verified): **every writer that diverges `kdf` from the recovery wrap's params records `recoveryKdf` first, inside the same atomic save.**
- `kdfMigratedBundle` backfills at `VaultSession.swift:234-235` BEFORE `kdf = .constrained` at :243; single `save()` at :215.
- `rewrapWithPassword` backfills at `VaultSession+Recovery.swift:71-76` BEFORE `kdf = params` at :78; single `save()` at :80.
- No persisted state can exist where `kdf != recovery-wrap-params && recoveryKdf == nil` (on current binaries).

| Path | Result | Evidence |
|---|---|---|
| (a) New vault → kit → recover | SAFE | `createVault` kdf=.constrained (`VaultSession.swift:67`); `generateRecoveryKit` wraps with `bundle.kdf` and records the same value (`+Recovery.swift:14,20`); `recover` unwraps with `recoveryKdf ?? kdf` (`+Recovery.swift:40`) — always the recorded value. |
| (b) Legacy vault, recover BEFORE migration | SAFE | kdf=.standard, recoveryKdf=nil → fallback `kdf`=.standard = actual wrap params (identical to old behavior). The subsequent `rewrapWithPassword` backfills `.standard` before moving kdf to `.constrained`. |
| (c) Legacy vault, recover AFTER migration | SAFE | Migration backfilled recoveryKdf=.standard while `updated.kdf` still held the old value (assignment order at `VaultSession.swift:234-243`). Every vintage checked: kit regenerated pre-migration on new binary records `bundle.kdf` verbatim; kit regenerated post-migration wraps AND records `.constrained`. Wrap params and recorded params come from the same variable at the same moment in every writer — no vintage can desynchronize. |
| (d) Mid-migration crash / save failure | SAFE | Re-wrap is a pure step on a value copy; `VaultKeyBundle.save()` uses `.atomic` (`VaultKeyBundle.swift:55`) — temp-file + rename, reader sees old or new, never torn. Failure keeps the old bundle byte-identical and unlock proceeds (`migrateKdfProfileIfNeeded` catch at `VaultSession.swift:217-220`); covered by `testUnlockSucceedsWhenMigrationCannotPersist` (read-only container injection + byte-equality assert). Crash between save and `adoptUnlocked`: next unlock unwraps the migrated bundle with the same password — fine. |
| (e) Rollback to prior app version | SAFE for password; one narrow kit edge (Medium #2) | Old binary's `JSONDecoder` ignores the unknown `recoveryKdf` key; `kdf` values travel in JSON so the old binary unwraps the `.constrained` password wrap fine (params are data-driven, not code constants). See Medium #2 for the bundle-re-save edge. |
| (f) changeMasterPassword after migration | SAFE | Unwraps with current `bundle.kdf` (`+Recovery.swift:54-56`, always matches `wrappedByPassword`); `rewrapWithPassword` backfill is a no-op when recoveryKdf already set; recovery envelope untouched. |
| (g) CloudKit escrow push/join post-migration | SAFE | Push sends `recoveryKdf ?? kdf` (`VaultKeyEscrowService.swift:71`). Fingerprint dedup is keyed on the wrapped bytes (:72) — an unchanged envelope is never re-pushed, so the cloud record keeps the params it was originally (correctly) pushed with; migration alone cannot push wrong params because it never changes `wrappedByRecovery`. Kit regeneration changes the bytes → fresh push with matching recorded params. Join side: params travel with the CK record (`fetchRecoveryEnvelope`), unwrap uses them verbatim (`JoinVaultFlow.swift:396-400`), then `joinVault` re-wraps locally under `.constrained` AND records `recoveryKdf = params` (`+Join.swift:18,36`). Cross-device: bundles are device-local files; each device pushes its own envelope + its own recorded params — always self-consistent. |

Also verified:
- **Argon2 primitive untouched**: `git diff main...HEAD -- VaultifyCore/CArgon2 VaultifyCore/Crypto/` shows only `KdfParams.swift` doc comments (+10/-2, values unchanged). KAT vector test present (`KdfMigrationTests.testArgon2KnownAnswerVector`, canonical `0931…3cf7`).
- **Migration trigger placement**: called after the password is proven and before `adoptUnlocked` (`VaultSession.swift:104-105`). No partial-state window — the bundle write is atomic and independent of session state; a concurrent whole-bundle load-modify-save elsewhere would at worst revert the migration with a self-consistent snapshot (retried next password unlock), never mix salt/wrap.
- **Backup path independent**: `VaultBackup` records its own `kdf` inside the backup blob (`VaultBackup.swift:30,123,133`) — no coupling to bundle params.
- **`.standard` survivors are correct**: Level-2 (`+Level2.swift:16,47`), SecretGuard, backups — none unwrapped in the appex (grep: zero `level2|l2Kdf|wrappedL2SK` hits in `VaultifyAutoFill/`).
- **Memberwise-init nil default**: `recoveryKdf` is an optional `var` → implicit nil in the memberwise init used at `VaultSession.swift:74-78` and `+Join.swift:24-26`; compiles (make check green).

---

## 2. Findings

### Critical
None.

### High

**H1 — `ApprovalCeremonyService` emits UP=0/UV=0 assertions for silently-registered passkeys → RP rejects the sign-in.**
`Vaultify/Services/Sharing/ApprovalCeremonyService.swift:192` still signs with `flags: secret.flags ?? WebAuthn.legacyAssertionFlags`. Before this branch, every stored credential's flags included UP|UV, so this was harmless. Phase 5 introduces the first credentials whose stored flags are `BE|BS` only (`conditionalCredentialFlags = 0x18`). Failure scenario: owner's device silently registers a passkey (iOS 18 automatic upgrade) → owner shares that login with a passkey slot in askEachTime mode → recipient signs in → owner Face-IDs the approval → the assertion carries authenticatorData flags `0x18` (UP=0) → WebAuthn §7.2 verification step 16/17 requires the RP to reject any assertion with UP unset → sign-in fails with an opaque server error, after the owner explicitly approved. This is the exact bug class the two extension call sites were fixed for (`PasskeyCeremonyView.swift:175,266`); this third call site was missed. UP=1/UV=1 is genuinely true here (Face ID ran, `:173-174`).
Fix (one line): `flags: WebAuthn.assertionFlags(stored: secret.flags)`.
Note this is app-side, so the agent's "out of scope" note is wrong in effect: the regression only becomes reachable because of this branch's phase 5. Ship the fix in the same PR.

### Medium

**M1 — Rollback + old-binary bundle re-save can permanently strand a `.constrained`-wrapped Emergency Kit (narrow slice of path e).**
Old binaries drop the unknown `recoveryKdf` key on any bundle re-save (Codable round-trip). Scenario: kit generated on the NEW version (envelope wrapped `.constrained`, recoveryKdf=.constrained) → user rolls back → old `changeMasterPassword`/`rewrapWithPassword` sets `kdf = .standard` and saves, dropping recoveryKdf → recovery unwrap now derives with `.standard` against a `.constrained` envelope on the old binary AND after re-upgrading (`recoveryKdf ?? kdf` = .standard). Password path unaffected; regenerating the kit fully recovers. Unfixable retroactively (the vulnerable code is in already-shipped binaries). Recommendation: accept as documented residual; add a support-runbook note ("after an app downgrade+upgrade, regenerate the Emergency Kit"), and consider bumping `VaultKeyBundle.version` on migrated bundles so FUTURE binaries can refuse/flag foreign-vintage rewrites.

**M2 — Face-ID-only users never migrate; the extension's password fallback still runs 64 MiB Argon2.**
`migrateKdfProfileIfNeeded` only fires on in-app password unlock (`VaultSession.swift:104`); `unlockWithBiometrics` (:108) doesn't (can't — no password in hand). The affected cohort hits the extension password form precisely when biometrics fail (lockout, sweaty hands, biometry invalidation) — the worst moment for a jetsam kill, and biometry invalidation also clears the shared-group key, making password-in-appex the ONLY path. Known residual (plan open question 1, phase 6 measures headroom). If phase 6 shows real jetsam risk, consider an app-side nudge ("confirm your master password") for legacy-bundle + biometric-only users. No action required in this PR.

### Low

**L1 — `AESGCM`/`PasskeyVault` SecureBytes overloads copy the key into an un-zeroed transient `[UInt8]`.**
`AESGCM.swift:24-30` and `PasskeyVault.swift:33-35,44-46,…` do `key.withUnsafeBytes { … key: Array($0)) }` — the Array copy is released un-scrubbed. Pre-existing on main (not introduced here), but this branch routes every extension decrypt through it, so the mlock'd SecureBytes is partially theater: one plain-heap copy of the Vault Key per `AESGCM.open` call. Cheap improvement: `SymmetricKey(data: $0)` directly (UnsafeRawBufferPointer is ContiguousBytes; CryptoKit zeroizes SymmetricKey backing on release), or `var k = Array($0); defer { secureZero(&k) }` in the overloads.

**L2 — CoW makes `secureZero` ineffective in `JoinVaultFlow.adoptKey` (pre-existing, same hygiene class).**
`JoinVaultFlow.swift:66-69`: `var bytes = key; receivedKey = SecureBytes(bytes); secureZero(&bytes)` — `bytes` shares storage with the `key` parameter; `withUnsafeMutableBytes` inside `secureZero` forces a CoW copy and zeroes the COPY, leaving the original key buffer to be freed un-scrubbed. Contrast with the correct new pattern in `UnlockGate.swift:147-150` (`raw` uniquely owns the returned array → in-place zero works). Not touched by this branch; worth a follow-up sweep for `var x = <shared array>; secureZero(&x)`.

**L3 — `SharedCredentialsCache.save` staying `[UInt8]`: acceptable residual.**
Verified callers: `SharedItemsProjection.swift:91,251` (app-side), which already hold `[UInt8]` copies from the surrounding app-side flow. Changing `save` alone buys nothing; converging the projection's key handling to SecureBytes is app-side scope for a later pass. The asymmetry (load=SecureBytes, save=[UInt8]) is documented in the code comment (`SharedCredentialsCache.swift:100-102`). Note: plan.md:47 says all four types are "extension-only callers" — inaccurate for `save`; the implementation correctly deviated.

---

## 3. Other review areas (verified clean)

- **Recoverable store**: zero remaining `VaultStore()` (fatalError init) constructions in `VaultifyCore`/`VaultifyAutoFill`; the appex's only construction is `makeStore()` → `try VaultStore(recoverable: false)` (`CredentialProviderViewController.swift:227`). All 8 appex entry points guard it: password list, OTP list (x2), provide-credential (3 branches), save-password, passkey registration, passkey params list, silent registration (`skipSilentRegistration("request")` → `.userInteractionRequired`, correctly letting the interactive flow retry). The `onNoPasskey` re-host reuses the same store instance — no second container on the same SQLite file.
- **SecureBytes lifecycle**: `UnlockGate` holds one instance in `@State`, passed by reference down the tree; preset-key fallback shares the same instance across the re-host — ARC keeps it alive, `deinit` (memset_s+munlock) runs exactly once. No use-after-zero: all `defer { secureZero(&x) }` sites in the diff operate on uniquely-referenced arrays after the SecureBytes memcpy copy (checked `unlock`, `deriveVaultKey`, `generateRecoveryKit`, `UnlockGate`, `kdfMigratedBundle`'s detached-task capture is awaited before the caller's zero).
- **UV flags**: silent create emits `0x58` (AT|BE|BS, UP=0/UV=0) and bails to `.userInteractionRequired` on `userVerificationPreference == .required` (`+SilentPasskeys.swift:28-31`) — matches Apple's automatic-passkey-upgrade guidance; interactive registration keeps `0x5D`; both extension assertion sites use `assertionFlags(stored:)` → always UP|UV + copied BE/BS. Test coverage asserts all four byte values. Rollback on silent-save failure deletes both the record and the QuickType identity.
- **Concurrency**: `wrap`/`unwrap` run in `Task.detached` (真 off-main under `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor` — the known nonisolated-runs-on-caller trap is avoided); `UnlockGate.unlockWithMaster` detaches `deriveVaultKey` (`UnlockGate.swift:163-165`); `kdfMigratedBundle` is a nonisolated pure step.
- **Localization**: no new user-facing strings (all strings in the diff pre-exist on main — grep-verified for `UnlockGate`); no xcstrings changes needed.
- **No plan-artifact refs** in new code/comments (checked for finding codes P1/S1-S3/phase numbers — comments explain invariants, not origins).
- **Logging hygiene**: `kdfLog` emits boolean outcomes only; no salts/params/material.
- **Tests**: `KdfMigrationTests` covers codec back-compat, real-profile migration round-trip incl. Emergency-Kit-still-opens assert, no-op guard, session-level create/unlock-migrate, and the failed-persist path via read-only-container injection with byte-equality on the old bundle — exactly the right lockout guards. `WebAuthnTests` pins the flag bytes. `SharedCredentialsCacheTests` updated for the load signature.

## 4. Task completeness vs plan

Phases 1-5 implemented and match their phase files; phase-04 todo all checked (incl. the escrow push-side fix the audit flagged). Phase 6 (on-device memory QA) correctly still `pending` — that user gate plus H1 are the only things between this branch and merge. Phase 7 deferred as planned.

## Recommended actions (priority order)
1. **Fix H1** — `ApprovalCeremonyService.swift:192` → `WebAuthn.assertionFlags(stored: secret.flags)` (+ a WebAuthnTests-style assert if a testable seam exists).
2. Document M1 in the deployment/support notes ("regenerate Emergency Kit after downgrade+upgrade"); optionally bump bundle `version` on migration for future-binary detection.
3. (Follow-up, not blocking) L1: make the AESGCM SecureBytes overloads feed `SymmetricKey(data:)` straight from the borrowed buffer; sweep L2's CoW-zero pattern.
4. Proceed to phase 6 device QA (out of scope here).

## Unresolved questions
- None blocking. M1 mitigation (version bump vs. docs-only) is a product/support call.
