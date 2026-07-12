# Phase 06 — Testing + On-Device Memory QA

## Context Links

- Test target: `VaultifyTests/` (pattern: in-memory `VaultStore` + fixed Vault Key, no Argon2/keychain — `VaultifyTests/IdentityDataModelTests.swift:6`; run via `make test DEST='platform=iOS Simulator,id=<UDID>'`, Makefile `:91-95`)
- Runtime-verification convention: DEBUG file-based self-test, read back via `simctl get_app_container` (project CLAUDE.md "Verifying runtime behavior")
- Existing KDF test touching params: `VaultifyTests/PasskeyBackupRoundtripTests.swift:66`

## Overview

- **Priority**: P1 (gates release of phases 1-5)
- **Status**: pending
- Two tracks: (A) unit-test matrix in `VaultifyTests` (simulator, in-memory), (B) explicit ON-DEVICE memory QA of the appex Argon2 path — the one thing no simulator can validate (jetsam limits differ).

## Test Matrix (Track A — unit)

| Area | Test | Phase under test |
|---|---|---|
| Store robustness | `VaultReader.logins/totpItems` against `VaultStore(recoverable: true)` in-memory store: seeded records decrypt/filter/sort correctly with a fixed key | 1, 3 |
| Store robustness | store-failure shim (invalid store URL) ⇒ throws / caller gets error, no crash | 1 |
| SecureBytes | round-trip: `SecureBytes(bytes).bytes == bytes`; `secureZero` zeroes in place; `VaultReader.deriveVaultKey`-shaped wrap/unwrap with `SecureBytes` result unseals an `AESGCM` blob | 2 |
| Reader signatures | `logins(store:vaultKey:)` etc. compile against SecureBytes + injected store (implicit via above) | 2, 3 |
| KDF bundle decode | old-format JSON without `recoveryKdf` decodes; `recoveryKdf` round-trips | 4 |
| KDF migration | bundle wrapped `.standard` → migrate(password) ⇒ `kdf == .constrained`, fresh salt, same password unwraps, `wrappedByRecovery` byte-identical, `recoveryKdf == .standard` | 4 |
| KDF recovery-after-migrate | generate recovery wrap under `.standard`, migrate password path, then unwrap recovery using `recoveryKdf ?? kdf` succeeds | 4 (lockout regression guard) |
| KDF new vault | create-path bundle asserts `.constrained` | 4 |
| KDF idempotence | migrating a `.constrained` bundle is a no-op (no salt churn) | 4 |
| Argon2 KAT | existing KAT still green (`Argon2.swift:56` fixed params) | 4 |
| WebAuthn flags | silent registration authData flag byte `0x58`; interactive `0x5D` | 5 |
| WebAuthn flags | `assertionFlags(stored:)` matrix: nil→`0x05`, BE\|BS→`0x1D`, UP\|UV\|BE\|BS→`0x1D`, UP\|UV→`0x05` | 5 |
| Backup status | `PasskeyBackupStatus.evaluate` unchanged for silent-flag credentials (BE/BS still read) | 5 |

Notes: KDF migration tests use tiny Argon2 params where possible? NO — migration logic must be tested with the real profiles at least once (seconds-scale, acceptable); structure the migration function so params are injectable if suite time becomes a problem. Tests live in new files named by domain, e.g. `VaultifyTests/KdfMigrationTests.swift`, `VaultifyTests/WebAuthnFlagTests.swift`, `VaultifyTests/AutoFillReaderTests.swift` (PascalCase per Swift convention; no plan refs in names). Adding files ⇒ `tuist generate` before running.

## On-Device Memory QA (Track B — manual, REQUIRED before release)

Goal: answer open question 1 — does 64 MiB Argon2 jetsam the appex on min-spec hardware, and confirm the 32 MiB profile's headroom.

1. **Instrumentation (DEBUG only)**: add a temporary self-test hook in the appex password-unlock path that samples `task_vm_info.phys_footprint` before Argon2, at completion, and records peak, writing JSON to the App Group container (`SharedConfig` URL). Read back on-device via a hidden DEBUG row in the app (or Xcode container download). File-based per project convention — console capture is unreliable. Remove or `#if DEBUG`-fence before release; keep names generic (`MemoryFootprintProbe`), no plan refs.
2. **Device**: oldest hardware that runs iOS 17.3 available to us (A12-class if possible — smallest jetsam budgets). Record device model + OS in the QA note.
3. **Scenario 1 — legacy 64 MiB vault**: fresh install of the PRE-migration bundle state (or toggle Face ID off / cancel Face ID) → Safari password field → Vaultify AutoFill → master-password unlock. Repeat 5×, cold and warm. Record peak footprint and any `EXC_RESOURCE`/jetsam termination (check Settings → Privacy → Analytics crash logs for the appex process).
4. **Scenario 2 — migrated 32 MiB vault**: open app, password-unlock once (migration fires), verify bundle `kdf` via the DEBUG read-back, repeat the appex password unlock 5×. Expect peak roughly 32 MiB lower.
5. **Scenario 3 — Face ID path**: confirm footprint stays flat (no Argon2) — regression sanity.
6. **Conditional upgrade E2E (phase 5)**: iOS 18+ device, RP with conditional-create (webauthn.io), verify silent registration completes and the created passkey signs in afterwards.
7. Record results in `plans/reports/` QA note; the 64 MiB result decides whether a proactive migration nudge for Face-ID-only users is proposed to the user (do not auto-add).

## Related Code Files

Create: `VaultifyTests/KdfMigrationTests.swift`, `VaultifyTests/WebAuthnFlagTests.swift`, `VaultifyTests/AutoFillReaderTests.swift`; DEBUG probe file in `VaultifyAutoFill/` (e.g. `MemoryFootprintProbe.swift`, `#if DEBUG`).
Modify: none beyond hooks added in earlier phases.

## Todo

- [ ] Track A matrix implemented, `make test` green
- [ ] `tuist generate` after adding test files
- [ ] DEBUG footprint probe (fenced)
- [ ] Scenarios 1-3 executed on min-spec device, results filed
- [ ] Conditional-upgrade E2E on iOS 18+ device
- [ ] Probe removed/fenced for release; `make check` green

## Success Criteria

- All unit tests pass locally and on the CI runner (stable Xcode — no unguarded new APIs in tests).
- On-device numbers filed: peak appex footprint for 64 MiB vs 32 MiB unlock, jetsam yes/no.
- No failing test ignored/skipped to pass (per development rules).

## Risk Assessment

- Test-host trap: CI/simulator test host has no CloudKit container — keep all new tests off CloudKit code paths (known trap from prior work).
- Argon2 in tests: `.standard` derive takes seconds on CI — cap real-profile derivations to the 2-3 migration tests; everything else uses fixed keys.

## Security Considerations

- The footprint probe must log numbers only — no key material, no salts, no password-length hints.

## Next Steps

- Release train: phases 1-5 + this phase ship together (one `make release` cycle). Phase 7 is a separate, later decision.
