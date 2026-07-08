---
title: "Loox Quick View — one-shot browser handoff (Open on Computer)"
description: "Ephemeral field-scoped E2E handoff: iPhone approves exact fields → browser tab's ephemeral key decrypts once. Recipient-keyed dual of Loox Link."
status: pending
priority: P1
branch: "main"
tags: [security, sharing, loox, quick-view]
blockedBy: []
blocks: []
created: "2026-07-08T03:39:49.588Z"
createdBy: "ck:plan"
source: skill
---

# Loox Quick View — one-shot browser handoff (Open on Computer)

## Overview

Browser at `looxpassword.com/open` mints ephemeral P-256 enc+sig keys → shows QR/code/SAS.
App scans → user picks exact fields on approval sheet → Face ID → re-read → seal to the
browser's key (ECDH P-256 → HKDF-SHA256 → AES-256-GCM, KDF transcript per INV-QV-18) →
upload atomically claims the session (first valid approval wins, INV-QV-16) → browser PoP →
decrypt → render memory-only, one shot. Server is a blind mailbox; no read API over the vault.

**Refs (authoritative — owner-approved 260708, decision logs supersede open questions):**
- App proposal: `plans/reports/proposal-260708-1016-loox-quick-view-app-team.md`
- Backend companion: `plans/reports/backend-proposal-260708-1016-loox-quick-view-session-mailbox.md`

**Locked decisions (owner):** suite P-256 ECDH+HKDF+AES-GCM (no ChaCha/HPKE — WebCrypto-native);
bind ADVISORY only, claim at upload; SAS derived both ends, mismatch = hard block (INV-QV-19);
upload assertion binds `SHA256(canonicalUploadBody)`; resolve-by-code = POST body; defaults
username ON / website ON / password OFF (+visibility warning) / TOTP OFF / notes OFF; TOTP =
virtual field carrying only a boundary-aware CURRENT code (INV-QV-17); history row minimal
(`item_id + timestamp + result`); guard2-only item → entry disabled + explainer; TTLs
180s/90s/5min/2min; `/open` + API canonical domain only (INV-QV-14).

**Reuse map (verified in codebase):** `LooxLinkEnvelope` payload schema (app-only, `Vaultify/Features/Sharing/LooxLink/`) ·
`LooxLinkCanonical`/`LooxLinkAttestation` transcript+assert pattern · `CapabilityManifest`/`DomainRegistryDocument`
P256 signed-doc verify pattern (same `cap-2026-01` trust root, distinct MAGIC) · **boundary-aware
TOTP primitives `TOTPWindow` + `TOTPIssuancePolicy` (`VaultifyCore/Sharing/ApprovalModels.swift`)
+ `TOTPGenerator`** (NOT `ApprovalCeremonyService` — that class is `@MainActor @Observable`
CKShare-bound, takes `ApprovalCoordinator.PendingOwnerRequest`, and seals with
`Curve25519_SHA256_ChachaPoly` `ApprovalCrypto.swift:92` = the wrong suite; do not reuse it) ·
`QRScannerView` (generic `onFound:(String)->Void`) · `CapabilityStore`/health-probe wiring.

**Placement (owner ADR parity):** Quick View is app-only, mirroring LooxLink (`LooxLinkEnvelope/
Crypto/Canonical` all live under `Features/Sharing/`, NOT VaultifyCore, to keep DeviceCheck out of
the appex). The Quick View kernel therefore lives in `Vaultify/Features/Sharing/QuickView/`, not
VaultifyCore — VaultifyCore cannot import app-only `LooxLinkEnvelope`. The kernel still *reuses*
VaultifyCore primitives (`CanonicalWriter`, P256 verify helpers) without living there.

## Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | [Contract Freeze Parity Sign-off (QV-A0)](./phase-01-contract-freeze-parity-sign-off-qv-a0.md) | Pending |
| 2 | [Kernel: Envelope Verifier + SAS + Sealer (QV-A1)](./phase-02-kernel-envelope-verifier-sas-sealer-qv-a1.md) | Pending |
| 3 | [Session Client + App Attest + Capability (QV-A2)](./phase-03-session-client-app-attest-capability-qv-a2.md) | Pending |
| 4 | [Approval UX + Scanner + Enter Code (QV-A3)](./phase-04-approval-ux-scanner-enter-code-qv-a3.md) | Pending |
| 5 | [Adversarial QA Matrix (QV-A4)](./phase-05-adversarial-qa-matrix-qv-a4.md) | Pending |
| 6 | [Device & Browser QA on Staging (QV-A5)](./phase-06-device-browser-qa-on-staging-qv-a5.md) | Pending |

## Gates & Dependencies

- **GATE QV-1 (external, backend repo):** frozen artifacts + vectors, delivered by BE generator
  importing production encoders. Post-validation the contract is split (DEC-QV-QR-01):
  `LOOX-QUICK-VIEW-SESSION-V1` (freeze early), `-QR-V1` (post-benchmark carrier), `-CODE-V1`
  (resolve-only), `-PAYLOAD-V1` (+ AEAD-bound TOTP `valid_until`), `LOOX-QV-FIELD-MANIFEST-V1`
  (structural), `-POP-V1`, `LOOX-APP-ATTEST-QUICK-VIEW-V1`, SAS spec, and the capability-manifest
  `quick_view.exposure` state. Phase 1 closes this gate; Phases 2–4 are code-blocked on it (kernel
  can start against SESSION/PAYLOAD/manifest once frozen, without waiting on the QR benchmark). No
  local plan blocks this plan.
- Phase 5 needs staging worker + `/open` page live (BE rollout step 2).
- Phase 6 manual, needs assertion shadow ladder on staging.

## Implementation Log

### 2026-07-08 — Increments A+B built ahead of GATE QV-1 (owner-authorized parallel build)

**Status:** app-side code COMPLETE + compiling + unit-tested; byte-parity vs BE vectors PENDING (GATE
QV-1 open). All wire byte-layouts marked `// PENDING GATE QV-1` — swap in BE golden vectors when
delivered. Verified independently (not just subagent report): `tuist generate` + workspace
`xcodebuild` **BUILD SUCCEEDED** (app + AutoFill extension); full `VaultifyTests` suite **TEST
SUCCEEDED**, 0 failures (39 new QuickView tests: 20 kernel + 7 client + 12 flow).

**Kernel + wiring (Phase 2 + Phase 3 capability slice)** — `Vaultify/Features/Sharing/QuickView/`:
QuickViewFieldKind, QuickViewApprovedField, QuickViewFieldManifest (+`QuickViewWire` single dialest),
QuickViewSAS (7772-word list), QuickViewSessionEnvelope(+Verifier, mandatory key-hash substitution
guard), QuickViewPayloadSealer (ECDH→HKDF→AES-GCM, INV-QV-18 transcript), QuickViewConfig,
QuickViewExposure(+Resolver, fail-closed public+shadow), QuickViewHistoryStore. Modified:
`CapabilityID.quickView`, `CapabilityHealthProbe` quick-view service-state URL.

**Client + UX (Phase 3 net + Phase 4)**: QuickViewCanonical, QuickViewAttestation (shadow ladder),
QuickViewAPIClient (resolve POST-body / advisory bind / upload attest-trio / generic-failure map),
QuickViewHumanCode, QuickViewPayloadComposer (LooxLinkEnvelope UNCHANGED, virtual TOTP appended +
AEAD-bound valid_until + structural manifest), QuickViewApprovalFlowModel, + 5 UX sheets. Modified
ItemDetailScreen (entry + guard2/exposure gating), AppEnvironment, Localizable.xcstrings (EN+VI, all
new strings). QRScannerView reused.

**Code review (0 Critical, 1 High, 2 Med, 2 Low) — security findings fixed:**
- (High) virtual-TOTP now explicitly excludes guard2 (`isExtraProtected`) in composer + toggle, not
  by incidental SecretGuard-tag decode failure. New test `testComposerExcludesGuard2TOTP`.
- (Med) `QuickViewSessionEnvelopeVerifier.verify` key-hash substitution guard made mandatory
  (non-optional params) — no silent skip. Call sites + tests updated.
- (Med) 2FA toggle hidden when the TOTP field is guard2.
- (Low, deferred) `QuickViewPayloadComposer` MainActor-vs-nonisolated consistency; dead server-code
  errorDescription — noted, not load-bearing.
Review verified correct: INV-QV-18/24/25/17/26/19, minimal history row, re-read after Face ID,
advisory-bind never blocks, no plaintext/SAS/session_id logged, EN+VI complete.

**BLOCKED on external (cannot run now):** GATE QV-1 byte-parity (BE vectors), Phase 5 staging drills
(concurrent-approval race, QR-photographed dead-lock, airplane-mid-ceremony, one-shot consume — need
BE staging worker), Phase 6 browser matrix (need staging + `/open` page). Automated Phase 5 adversarial
rows (envelope tamper, AAD/KDF mutation, SAS determinism, TOTP edge/wait-vs-TTL, manifest structural,
exposure matrix, guard2 exclusion) ARE covered + green.

### 2026-07-08 (later) — GATE QV-1 MET: byte-for-byte parity reconciliation vs BE frozen vectors

BE delivered frozen contracts (`~/Developer/Projects/frontend/looxpassword/docs/quick-view-contracts.md`
+ `workers/loox-quick-view/schemas/*-vectors-v1.json`). Reconciled the app against them — the frozen
vectors are the acceptance oracle. **Verified independently: BUILD SUCCEEDED; full suite 404/404, 0
failures; `QuickViewParityTests` 8/8 pass byte-for-byte.**

Fixes applied (all had been `PENDING GATE QV-1` placeholders):
- **SAS rewritten** — BIP-39 English 2048 (bundled `Vaultify/Resources/sas-wordlist-bip39.txt` from BE
  `sas-wordlist.ts`), correct HKDF (ikm = session_id‖enc_hash‖sig_hash **hex-decoded bytes**, salt/info
  = utf8("LOOX-QV-SAS-V1"), L=4), bit-packed word indices + `okm[3]%100`. Golden → "ramp foam 97". (Was
  EFF-7772 + wrong derivation — total mismatch, now fixed.)
- **SESSION-V1 transcript** — `key_id` moved to 3rd position (after version); all hash/id/nonce fields
  hex-decoded to raw bytes for the blob (were utf8). Verifies vs golden signature.
- **PAYLOAD sealer** — KDF magic `LOOX-QUICK-VIEW-KDF-V1` + `byte(1)` version + hex-byte blobs; AAD magic
  prefix added; `payload_key_info = raw("LOOX-QUICK-VIEW-PAYLOAD-V1")‖byte(1)‖raw("aead-key")` (was
  `magic‖u32‖"app-to-browser"`); uploaded ciphertext = IV(12)‖ct‖tag opaque.
- **Upload assertion** canonical body + u16 clientData framing verified vs vector.
- **NEW SIGNER-KEYSET-V1** (`VaultifyCore/Models/QuickViewSignerKeyset.swift` +
  `QuickViewSignerKeysetClient.swift`, mirrors DomainRegistry) — SESSION-V1 now verifies against the
  runtime signer key ENDORSED by the offline-signed keyset (status active/verify_only, env/window),
  not the bundled manifest root. Vector-verified.
- **QR variant B parser** (`QuickViewQRCode.swift`) — `LOOX-QV-QR-V1:{code}:{b64url(sha256(sid‖enc‖sig)[:8])}`
  parse + post-resolve digest binding.
- Vector corrections BE made vs my brief: `approval_id` = raw 32 random bytes (not UUID string);
  `CapabilityManifest` capability map already lenient on unknown names (no change needed).
- Earlier code-review security fixes CONFIRMED intact through the rewrite: guard2-TOTP exclusion,
  mandatory (non-optional) key-hash substitution guard.

**Still needs BE confirmation (honestly flagged, no frozen vector):**
1. **QR variant A vs B** — contract doc still lists QR density as pre-freeze "open"; app implements
   variant B per handoff, awaiting the device-scan benchmark (QV-A0) + BE QR-V1 freeze.
2. **Upload HTTP body encoding** — hex vs base64 for `enc_key_hash`/`approval_id`/`field_manifest_hash`
   in the `aad_fields` JSON is not vector-covered (only transcript bytes are frozen); app chose hex —
   confirm with BE.

**Still BLOCKED (external):** Phase 5 staging drills + Phase 6 browser matrix (need BE staging deploy;
BE rollout is owner-gated per DEC-QV-ROLLOUT-01: prod required-before-active, fail-closed encoded).

## Non-goals (V1)

Passkey handoff · attachments · multi-item per session · persistent/"trusted browser" sessions ·
browser-initiated field requests · Mac/iPad native enter-code surfaces · autofill-into-page.

## Risks

- QR payload density unresolved (variant A full envelope vs B locator+digest) — benchmark in
  Phase 1 BEFORE session-envelope freeze; wrong pick = re-freeze.
- Custom KEM (transcript-bound ECDH) instead of HPKE: acceptable per house discipline ONLY with
  frozen vectors + mutation matrix (Phase 2/5) — no drive-by "simplifications" to the KDF.
- Web `/open` page is out of app-team hands; app-side AAD/PoP verify must not assume browser
  correctness (one-shot + TTLs are the backstop).

## Red Team Review

### Session — 2026-07-08
**Findings:** 10 (10 accepted, 0 rejected). Reviewers: Security Adversary (completed, 7 findings);
Failure-Mode / Assumption / Scope lenses covered by controller verification (3 parallel subagents
aborted on credit exhaustion — findings re-derived with grep evidence, not lost).
**Severity breakdown:** 3 High, 7 Medium.

| # | Finding | Sev | Disposition | Applied To |
|---|---------|-----|-------------|------------|
| F1 | `ApprovalCeremonyService` not reusable (CKShare/ChaCha-bound); real primitives = `TOTPWindow`+`TOTPIssuancePolicy`+`TOTPGenerator` | High | Accept | plan.md, Phase 2, 4, 5 |
| F8 | Kernel placed in VaultifyCore diverges from LooxLink app-only ADR; can't import app-only envelope; wordlist bundling gap | High | Accept | plan.md, Phase 2 |
| F4 | `LooxLinkEnvelope.build()`/`shareableFields` hard-excludes TOTP; `Field` has no id → virtual TOTP can't route through it | High | Accept | Phase 4 |
| F5 | Serializer dialect conflict: `CanonicalWriter` vs `LooxLinkCanonical` inline u16/u32 | Medium | Accept | Phase 2 |
| F6 | Wrong enum name (`Capability` → `CapabilityID`); quick-view needs its own service-state URL | Medium | Accept | Phase 3 |
| F2 | Shadow-mode upload assertion leaves INV-QV-16 unenforced at GA | Medium | Accept | Phase 3, 5, 6 |
| F3 | SAS over-credited vs attacker-controlled `/open` page (phishing residual) | Medium | Accept | Phase 4, 5 |
| F7 | TOTP boundary-wait competes with 180s TTL; 30s code shown under 5-min render | Medium | Accept | Phase 4 |
| F9 | App already ships `eff_large_wordlist.txt` — SAS spec should not bundle a 2nd wordlist | Medium | Accept | Phase 1 |
| F10 | `QuickViewHistoryStore` duplicates `LooxLinkRecordStore`/`KeychainStore` pattern | Medium | Accept | Phase 4 |

Evidence: `ApprovalCrypto.swift:92` (ChaCha), `ApprovalModels.swift:335` (`TOTPWindow`),
`LooxLinkEnvelope.swift:35-40` (TOTP excluded), `ApprovalCanonical.swift:32` (`CanonicalWriter`),
`LooxLinkCanonical.swift:22` (inline enum), `Capability.swift:6` (`CapabilityID`),
`CapabilityHealthProbe.swift:12` (per-id `readyURL`), `Project.swift:200,124` (EFF wordlist),
`LooxLinkAttestation.swift:10-12` (register-before-assert pattern QuickView inherits).

### Whole-Plan Consistency Sweep
- Files reread: plan.md + all 6 phase-*.md
- Decision deltas checked: 10 (kernel→app-side placement; TOTP primitives not `ApprovalCeremonyService`;
  `CapabilityID` enum; virtual-TOTP append path; single serializer dialect; wordlist reuse; history
  store pattern; GA gate on required-mode; SAS honest framing; TOTP wait bounded by TTL)
- Reconciled stale references: 2 (removed dead `VaultifyCore/Models/QuickView*` paths; de-duped
  `QRScannerView`). All `ApprovalCeremonyService` mentions now carry the NOT-reused qualifier.
- Unresolved contradictions: 0

## Validation Log

### Session 1 — 2026-07-08 (owner interview, 4 decisions)

**DEC-QV-EXPOSURE-01 (F2) — Cohort-gated exposure, NOT binary GA gate.** Quick View has a
three-state exposure control `quick_view.exposure = disabled | beta | public`. Public GA entry stays
hidden until backend assertion = **required**; shadow-mode uploads are accepted ONLY for an
explicitly gated beta cohort (TestFlight/internal) so real-device App Attest learning (invalidKey,
re-registration, challenge retry, assertion latency, stale builds) happens before required. Gating is
multi-layer: **app build/cohort gate + signed-manifest exposure state + backend cohort allowlist**
(an app-only UI flag is insufficient — a custom client bypasses UI). Backend rule: `if assertion_mode
== shadow → accept upload only from beta cohort`. State matrix (capability × assertion × cohort):
disabled/any/any→deny · beta/shadow/beta-tester→allow+record · beta/shadow/public→deny ·
public/required/eligible→allow · public/shadow/any→fail-closed. Beta shadow must NOT make a
"fully protected" security claim; still requires DO one-shot, short TTL, rate limit, no plaintext,
generic errors, telemetry, kill switch.
- Invariant rewrites: **INV-QV-16** → "A session accepts exactly one accepted approval upload. In
  production public mode, an upload is eligible only after successful REQUIRED App Attest
  verification. Shadow-mode uploads are permitted only for explicitly gated beta cohorts."
  **INV-QV-24 (new)** → "Public Quick View exposure MUST remain disabled while upload assertion
  enforcement is below REQUIRED."
- Rollout (owner-frozen): 1 staging off → 2 staging shadow → 3 staging required → 4 prod dark deploy
  → 5 prod beta cohort + shadow → 6 collect verdicts → 7 prod required → 8 verify health → 9 public
  GA manifest active.
- **Cross-doc dependency:** the backend companion proposal must add the exposure-state field + cohort
  allowlist + the shadow-accepts-beta-only rule (currently only app-plan carries it). Flag to BE.

**DEC-QV-FIELD-01 (F4) — Quick-View composer; `LooxLinkEnvelope` unchanged.** Base field set via the
existing `LooxLinkEnvelope` shareable builder; Quick-View-only virtual fields (current TOTP) appended
OUTSIDE the envelope by a dedicated Quick View payload composer using a **typed model**
(`QuickViewApprovedField` + `QuickViewFieldKind{username,password,email,website,note,custom,currentTOTP}`),
NOT a generic dictionary. `LooxLinkEnvelope` keeps its narrow invariant (persisted shareable fields
only) — do not teach it Quick-View concepts.
- **INV-QV-25 (new)** → "`field_manifest_hash` MUST be computed from the final ordered field set
  after all Quick-View-only virtual fields are materialized." Order frozen: persisted approved fields
  (deterministic envelope order) THEN virtual fields (fixed protocol order; V1 = `currentTOTP` last).
  Independent of tap/toggle/locale/label order.
- Manifest hash is **STRUCTURAL** (`count` + per-field `[stableID, kind, concealed, ordinal]`), NOT
  over secret values — ciphertext integrity is AES-GCM's job; hashing values duplicates
  responsibility and risks logging derived hashes of secrets. Transcript `LOOX-QV-FIELD-MANIFEST-V1`.

**DEC-QV-QR-01 (Q1) — Split SESSION freeze from QR carrier.** Freeze `LOOX-QUICK-VIEW-SESSION-V1`
(signed security object) EARLY, independent of QR transport. Human code = separate
`LOOX-QUICK-VIEW-CODE-V1` (resolve-only). QR carrier `LOOX-QUICK-VIEW-QR-V1` frozen AFTER a Phase-1
real-device benchmark of variant A (full signed envelope in QR) vs B (compact locator + envelope
digest, app fetches then verifies sig + digest-matches-QR). Benchmark on degraded conditions (old
iPhone, slow autofocus, low-brightness/glare screens, 20–60cm, low light, light/dark, Chrome/Edge/
Safari). Threshold: **choose A if success ≥ 99% & p95 scan < 2s on target devices, else B.** Owner
leans B pre-benchmark (used on strangers' machines; protocol already network-dependent via
bind/upload/poll, so a fetch barely dents the "offline" property; digest in QR binds fetch result to
what the user scanned). **No SESSION-V1 re-freeze permitted merely because the QR carrier changes.**

**DEC-QV-TOTP-01 (F7b) — Field-level TOTP expiry, not payload-wide.** Payload render TTL stays 5 min
(owner-locked). The virtual current-TOTP field carries an **authenticated `valid_until`** (exact TOTP
window boundary, app-minted) as payload metadata INSIDE the ciphertext / AEAD-bound (never a
plaintext-mutable field; browser/BE must not re-derive it from an assumed 30s period — clock skew /
custom period / future variants). Browser shows a per-code countdown and **redacts the OTP value once
`valid_until` passes** ("Expired — generate a new code on your phone"); other approved fields remain
until the normal 5-min render TTL. Fallback if field-level expiry is too much for V1: page TTL =
`min(5m, otp_valid_until)`. Owner rejected "keep 5 min + hint copy" (shows a stale secret too long).
- **INV-QV-26 (new)** → "A virtual current-TOTP field MUST carry its exact validity boundary as
  authenticated payload metadata. The browser MUST stop presenting the code as usable once that
  boundary passes." Optional `virtual_field_metadata_hash` in AAD is a post-V1 hardening, not required.
- **Cross-doc dependency:** the `/open` page (BE/web) owns the countdown + redaction; flag to BE.

### Whole-Plan Consistency Sweep (validation)
- Files reread: plan.md + all 6 phase-*.md
- Decision deltas checked: 4 (exposure states vs binary GA gate; contract split SESSION/QR/CODE +
  FIELD-MANIFEST; typed field model + structural hash; field-level TOTP `valid_until`)
- Reconciled stale references: 2 (GATE QV-1 artifact list 5→8 with the split; superseded "GA gate on
  required-mode" wording removed in favor of the three-state exposure matrix). Field kind naming
  unified to `currentTOTP` across all files.
- Unresolved contradictions: 0. Prior open questions (QR variant, SAS wordlist) now carry decision
  rules; remaining opens are BE-contract encodings resolved inside Phase 1's freeze.
- **Backend cross-doc actions flagged (not app-plan scope):** companion backend proposal needs (a)
  `quick_view.exposure` state + cohort allowlist + "shadow accepts beta-only"; (b) payload schema
  carrying AEAD-bound TOTP `valid_until`; (c) `/open` field-level countdown + redaction; (d) the
  SESSION/QR/CODE artifact split. These are BE deliverables surfaced during Phase 1 freeze.
