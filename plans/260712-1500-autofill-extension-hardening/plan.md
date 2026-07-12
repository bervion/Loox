---
title: "AutoFill Extension Hardening"
description: "Security, robustness and memory hardening of the AutoFill Credential Provider extension: recoverable stores, SecureBytes key hygiene, single-container presentations, extension-safe KDF profile + migration, silent-passkey UV fix"
status: pending
priority: P1
effort: 18h
branch: main
tags: [autofill, security, crypto, kdf, passkeys, performance]
created: 2026-07-12
---

# AutoFill Extension Hardening

Source audit: `plans/reports/from-extension-audit-260712-1453-autofill-extension-security-perf-report.md` (all findings re-verified against the codebase 2026-07-12).

## Phases

| # | Phase | Finding | Effort | Status |
|---|-------|---------|--------|--------|
| 1 | [Recoverable store on read paths](phase-01-recoverable-store-read-paths.md) | P3 | 1h | done |
| 2 | [Vault Key SecureBytes + privacy redaction](phase-02-vault-key-secure-bytes-and-privacy-redaction.md) | S1, S3 | 3h | done |
| 3 | [Single store per presentation](phase-03-single-store-per-presentation.md) | P2 | 2h | done |
| 4 | [Extension-safe KDF profile + vault migration](phase-04-extension-safe-kdf-profile-and-migration.md) | P1 | 6h | done |
| 5 | [Silent passkey UV flag correction](phase-05-silent-passkey-uv-flag-correction.md) | S2 | 2h | done |
| 6 | [Testing + on-device memory QA](phase-06-testing-and-on-device-memory-qa.md) | all | 4h | pending |
| 7 | [Optional: text-to-insert + PRF (iOS 18)](phase-07-optional-api-growth-text-to-insert-prf.md) | API growth | 8h | deferred |

## Dependency graph

```
Phase 1 (P3) ──► Phase 3 (P2)   [same functions: store acquisition]
Phase 2 (S1+S3) ─► Phase 3      [same signatures: key type then store param]
Phase 4 (KDF) — independent of 1-3 (app-side files), can run in parallel with 1-3
Phase 5 (S2) — independent (WebAuthn + silent path only)
Phase 6 — after 1-5
Phase 7 — separate release, gated on product decision (open question 3)
```

Phases 1→2→3 are sequential (overlapping files: `VaultReader.swift`, extension views). Phase 4 owns `Vaultify/Security/*` + `VaultifyCore/Keychain/VaultKeyBundle.swift` + `VaultifyCore/Crypto/KdfParams.swift` — disjoint from 1-3, parallel-safe. Phase 5 owns `VaultifyCore/Passkey/WebAuthn.swift` + silent-passkey file — parallel-safe with 1-4 except `PasskeyCeremonyView.swift` (also touched by phase 2; run 5 after 2 or rebase).

## Key decisions

- **KDF profile for new vaults**: `KdfParams.constrained` (32 MiB, t=4, p=4 — already defined, `VaultifyCore/Crypto/KdfParams.swift:18`). Applies only to the key-bundle password wrap; backups/Level-2/SecretGuard stay `.standard` (never unwrapped in the appex).
- **Migration**: opportunistic re-wrap on successful in-app password unlock (mirrors the `migrateBiometricKeyToSharedGroupIfNeeded` pattern, `VaultSession.swift:174`). Best-effort, atomic, never blocks unlock.
- **Critical prerequisite**: new `recoveryKdf` field on `VaultKeyBundle` — `recover()` currently unwraps the recovery envelope with the *current* `bundle.kdf` (`VaultSession+Recovery.swift:33`), not the generation-time params. Diverging profiles without this field = recovery-key lockout.
- **UV bit**: silent conditional registration must emit UP=0 UV=0 (WebAuthn conditional-create expectation); assertion flags decoupled from stored registration flags so interactive assertions keep UV=1.
- **Key type**: `SecureBytes` (class, mlock+memset_s) threaded from `UnlockGate` down; `VaultReader`/`VaultWriter`/`VaultSpaceReader`/`SharedCredentialsCache` are extension-only callers (verified by grep) → signatures change directly, no dual overloads.

## Rollback

Each phase is independently revertible (single PR per phase or stacked commits). Phase 4 rollback: revert creation-site constants — already-migrated bundles keep unlocking because KDF params travel inside the bundle. No schema/data migration anywhere.

## Open questions (from audit, carried)

1. Jetsam headroom of 64 MiB Argon2 on min-spec device — phase 6 measures it; drives whether a proactive migration nudge is ever needed for Face-ID-only users (residual risk, phase 4).
2. Text-to-insert: desired product capability or non-goal? Blocks phase 7.
3. PRF extension priority vs. other roadmap items. Blocks phase 7.
