# Code Review — Phase 2 Approval Mode Control-Plane Crypto Kernel

Scope: `VaultifyCore/Sharing/` (ApprovalModels, ApprovalCanonical, ApprovalCrypto, ApprovalVerifier, ParticipantIdentity; ApprovalConfig noted), `VaultifyTests/ApprovalKernelTests.swift`. Plan refs: `plans/260705-1137-approval-mode-sharing/phase-02-control-plane-crypto-core.md`, plan.md ADR-3/4/6/7. Findings only — no fixes applied.

## Overall Assessment

Strong kernel. Fail-closed verifier ordering correct (nonce consumed last = correct TOCTOU posture with atomic create-if-not-exists), ADR-3 two-recipient contract enforced by construction + cross-open tests, canonical encoding is injective with anti-malleability (`isAtEnd` guard), reader is bounds-checked before allocation, ADR-7 grep-clean (Unix-ms Int64 only; sole `Calendar`/`TimeZone` mention is a doc comment; `ApprovalConfig.requestTTL/responseTTL` are `TimeInterval` seconds — transport constants, not protocol timestamps, but inconsistent with the named-ms convention). Type-level askEachTime-TOTP-only constraint delivered exactly per M3/N. All types `nonisolated` + `Sendable`, compiles under MainActor default isolation. Issues below are design gaps + hardening, not broken crypto.

## High

### H1 — `verifyRequest` has no owner-side trust root: self-pin is a tautology
`ApprovalVerifier.swift:69` — `verifyGrant(grant, pinnedOwnerSigningKey: grant.ownerSigningPubKey, ...)` compares the grant's claimed key to itself; the pin check is a no-op on the owner path. `verifyRequest` therefore proves only *internal consistency* (grant signed by whatever key it embeds), never provenance. Anyone able to place a grant record in front of this API (with a guessable epoch — typically 1) mints a fully "valid" grant with their own key pair. Exploitability currently depends entirely on Phase-3 storage ACLs (grants living in the owner's private zone). Two structural complications: (a) multi-device owner — grant signed on device A1 won't match A2's `DeviceSigningIdentity`, which is presumably why the self-pin exists; (b) the kernel claims "the whole trust model rests here" (phase overview) yet delegates grant provenance silently to transport. Recommend: make `verifyRequest` take an explicit `trustedOwnerSigningKeys: Set<Data>` (owner's own enrolled device keys) instead of self-pinning, or at minimum a loud doc-contract that grant authenticity is a caller/transport obligation + a Phase-3 checklist item. The B-side path (`verifyGrant` with a real TOFU pin) is sound as designed (ADR-4), tested at `ApprovalKernelTests.swift:166`.

### H2 — No `verifyResponse` in the kernel: B-side trust checks left to UI phases
`ApprovalResponse` carries `ownerSigningPubKey` + `ownerSignature` (`ApprovalModels.swift:104-111`), but `ApprovalVerifier` has no response verifier (grep: none in repo). B-side (Phase 5/6) must hand-roll: TOFU-pinned owner-key check, signature over `signingBody()`, requestId match, `respondedAtUnixMs` freshness vs `responseTTL`, decision/payload consistency (`approved` with nil `sealedPayload`, `rejected` WITH payload — both currently representable and unvalidated), and the `TOTPApprovalPayload.requestNonce` echo check after opening. History says this exact class of gap bites (ADR-3 note: "prior draft opened the ephemeral-sealed response with the participant key — a bug"). If planned for Phase 5, pull it forward into the kernel with typed failures so it can't be skipped or misordered in view-model code.

## Medium

### M1 — Pinned-key sort on encode, wire order on decode → decode(encoded(x)) ≠ x for multi-key grants
`ApprovalCanonical.swift:156` sorts `pinnedDeviceSigningKeys` into the signed bytes; `decode` (`:187`) returns wire (=sorted) order; synthesized `Equatable` is order-sensitive. Signatures still verify (`signingBody()` re-sorts — round-trip crypto is safe), but a grant built with keys in non-lexicographic order fails `==` against its own decode. `testCanonicalRoundTripPreservesSignatures` passes **only because every test grant has exactly one pinned key** (`ApprovalKernelTests.swift:35`). Latent hazard for Phase 3/4: any "did the grant change?" comparison (sync dedup, re-sign detection, device-enrollment diff) will see phantom changes → spurious re-sign/upload churn. Fix: normalize (sort) in decode and/or a memberwise-init `didSet`, or treat the property as a `Set<Data>` semantically. Also: decode accepts duplicate/unsorted pinned keys without rejection (harmless today — re-canonicalization means a mutated wire ordering still verifies iff semantics unchanged; duplicated capability fieldIds collapse in the dictionary and then fail signature — fail-closed, good).

### M2 — No request-lifetime clamp: B-signed `expiresAtUnixMs` is trusted unbounded
`ApprovalVerifier.swift:86` only checks `now < expiresAt`. A compromised-but-pinned B device can sign requests with multi-year expiry: they sit approvable in the owner's queue indefinitely, and `consume(nonce:expiresAtUnixMs:)` (`:94`) propagates that horizon into nonce retention ("never TTL-pruned below max request lifetime" — H4) → unbounded nonce-store growth. `ApprovalConfig.requestTTL = 120` exists (`ApprovalConfig.swift:51`) but is UI-layer only. Add a kernel clamp: reject when `expiresAt - createdAt > maxRequestLifetimeMs` or `expiresAt > now + maxRequestLifetimeMs` (new typed failure). `createdAtUnixMs` is otherwise entirely unchecked (future-dated accepted) — fold a sanity bound into the same check.

### M3 — HPKE `info` strings use ambiguous "|" concatenation instead of length-prefixing
`ApprovalCrypto.swift:70-76` — `"Loox approval response v1|\(requestId)|" + nonce` and `"Loox shared field v1|\(grantId)|\(fieldId)"`. Variable-length fields joined by an in-alphabet delimiter are not injective: `(grantId: "g|x", fieldId: "y")` and `(grantId: "g", fieldId: "x|y")` produce identical info → cross-field/cross-grant seal-context collision. Plan explicitly calls field ids "mutable strings" (M3); today they're app-generated so not practically exploitable, but the invariant is one editor change away from breaking. The codebase already does this right: `TrustFingerprint.code` uses `CanonicalWriter` length-prefixed blobs (`ApprovalCrypto.swift:141-146`). Use the same for both info builders. Do it now — it's a wire-format break later.

### M4 — `loadOrCreate` silently regenerates the device identity on undecodable key material
`ApprovalCrypto.swift:24-25` — `try? P256.Signing.PrivateKey(rawRepresentation:)` failure falls through to generate-and-overwrite. Corrupted/garbage keychain data → silent key rotation; every grant pinning the old key starts failing with `requesterKeyUnpinned` and no diagnosable cause on the owner side. Surface a typed error (or at least log + require explicit re-enrollment) instead of self-healing into a trust break. Related low-severity race: app and AutoFill extension calling `loadOrCreate` concurrently on first run — `KeychainStore.set`'s copy-then-add TOCTOU means the loser throws `unexpectedStatus(errSecDuplicateItem)` rather than silently forking identities (fail-visible, acceptable; a retry-read on duplicate would make it clean).

## Low

- **L1 — Escrow lacks AAD/domain separation.** `ParticipantIdentity.escrowSealed` (`ParticipantIdentity.swift:29-33`) is bare `AESGCM.seal` of 32 bytes under the Vault Key; any other 32-byte AES-GCM-under-Vault-Key ciphertext in the system is substitutable at the envelope layer (attacker can't forge, only swap known ciphertexts — weak attacker model, but free to fix). AESGCM helper (`VaultifyCore/Crypto/AESGCM.swift`) has no AAD parameter; the version byte is outside the AEAD. Consider AAD `"vaultify.participant-identity.v1"` when the helper grows AAD support.
- **L2 — TrustFingerprint is ~49.8 bits** (3×5 digits, `ApprovalCrypto.swift:147-151`). MITM needing a fingerprint-colliding P256 keypair does ~2^49 keygen+SHA256 — costly, not comfortably infeasible (Signal uses 60 digits). Acceptable as a *secondary* check given CloudKit-authenticated transport; document that it's not the primary channel binding, or add a 4th group. (Also: `value % 100_000` on u32 has negligible bias — fine.)
- **L3 — `TOTPWindow.counter` `precondition(period > 0)`** (`ApprovalModels.swift:135`) crashes on period 0. B-side computes advisory countdown from a decoded `TOTPApprovalPayload` whose `period` is remote input → corrupt/malicious payload = deterministic crash (DoS-by-trusted-owner only, but the kernel is supposed to fail closed, not trap). Return-nil/clamp on B-side ingestion, or validate period at payload decode.
- **L4 — Verifier never sanity-checks `nonce` or `ephemeralPubKey`.** Zero-length nonce passes all 8 steps (replay protection still holds — exact-match store — but info-binding entropy and the H4 record-name scheme degrade); an invalid 31/33-byte `ephemeralPubKey` is only discovered at seal time *after* the user completed the Face-ID approval ceremony (fail-closed but late, wasted ceremony). Cheap early guards: `nonce.count >= 16`, `ephemeralPubKey.count == 32`.
- **L5 — `UInt32(count)` casts trap on absurd sizes** (`ApprovalCanonical.swift:42,154,159`) — crash-not-corrupt for >4 GiB blobs / >2^32 entries; unreachable in practice, but the reader side is exemplary (bounds-check before allocation, `ApprovalCanonical.swift:104-110`), so the writer asymmetry is worth a comment or `guard`.
- **L6 — `ApprovalConfig` TTLs are `TimeInterval` seconds** (`ApprovalConfig.swift:51-53`) while the kernel convention is named Int64-ms constants (`TOTPIssuancePolicy`). Unit-mismatch foot-gun when Phase 3 compares `requestTTL` against `expiresAtUnixMs`. Rename/retype to `requestTTLMs: Int64 = 120_000`.

## Checklist Verdicts

- **(a) Crypto correctness** — Correct CryptoKit usage throughout: P256 raw-representation sign/verify with graceful `false` on malformed inputs (`ApprovalCrypto.swift:47-53`); HPKE one-shot Sender/Recipient, `Curve25519_SHA256_ChachaPoly`, encap length 32 correct for X25519; envelope `version || encap || ct` with min-length + version checks; AES-GCM escrow via combined-box helper. No API misuse found. Info-string construction is the one weakness (M3).
- **(b) Canonical encoding** — Deterministic and injective per artifact (sorted dict keys, sorted pinned set, length-prefixed everything, fixed-width big-endian, optional flag bytes, `isAtEnd` trailing-garbage rejection). Malformed input safe: length prefixes bounds-checked before any copy. Confirmed suspicion: sort-on-encode vs wire-order-decode is real (M1), masked by single-key test fixtures. u32 casts: L5.
- **(c) Verifier ordering / fail-closed** — No default-open path; every guard returns a typed failure; nonce-store throw maps to rejection (`:98-99`). Nonce-last is the right TOCTOU trade (invalid requests can't burn nonces; concurrent duplicates race only at the atomic authority). Owner self-pin: H1. B-side pin path: adequate. Note: nonce burns on verify (pre-UI), so owner-reject/abort forces B to re-request — consistent with `.interrupted` semantics, fine.
- **(d) Spec compliance** — ADR-3: enforced (distinct keys AND distinct info per purpose; cross-open tested both directions). ADR-7: compliant (integer Unix-ms math only; test pins same-instant-across-timezones counter). M3 unknown-field fail-closed: implemented + tested. Type-level askEachTime-TOTP-only: exactly as specified. ADR-6 `TOTPIssuancePolicy` constants match plan (18s/20s), boundary tested at exact threshold.
- **(e) Keychain** — `WhenUnlockedThisDeviceOnly` + `kSecUseDataProtectionKeychain` appropriate for a never-synced device key. Both targets' entitlements list only `$(AppIdentifierPrefix)com.bervion.vaultify.shared`, so `accessGroup: nil` defaults both processes into the same shared group → app and extension share ONE device signing identity (same device = same identity; sound, but make it deliberate in a comment — if separate identities were intended, this silently isn't that). First-run create race: fail-visible, see M4.
- **(g) Isolation** — All kernel types `nonisolated` + `Sendable`; no `@unchecked` outside the test nonce store; CryptoKit key types are Sendable; compiles under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (157/157 green per task context).

## Phase-8 Test Gaps (f)

1. Multi-key pinned set round-trip (would have caught M1) — grant with 3 unsorted keys: decode-equality + signature + `contains` membership.
2. Request-lifetime clamp (once M2 lands) — expiresAt = now + 10y rejected.
3. `verifyResponse` suite (once H2 lands) — wrong owner key, tampered ciphertext, requestId mismatch, approved-with-nil-payload, rejected-with-payload, stale respondedAt, requestNonce echo mismatch.
4. Empty/short nonce + malformed 31/33-byte ephemeralPubKey through `verifyRequest` (L4).
5. Grant with empty `pinnedDeviceSigningKeys` (verifies fine; all requests fail `requesterKeyUnpinned` — confirm fail-closed) and empty `capabilities`.
6. Decode fuzz: truncation at every field boundary for all 3 artifacts; length prefix 0xFFFFFFFF (must throw `truncated`, no allocation); duplicate capability keys (must fail signature).
7. HPKE info-collision regression once M3 length-prefixing lands (old envelopes must fail to open → confirms it's a versioned break).
8. `TOTPWindow` at negative unixMs (clamps to 0), period boundary exact-ms, and CKRecord round-trip byte-identity gate (already planned).
9. Cross-process `loadOrCreate` duplicate-item path (errSecDuplicateItem → error, not fork).

## Positive Observations

- Nonce-last + throw-maps-to-rejection is textbook fail-closed; the doc comments encode *why*, not just what.
- Type-tag + version domain separation means a grant can never verify as a request — tested.
- `TrustFingerprint` already uses the canonical writer for injective hashing — the right instinct exists in this file; M3 is just applying it consistently.
- Reader bounds-check-before-allocate defeats length-prefix memory bombs.
- Two-case `FieldCapability` making invalid states unrepresentable is exactly the right shape for a security kernel.

## Recommended Actions (priority order)

1. H1 — parametrize the owner-side grant trust root (or document + Phase-3 gate item).
2. H2 — add `ApprovalVerifier.verifyResponse` to the kernel before Phase 5 consumes responses.
3. M3 — length-prefix HPKE info strings NOW (wire break is cheapest pre-ship).
4. M1 — normalize pinned-key ordering at decode/init.
5. M2 — kernel max-request-lifetime clamp.
6. M4/L* — as batched hardening with Phase-8 tests.

## Unresolved Questions

- Is app↔extension sharing one `DeviceSigningIdentity` (via the shared keychain group) intentional? (Affects whether AutoFill-context requests are signed by a pinned key.)
- Multi-device owner: which device key signs grants, and how do sibling owner devices establish trust in it? (Drives the H1 API shape.)
- Is `ApprovalConfig.swift` (transport constants, in the same dir) Phase-2 or Phase-3 scope? Reviewed lightly here (L6); it references `CryptoRandom` and CloudKit naming not in the Phase-2 file list.
