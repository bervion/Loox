---
phase: 2
title: "Kernel: Envelope Verifier + SAS + Sealer (QV-A1)"
status: pending
priority: P1
effort: "1.5d"
dependencies: [1]
---

# Phase 2: Kernel — Envelope Verifier + SAS + Sealer (QV-A1)

## Overview

Pure, parity-tested kernel. No UI, no networking, no DeviceCheck. Everything here must reproduce the
frozen vectors byte-for-byte before Phase 3 starts.

**Placement (F8):** kernel lives in `Vaultify/Features/Sharing/QuickView/` (app-only), mirroring the
LooxLink ADR — `LooxLinkEnvelope`/`LooxLinkCrypto`/`LooxLinkCanonical` are all app-side, NOT
VaultifyCore, to keep DeviceCheck out of the appex. It is NOT in VaultifyCore: (a) Quick View is
app-only; (b) VaultifyCore cannot import app-only `LooxLinkEnvelope`, so a VaultifyCore kernel would
be forced into an awkward opaque-`Data` seam and could not build the payload itself. The kernel
still *reuses* VaultifyCore primitives (`CanonicalWriter`, P256 verify helpers, `TOTPWindow`) by
reference — those already compile into the app target via the `VaultifyCore/**` source glob.

## Architecture

- **Session envelope verifier** — follow `DomainRegistryDocument.swift` + verifier pattern
  (verbatim-wire transcript, lenient typed mapping, P256 sig over canonical bytes, same trust
  root as `CapabilityManifest` `cap-2026-01`, distinct MAGIC `LOOX-QUICK-VIEW-SESSION-V1`).
  Checks: signature, schema, protocol version, expiry, env match, key-hash consistency
  (enc/sig pub hashes vs QR/code payload).
- **SAS derivation** — `words(HKDF("LOOX-QV-SAS-V1", session_id ‖ enc_key_hash ‖ sig_key_hash))`
  → 2 words + 2 digits from the frozen wordlist (Phase 1: reuse shipped `eff_large_wordlist.txt`).
  Pure function; identical output to web impl.
- **Sealer** — ECDH P-256(app ephemeral, browser enc pub) → HKDF-Extract(salt =
  SHA256(kdf_transcript)) → HKDF-Expand(info = magic ‖ version ‖ role) → AES-256-GCM.
  AAD builder per `LOOX-QUICK-VIEW-PAYLOAD-V1`. App ephemeral keypair generated per seal,
  never reused. Plaintext input = serialized payload `Data`; because the kernel is app-side (F8) it
  MAY build the `LooxLinkEnvelope` directly (Phase 4 owns the vault re-read + field selection and
  passes the assembled envelope, including the appended virtual TOTP field per F4).
- **Serializer dialect (F5):** the two canonical dialects in the repo differ — VaultifyCore
  `CanonicalWriter` (`ApprovalCanonical.swift:32`) vs the LooxLink inline `u16/u32/u64` closures
  (`LooxLinkCanonical.swift:22`). Pick ONE for every Quick View transcript (KDF transcript, AAD,
  and the Phase-3 upload body/assertion) and match whatever BE froze in Phase 1. Recommend the
  LooxLink inline convention (the assertion pattern Phase 3 copies already uses it); if BE froze the
  `CanonicalWriter` layout instead, use that everywhere and prove byte-identity in a parity test.
  Do NOT mix dialects across artifacts.
- **NOT reused: `ApprovalCeremonyService`/`ApprovalSeal`** (F1) — CKShare/`Curve25519_SHA256_ChachaPoly`
  bound. Boundary-aware TOTP uses the pure primitives `TOTPWindow` + `TOTPIssuancePolicy`
  (`ApprovalModels.swift:335`) + `TOTPGenerator`; the mint + wait loop is Quick-View-owned (Phase 4).
- **Typed field model + structural manifest (DEC-QV-FIELD-01):** define
  `QuickViewFieldKind{username,password,email,website,note,custom,currentTOTP}` and
  `QuickViewApprovedField{stableID, kind, label, value, concealed}` (no generic dicts). The manifest
  hasher (`LOOX-QV-FIELD-MANIFEST-V1`) hashes STRUCTURE only — `count ‖ per-field [stableID, kind,
  concealed, ordinal]` — over the FINAL ordered array (persisted fields in deterministic envelope
  order THEN virtual fields; V1 `currentTOTP` last), NOT secret values (INV-QV-25). Kernel exposes
  the hasher; Phase 4 supplies the assembled array. This is pure and parity-tested here.
- Concurrency: `nonisolated` types (CLAUDE.md rule — crypto off-main).

## Related Code Files

- Create: `Vaultify/Features/Sharing/QuickView/QuickViewSessionEnvelope.swift` (parse + typed model)
- Create: `Vaultify/Features/Sharing/QuickView/QuickViewSessionEnvelopeVerifier.swift` (sig/schema/env/expiry)
- Create: `Vaultify/Features/Sharing/QuickView/QuickViewSAS.swift` (derivation; reads shipped `eff_large_wordlist.txt`)
- Create: `Vaultify/Features/Sharing/QuickView/QuickViewPayloadSealer.swift` (ECDH/HKDF/AES-GCM + KDF transcript + AAD)
- Create: `Vaultify/Features/Sharing/QuickView/QuickViewApprovedField.swift` (typed field model + `QuickViewFieldKind`)
- Create: `Vaultify/Features/Sharing/QuickView/QuickViewFieldManifest.swift` (structural `LOOX-QV-FIELD-MANIFEST-V1` hasher)
- Read for pattern: `VaultifyCore/Models/DomainRegistryDocument.swift`,
  `VaultifyCore/Models/CapabilityManifest.swift`, `Vaultify/Features/Sharing/LooxLink/LooxLinkCrypto.swift`,
  `Vaultify/Features/Sharing/LooxLink/LooxLinkCanonical.swift` (dialect), `VaultifyCore/Sharing/ApprovalModels.swift` (`TOTPWindow`)
- Create: `VaultifyTests/QuickViewKernelParityTests.swift` (frozen vectors from Phase 1)

## Implementation Steps

1. Session envelope model + verifier (registry pattern; trusted-root injection for tests).
2. SAS derivation + wordlist resource; cross-check against BE SAS vectors.
3. KDF transcript builder + AAD builder (CanonicalWriter), then sealer (CryptoKit:
   `P256.KeyAgreement`, `HKDF<SHA256>`, `AES.GCM`).
4. Parity tests: golden vectors byte-for-byte (envelope verify accept/reject, SAS strings,
   KDF-derived key, sealed ciphertext with fixed eph key + nonce injection for determinism).
5. Mutation tests: every AAD/KDF field swap from the vector set must fail decrypt/verify;
   env cross-replay rejected; expired envelope rejected.
6. `tuist generate` + compile check (`make check`) + `make test`.

## Success Criteria

- [ ] All golden vectors green byte-for-byte; all mutation vectors rejected
- [ ] SAS output identical to BE/web vectors
- [ ] Kernel has zero UI/network/DeviceCheck imports; types `nonisolated`; lives under `Features/Sharing/QuickView/`
- [ ] Single serializer dialect used across KDF transcript + AAD (F5); parity-proven
- [ ] Structural manifest hasher matches BE vectors; hashes structure not values; order deterministic (DEC-QV-FIELD-01/INV-QV-25)
- [ ] `make check` + `make test` pass (app + extension still compile)

## Risk Assessment

- Determinism in tests: AES-GCM nonce + eph key must be injectable seams (as LooxLink M0 did);
  production path keeps them random.
- Do NOT reuse `ApprovalCrypto` HPKE (`Curve25519_SHA256_ChachaPoly`, `ApprovalCrypto.swift:92` —
  not WebCrypto-compatible); this is a deliberate separate suite.
- Serializer-dialect drift (F5) is the top parity risk: one wrong length-prefix/field-order silently
  passes local golden vectors but fails BE once assertion goes required (discovered only at staging).

<!-- Updated: Validation Session 1 — DEC-QV-FIELD-01 typed field model + structural manifest hasher (INV-QV-25); app-side placement -->

## Unresolved questions

None. Kernel scope is fully specified once GATE QV-1 vectors land.
