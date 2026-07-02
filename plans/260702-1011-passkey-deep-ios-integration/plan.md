---
title: "Passkey Deep iOS Integration"
description: "Complete Vaultify's passkey provider: QuickType identities, Face ID, ceremony correctness, in-app management, iOS 18 silent upgrades via envelope key, largeBlob, credential exchange"
status: in-progress
priority: P1
branch: "main"
tags: [passkey, webauthn, autofill, ios]
blockedBy: []
blocks: []
created: "2026-07-02T03:24:46.885Z"
createdBy: "ck:plan"
source: skill
---

# Passkey Deep iOS Integration

## Overview

Passkey core already ships (ES256 WebAuthn primitives, registration + assertion ceremonies in the AutoFill extension, `ProvidesPasskeys` capability). This plan completes it into a first-class iOS passkey provider: passkeys surface on QuickType, unlock with Face ID, ceremonies follow WebAuthn L3 + Apple guidance, users manage passkeys inside the app (attached to matching login items), and iOS 18 automatic passkey upgrades work silently through a write-only envelope key — without weakening the zero-knowledge read model.

Scope mode: **EXPANSION** (user-confirmed 2026-07-02). Design decisions D1–D3 and findings F1–F15: `plans/reports/scout-260702-1011-passkey-current-state-report.md`.

## Phases

| Phase | Name | Priority | Effort | Depends on | Status |
|-------|------|----------|--------|------------|--------|
| 1 | [Core WebAuthn Correctness & Data Model](./phase-01-core-webauthn-correctness-data-model.md) | P1 | 6h | — | Complete |
| 2 | [Extension Face ID & Ceremony Hardening](./phase-02-extension-face-id-ceremony-hardening.md) | P1 | 6h | 1 | Complete |
| 3 | [QuickType Passkey Identities](./phase-03-quicktype-passkey-identities.md) | P1 | 4h | 1, 2 | Complete |
| 4 | [App UI Passkey Management](./phase-04-app-ui-passkey-management.md) | P2 | 10h | 3 | Complete |
| 5 | [Envelope Key & iOS 18 Auto-Upgrades](./phase-05-envelope-key-ios-18-auto-upgrades.md) | P2 | 8h | 1, 3 | Complete |
| 6 | [largeBlob & AAGUID Branding](./phase-06-largeblob-aaguid-branding.md) — *stretch* | P3 | 4h | 2 | Pending |
| 7 | [Credential Exchange Import-Export](./phase-07-credential-exchange-import-export.md) — *stretch* | P3 | 2d | 1, 4 | Pending |

Execution order: 1 → 2 → 3 → 4 (core, sequential). 5 after 3. 6 and 7 are stretch — shippable release after phase 5; 6/7 can slip to a follow-up.

Ship cadence (validation session 1): **one TestFlight release after Phase 5** (`make release`) — no intermediate betas. Cook runs 1→5 then **STOPS for user review** before touching stretch phases 6–7.

## Key decisions

- **D1 EXPANSION scope** — all findings F1–F14 + stretch phases 6–7. PRF excluded WITH evidence (no provider-side SDK surface). CloudKit sync of `PasskeyRecord` deferred (iCloud compile-gated OFF; documented as F15 follow-up).
- **D2 Envelope key** — HPKE write-only public key lets the extension create passkeys with the vault locked (iOS 18 silent upgrades). Reads still require unlock. No biometric prompt in the silent path. Pinned: `HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly` + 1-byte format version; keys live as optional fields in the existing `VaultKeyBundle`; NO password-change coupling (Vault Key never rotates on password change — `KeyHierarchy.swift`); provisioning VERIFIES the keypair every unlock. (Red-team session 2026-07-02.)
- **D3 Attach-to-login UI** — passkeys display inside matching login items (`VaultItem.matchesRelyingParty`, reusing the codebase's existing suffix-match convention) + a standalone Passkeys screen (Settings) for the full list & orphans.
- **D4 Flags (user-confirmed)** — NEW credentials register `UP|UV|BE|BS(|AT)` (BE=1|BS=1 constant, ecosystem parity); flags stored per-credential in `PasskeySecret.flags`; LEGACY credentials keep asserting `UP|UV` (BE is immutable per credential — never flip existing ones). signCount stays 0. UV always set (unlock is always interactive).
- **D5 Auto-upgrade default ON (user-confirmed)** — "Automatic passkey upgrades" toggle ships enabled; write-only envelope keeps the read model zero-knowledge.
- **D6 Passkeys in encrypted backup (user-confirmed, validation S1)** — `VaultBackup.EncryptedBackup` sealed payload gains an optional passkeys array (old backups keep decoding); export includes passkeys, import restores + dedupes + refreshes identities. CSV export explicitly NEVER includes passkeys. Makes BS=1 honest.
- **D7 Quarantine notice (user-confirmed, validation S1)** — when envelope verification quarantines unopenable silent passkeys, the app shows a ONE-TIME notice (affected sites listed) so the user can clean up at the RP; not log-only.
- **API guards** — target iOS 17.6: `excludedCredentials`/`matchedExcludedCredential`/silent registration (`performWithoutUserInteractionIfPossible(passkeyRegistration:)`)/largeBlob = `#available(iOS 18, *)`; credential exchange = `#available(iOS 26, *)`.

## Validation gates (every phase)

- `tuist generate` after adding files; `make check` compiles app + extension with zero errors.
- `make test` green (new WebAuthn/envelope/matching tests included).
- Every new user-facing string in `Vaultify/Localizable.xcstrings` with EN **and** VI values.
- No unguarded API above iOS 17.6 (stable-Xcode CI must stay green).

## Red Team Review

### Session — 2026-07-02
**Reviewers:** Security Adversary, Failure Mode Analyst, Assumption Destroyer, Scope & Complexity Critic (4× code-reviewer, Full verification tier). Raw reports: `./reports/from-code-reviewer-to-planner-red-team-*-plan-review-report.md`.
**Findings:** 33 raw → 15 after dedupe (2 Critical, 7 High, 6 Medium). **All 15 accepted** (user decision 2026-07-02); two sub-suggestions rejected: backup-exclusion of the key bundle (breaks legitimate restore; superseded by verify-on-unlock) and a plaintext dedupe-key column (metadata leak; unlock-migration reconciliation suffices).

| # | Finding | Severity | Disposition | Applied To |
|---|---------|----------|-------------|------------|
| RT-1 | Password-change envelope rotation premise false (Vault Key never rotates) — drop hook, erase-only invalidation | Critical | Accept | Phase 5 |
| RT-2 | Envelope lifecycle trust: stale envelope survives erase; provisioning must VERIFY keypair, quarantine mismatch, validate records as untrusted input | Critical | Accept | Phase 5 |
| RT-3 | `PasskeyVault` needs store injection; throwing init everywhere; per-call `ModelContainer` churn + fatalError reads eliminated; tests become possible | High | Accept | Phases 1, 2, 3 |
| RT-4 | Crypto/API pinning: cited HPKE ciphersuite doesn't exist → pin `Curve25519_SHA256_ChachaPoly` + version byte; Swift override is `performWithoutUserInteractionIfPossible(passkeyRegistration:)` | High | Accept | Phase 5 |
| RT-5 | Store envelope keys as optional `VaultKeyBundle` fields — no new key file, erase-wipe falls out free | High | Accept | Phase 5 |
| RT-6 | Dedupe-replace needs single-save atomicity + induced-failure test; phantom-credential residual documented | High | Accept | Phase 1 |
| RT-7 | Identity refresh race: fire-and-forget Tasks can resurrect deleted passkeys — serialize with generation stamps | High | Accept | Phase 3 |
| RT-8 | Silent-path "dedupe by record id" is a no-op (random credentialIDs); reads must never write — ALL migration + rp+userHandle reconciliation at unlock hooks only | High | Accept | Phase 5 |
| RT-9 | Plan-text corrections: Phase 1 omitted its extension caller (`CredentialProviderViewController.swift:169,188`); "Add all/matching" → reshape (they exist); xcstrings path is `Vaultify/Localizable.xcstrings` (was wrong in 4 phases); Phase 7 evidence cite fixed | High | Accept | Phases 1, 2, 4, 5, 7 |
| RT-10 | Identity write correctness: shared identity factory (VaultifyCore); `await` saves/removals before `completeRegistrationRequest`; `save` returns replaced SECRETS (not bare IDs) so removal identities are field-accurate | Medium | Accept | Phases 1, 2, 5 |
| RT-11 | App-side cache is metadata-only `PasskeyInfo` (no `privateKeyRaw` in the `@Observable` graph); `SecureBytes` overloads instead of raw-array bridging | Medium | Accept | Phases 1, 3 |
| RT-12 | Host-matching already exists twice (`VaultReader.swift:87-94`, `TwoFactorCatalog.swift:74`) — extend `VaultItem`, no new matcher module | Medium | Accept | Phase 4 |
| RT-13 | Phase-boundary rework: identity append folded into Phase 2; pre-unlock gates live in the VC, post-unlock logic in the ceremony view | Medium | Accept | Phases 2, 3 |
| RT-14 | Per-credential `flags` stored in `PasskeySecret`; legacy credentials keep UP|UV (BE immutable); BS value surfaced → user chose BE=1|BS=1 for new | Medium | Accept | Phase 1 (+D4) |
| RT-15 | Silent-path logging: marker-only, never relying-party at `.public` (extension logging policy) | Medium | Accept | Phase 5 |

### Whole-Plan Consistency Sweep
- Files reread/swept: `plan.md` + `phase-01..07` (grep for rejected terms, fictional APIs, wrong paths, password-change coupling)
- Decision deltas checked: 15 (RT-1..RT-15) + user decisions D4 (BE=1|BS=1 new / legacy UP|UV) and D5 (auto-upgrade default ON)
- Reconciled stale references: 3 (RT-8 mislabel in phase-05; phase-07 evidence citation; phase-07 xcstrings path) — phases 1–5 were fully rewritten with all deltas applied
- Unresolved contradictions: **0**

## Validation Log

### Session 1 — 2026-07-02
**Trigger:** post-red-team validation interview (`/ck:plan validate`, mode=prompt). Verification pass skipped per guard — Red Team Review already carries Full-tier verification evidence; no `[UNVERIFIED]` tags.
**Questions asked:** 4

#### Questions & Answers
1. **[Scope]** Encrypted backup currently ships items+folders only (`ExportView.swift:90`, `VaultBackup.swift:30,98`) — passkeys lost on restore, contradicting BS=1. Handle how?
   - Options: Add passkeys to encrypted backup (Recommended) | Defer with risk note | Flip BS=0 + defer
   - **Answer:** Add passkeys to encrypted backup
   - **Rationale:** restores keep sign-in credentials; keeps the D4 BS=1 claim honest. CSV stays passkey-free.
2. **[Risks/UX]** Envelope-integrity quarantine (restore mismatch/tamper) — surface to user?
   - Options: One-time in-app notice (Recommended) | Log-only
   - **Answer:** One-time in-app notice listing affected sites
   - **Rationale:** RP-side credentials survive quarantine; without a notice, later sign-in failures are undebuggable for the user.
3. **[Scope]** TestFlight cadence?
   - Options: Beta after Phase 3 + release after Phase 5 (Recommended) | Single release after Phase 5 | Beta per phase
   - **Answer:** **Single release after Phase 5** (user overrode the recommendation)
   - **Rationale:** one CI/CD round; on-device verification happens locally before the release tag.
4. **[Scope]** Stretch phases 6–7 during cook?
   - Options: Stop for review after Phase 5 (Recommended) | Run 1→7 straight
   - **Answer:** Stop for review after Phase 5
   - **Rationale:** 6–7 remain user-gated; cook checkpoint after the shippable core.

#### Confirmed Decisions
- Backup coverage: extend `EncryptedBackup` sealed payload (optional field) — new D6.
- Quarantine UX: one-time notice — new D7.
- Ship: single `make release` after Phase 5; cook checkpoint before phases 6–7.

#### Impact on Phases
- Phase 4: +backup/restore steps & files (`VaultBackup.swift`, Export/Import views, roundtrip tests); effort 8h → 10h.
- Phase 5: quarantine records affected relying parties → one-time notice surfaced in the Passkeys screen; strings EN+VI.

### Whole-Plan Consistency Sweep (Session 1)
- Files reread/swept: `plan.md` + `phase-01..07` after propagation
- Decision deltas checked: 4 (D6 backup, D7 notice, single-release cadence, stretch checkpoint)
- Reconciled stale references: 0 stale claims found (backup/notice were previously unmentioned, not contradicted)
- Unresolved contradictions: **0**

### Session 2 — 2026-07-02
**Trigger:** chunk 2 implementation (phases 4-5).
**Completed:** in-app Passkeys management, login-detail passkey attachment, encrypted backup passkey roundtrip, HPKE envelope key, iOS 18 silent registration hook, unlock-time migration/dedupe/quarantine notice.
**Validation:** post-review hardening applied; `make check` passed; full `VaultifyTests` passed (114 tests, 0 failures).
**Manual pending before TestFlight:** on-device QuickType delete disappearance and iOS 18 RP-triggered automatic upgrade smoke test.

## References

- Scout: `plans/reports/scout-260702-1011-passkey-current-state-report.md`
- SDK availability: `plans/reports/researcher-260702-1018-passkey-sdk-availability-report.md`
- Best practices: `plans/reports/researcher-260702-1011-passkey-provider-best-practices-report.md`
- Red-team reports: `./reports/` (4 reviewer artifacts)

## NOT in scope

- PRF extension (no provider-side API in SDK — verified).
- CloudKit sync of passkeys (iCloud gated off; enabling sync later must add `PasskeyRecord` — documented follow-up).
- Custom shell/tab UI changes; associated domains (not needed for credential providers).
