---
phase: 1
title: "Contract Freeze Parity Sign-off (QV-A0)"
status: pending
priority: P1
effort: "0.5d"
dependencies: []
---

# Phase 1: Contract Freeze Parity Sign-off (QV-A0)

## Overview

**No code.** Reconcile + sign off the frozen byte-level contracts with BE, resolve the two
pre-freeze unresolved questions, receive vector sets. Closes **GATE QV-1**; unblocks Phases 2–4.
Governance = DEC-03/shorten pattern: BE owns canonical encoders, generators IMPORT the production
encoder, frozen JSON vectors, app parity signs off byte-for-byte.

**Progress (2026-07-08):** app-side analysis DONE →
`reports/qv-a0-qr-density-and-sas-wordlist-analysis-report.md`. QR byte budgets computed (A = QR v12
65×65 offline w/ pubkeys; B = v4–v8 33–49 modules w/ fetch) + surfaced a freeze-critical gap:
SESSION-V1 hashes-only is NOT offline-ECDH-usable (needs the real browser pubkey) → "offline variant
A" must carry compressed pubkeys. SAS wordlist verified = **7772 words** (not canonical EFF 7776;
`PasswordGenerator.swift:3` comment stale) → BE/web must adopt the exact same file. STILL PENDING:
BE draft artifacts+vectors, physical-device QR benchmark, BE decisions on §Open-items 2/4/5/6.

## Requirements

Frozen artifacts to review (backend doc §B3 — verify owner P0/P1 corrections landed). **Contract split
per DEC-QV-QR-01:** the SESSION envelope, the QR carrier, and the human code are THREE independent
artifacts — SESSION-V1 freezes early, QR-V1 freezes after the benchmark, no SESSION re-freeze when the
QR carrier changes:
1. `LOOX-QUICK-VIEW-SESSION-V1` — signed session envelope (freeze EARLY, transport-independent).
   Check: `env` INSIDE signed payload, registry-style `key_id`, same P256 trust root as
   cap-manifest/domain-registry, distinct MAGIC.
2. `LOOX-QUICK-VIEW-QR-V1` — QR carrier (freeze AFTER benchmark). Mode = `fullEnvelope` (variant A)
   or `locatorDigest` (variant B: `protocol ‖ session_id ‖ envelope_hash` [+ minimal server sig] →
   app fetches SESSION-V1, verifies sig AND that its hash matches the QR digest).
3. `LOOX-QUICK-VIEW-CODE-V1` — human code, resolve-only (Crockford 8+checksum, POST body).
4. `LOOX-QUICK-VIEW-PAYLOAD-V1` — KDF transcript + AAD. Check INV-QV-18: kdf_transcript carries
   `version ‖ session_id ‖ browser_enc_key_hash ‖ browser_sig_key_hash ‖ app_eph_pub_hash ‖ env`;
   AAD carries `session_id ‖ enc_key_hash ‖ approval_id ‖ field_manifest_hash ‖ issued_at ‖ expires_at`.
   **Virtual TOTP `valid_until` metadata (DEC-QV-TOTP-01/INV-QV-26):** the current-TOTP field's exact
   validity boundary rides INSIDE the ciphertext (AEAD-bound), never plaintext-mutable; confirm the
   payload plaintext schema carries it so the `/open` page can count down + redact.
5. `LOOX-QV-FIELD-MANIFEST-V1` (DEC-QV-FIELD-01) — **structural** manifest hashed for AAD's
   `field_manifest_hash`: `count ‖ per-field [stableID, kind, concealed, ordinal]`, computed over the
   FINAL ordered field array (persisted envelope-order fields THEN virtual fields; V1 currentTOTP
   last). NOT over secret values. Confirm BE/app/web agree on the structural encoding + order.
6. `LOOX-QUICK-VIEW-POP-V1` — browser PoP (app side only observes; still review operation/env fields).
7. `LOOX-APP-ATTEST-QUICK-VIEW-V1` — upload assertion: `u16len(method) ‖ u16len(path) ‖
   u16len(challengeId) ‖ u16len(session_id) ‖ SHA256(canonicalUploadBody)` — exact bytes, path pinned.
8. SAS spec — derived `words(HKDF("LOOX-QV-SAS-V1", session_id ‖ enc_key_hash ‖ sig_key_hash))`,
   2 words + 2 digits, wordlist + truncation frozen (server never picks the phrase).

## Implementation Steps

1. **QR density benchmark (DEC-QV-QR-01):** variant A (full signed envelope in QR) vs B (compact
   locator `protocol ‖ session_id ‖ envelope_hash` + app fetch). Scan on degraded conditions (old
   iPhone, slow autofocus, low-brightness/glare screens, 20–60cm, low light, light/dark, Chrome/Edge/
   Safari). Measure: time-to-first-success, success rate, retries, false decodes, min practical QR
   size. **Decision rule: choose A if success ≥ 99% AND p95 scan < 2s on target devices, else B.**
   Feeds `LOOX-QUICK-VIEW-QR-V1` freeze ONLY — SESSION-V1 is frozen independently and never re-frozen
   for a carrier change. Report result to BE.
2. **SAS wordlist (unresolved Q2):** confirm source list, truncation, and digit derivation with BE;
   freeze in SAS spec. **The app already ships `Vaultify/Resources/eff_large_wordlist.txt`
   (`Project.swift:124,200` — EFF large, 7776 words)** — evaluate reusing it (truncate/index) so the
   app does NOT bundle a second wordlist. Wordlist choice is a FROZEN CONTRACT decided jointly with
   BE/web (both ends derive SAS independently), not an app-local decision — but reuse is the default
   unless BE has a constraint.
3. Review each artifact draft against owner decision log (both proposals) — flag any drift.
4. Confirm `canonicalUploadBody` serialization (field order/encoding — BE encoder decision) is
   documented well enough for Swift parity.
5. Receive golden + mutation vector sets per artifact (session/browser/approval/field-manifest
   swaps, lowercase-method normalization, env cross-replay rejection).
6. Sign off GATE QV-1; record contract doc path/version in this plan dir.

## Success Criteria

- [ ] SESSION-V1 frozen early; QR-V1 frozen post-benchmark; CODE-V1 separate (DEC-QV-QR-01)
- [ ] QR variant decided by threshold (≥99% & p95<2s → A, else B); result recorded
- [ ] SAS wordlist + truncation frozen (reuse shipped `eff_large_wordlist.txt` unless BE blocks)
- [ ] Structural `LOOX-QV-FIELD-MANIFEST-V1` + field order agreed BE/app/web (DEC-QV-FIELD-01)
- [ ] Payload schema carries AEAD-bound TOTP `valid_until` (DEC-QV-TOTP-01/INV-QV-26)
- [ ] Exposure-state + cohort-allowlist rule confirmed in backend contract (DEC-QV-EXPOSURE-01)
- [ ] All 8 artifacts signed off, zero drift vs owner decision log
- [ ] Vector sets (golden + mutation) in hand, referenced for Phase 2 parity tests
- [ ] GATE QV-1 declared closed with BE

## Risk Assessment

- Freezing the QR carrier before the benchmark ⇒ possible re-freeze — benchmark is step 1. But
  SESSION-V1 CAN and SHOULD freeze early (transport-independent, DEC-QV-QR-01) so kernel work isn't
  blocked on the benchmark.
- Watch for BE "simplifying" the KDF transcript back to AAD-only (undoes owner P0-1).
- Manifest hash must stay structural (DEC-QV-FIELD-01) — if BE proposes hashing values, push back
  (duplicates AES-GCM integrity, risks logging secret-derived hashes).

<!-- Updated: Validation Session 1 — DEC-QV-QR-01 contract split + benchmark threshold; DEC-QV-FIELD-01 structural manifest; DEC-QV-TOTP-01 valid_until; DEC-QV-EXPOSURE-01 cohort rule -->

## Unresolved questions

None new. Prior open items (QR variant, SAS wordlist) now have decision rules; both resolve inside
this phase's benchmark + BE freeze.
