---
phase: 5
title: "Adversarial QA Matrix (QV-A4)"
status: pending
priority: P1
effort: "1d"
dependencies: [4]
---

# Phase 5: Adversarial QA Matrix (QV-A4)

## Overview

Attack-shaped verification of every invariant, split into automated XCTest (kernel/client) and
staging drills (need BE staging worker + `/open` page live). Each row maps to an INV-QV-* — a
drill without an invariant is out of scope; an invariant without a drill is a gap.

## Requirements — matrix

Automated (XCTest, extends Phase 2/3 suites):
- Tampered session envelope: bad sig, wrong root, wrong env, expired, key-hash mismatch,
  version skew → all rejected (INV-QV-14 family, verifier surface).
- AAD/KDF mutation matrix: swap each of session_id / enc_key_hash / sig_key_hash /
  app_eph_pub_hash / approval_id / field_manifest_hash / issued_at / expires_at / env
  between two valid contexts → decrypt MUST fail at AEAD (INV-QV-18).
- SAS: two sessions differing in any key hash → different phrases; derivation matches vectors
  (INV-QV-13).
- TOTP window-edge: seal at t = boundary−ε → Quick-View wait loop waits for fresh window; sealed
  code == code valid at issue; seed never serialized (INV-QV-17). Test the pure primitives
  `TOTPWindow`/`TOTPIssuancePolicy` (`ApprovalModels.swift:335`) + `TOTPGenerator` directly (existing
  `ApprovalCeremonyService` tests are a template only — that class is NOT reused, F1). Add: wait
  bounded by session TTL — if fresh window exceeds remaining TTL, abort to "start again" (F7).
- Virtual TOTP appended outside `shareableFields`: structural `field_manifest_hash` (INV-QV-25)
  covers the appended `currentTOTP` field; reorder/drop/kind-swap of the final array → AAD mismatch →
  decrypt fails. Hash is over structure (stableID/kind/concealed/ordinal), NOT values (DEC-QV-FIELD-01).
- TOTP `valid_until` (INV-QV-26): metadata is AEAD-bound (mutating it fails decrypt); assert the
  minted `valid_until` == the window end of the code that was sealed (field-level expiry, DEC-QV-TOTP-01).
- Field-manifest honesty: envelope built from selection {username, website} contains nothing
  else; `field_manifest_hash` in AAD matches actual ciphertext content.

Staging drills (manual/scripted vs staging worker):
- Expired session upload; reused (already APPROVED) session upload → generic failure both.
- **Concurrent-approval race:** two apps upload to one session → exactly one ciphertext lands,
  loser gets generic failure (INV-QV-10/16).
- **QR-photographed drill (owner P0-2):** attacker binds/scans first → legitimate approval
  still wins; no bind action can dead-lock the session (INV-QV-16).
- SAS mismatch drill: human-verify abort-only UI (INV-QV-19).
- **Attacker-controlled `/open` page (F3, accepted residual):** attacker hosts a legitimate session
  on their OWN browser+keys and social-engineers the victim to scan ("scan to view on your
  computer"). SAS MATCHES (it is a real session) — SAS does not defend this class. Verify the
  documented mitigations actually fire: password OFF by default + visibility warning on tick,
  TOTP/notes OFF, browser metadata shown, one-shot. Record as accepted residual, not a pass/fail
  crypto check. SAS/INV-QV-19 defends honest-browser MITM only — do NOT frame it as anti-phishing.
- **Cohort-gated exposure (F2 → DEC-QV-EXPOSURE-01):** drive the state matrix —
  `disabled/any/any → no entry`; `beta/shadow/beta-tester → entry + upload accepted + verdict
  recorded`; `beta/shadow/public → no entry` (public build sees nothing); `public/shadow/any → FAIL
  CLOSED` (INV-QV-24, manifest can't outrun assertion); `public/required/eligible → entry + upload
  accepted`. Verify the app fails closed on public+shadow and that a public (non-beta) build shows no
  entry while exposure=beta. Forged non-app client in shadow: server accepts only from beta cohort
  (backend enforcement — coordinate with BE); app-side check is the exposure gate, not that shadow
  rejects everything.
- Airplane mode mid-ceremony (after Face ID, before upload) → calm error, no partial state,
  session reusable-or-expired handled by "start again".
- One-shot: consume once → second consume fails; app-side confirm shows sent exactly once.

## Related Code Files

- Create: `VaultifyTests/QuickViewAdversarialTests.swift` (mutation matrix, envelope tamper, TOTP edge, manifest honesty)
- Modify: `VaultifyTests/QuickViewKernelParityTests.swift` (extend mutation vectors if BE set incomplete)
- Create: staging drill checklist → results recorded in this file's checklist (no separate report unless failures)

## Implementation Steps

1. Build mutation-matrix test harness (two valid contexts, systematic single-field swap).
2. Envelope tamper suite; TOTP boundary suite; manifest honesty suite.
3. Run staging drills vs BE staging (coordinate: needs rollout step 2 done); record outcomes.
4. File + fix any failures; re-run to green. Failures in frozen-contract behavior escalate to
   BE, not patched around client-side.

## Success Criteria

- [ ] 100% of mutation matrix rejected at AEAD; zero "server policy saved us" cases
- [ ] Race + QR-photographed drills pass: first valid approval wins, no dead-lock
- [ ] SAS mismatch abort-only verified on device; attacker-controlled-page residual documented (F3)
- [ ] Exposure matrix drilled: public+shadow fails closed; beta entry hidden from public build (DEC-QV-EXPOSURE-01)
- [ ] Structural manifest + `valid_until` mutations rejected at AEAD (DEC-QV-FIELD-01/TOTP-01)
- [ ] TOTP edge + airplane-mode drills pass; wait-exceeds-TTL aborts to "start again" (F7)
- [ ] All XCTest suites green in `make test`

## Risk Assessment

- Race drills need two devices/simulators + staging session — script the uploads (curl with
  captured bodies) if second device is impractical; the claim atomicity is server-side but the
  app must handle loser path gracefully.

<!-- Updated: Validation Session 1 — added exposure-matrix drill (DEC-QV-EXPOSURE-01), structural-manifest + valid_until mutation rows (DEC-QV-FIELD-01/TOTP-01) -->

## Unresolved questions

None. Some drills depend on BE staging + cohort allowlist being live (rollout steps 2/5).
