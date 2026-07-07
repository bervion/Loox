# Backend Proposal — Relay & Loox Link Abuse Hardening / Client Admission

**From:** Vaultify app team
**To:** Loox backend team (`workers/loox-link`, `workers/loox-relay`)
**Date:** 2026-07-06
**Status:** Sent to BE. **BE responded 260707 with corrections** — see `plans/reports/app-team-response-260707-0903-relay-assertion-destination-verification-plan.md`. Follows the client-authenticity audit (`plans/reports/analysis-260706-2208-loox-api-abuse-client-authenticity-report.md`).

> **⚠️ Corrections after BE review (2026-07-07) — this proposal was wrong on 2 points:**
> 1. **B1 / Q4 relay transcript:** the proposed new `LOOX-RELAY-ASSERTION-V1` (method/path/challengeID) does **not** exist and is **retracted**. BE relay App Attest reuses the command transcript directly: `clientDataHash = SHA256(LOOX-RELAY-AUTHZ-V1 command bytes)`, no challenge, freshness = nonce + `sign_count` CAS. Relay App Attest **backend is already built** (`ASSERTION_MODE=off`) — not "awaiting a draft" (Q1 wrong); waiting on iOS assertion + parity fixture.
> 2. **B2 destination:** no longer deferrable. `FORWARD_MODE=send` is live + `rotateDestination` accepts arbitrary destinations with no ownership check → ATTACK-R02 is real now. Elevated to P0 as **DEC-DST-01** (destination ownership verification). See the response doc.

---

## 0. TL;DR

The client crypto/authorization layer is complete and byte-parity tested. The **admission boundary is not**. A custom client that understands the public protocol can today self-mint a Relay Principal and consume paid backend resources without being a legitimate Loox app instance, because relay admission relies only on a self-consistent P256 key + signature. This proposal closes that boundary.

**The central question is not "can someone read HTTPS?" — it is "can someone who understands our public protocol build a valid custom client and consume paid backend resources without being an authorized Loox app instance?"**

Locked priorities:

```
P0-1  Loox Link transcript V2 — bind one_time (before enabling required mode)
P0-2  Relay App Attest admission
P0-3  Multi-dimensional abuse budgets
P1    shadow → required rollout + remove interim static token
P2    certificate/SPKI pinning — DEFERRED (intentional; ATS default stands)
```

---

## 1. Current state (what the client already provides)

Backend can rely on these being live and tested client-side:

- **Relay Principal (P256).** Per-command ECDSA-P256/SHA-256 signature over canonical transcript `LOOX-RELAY-AUTHZ-V1` (magic frozen — **do not rename**). Command kinds 1–6: `createAlias, disableAlias, rotateDestination, deleteAlias, disableAll, rotatePrincipal`. Wire body: `principal_id, epoch, nonce (16B), issued_at_unix_ms, kind, signature, genesis_public_key`. Frozen vectors: `VaultifyTests/Fixtures/relay-authz-command-vectors-v1.json` (backend MUST reproduce byte-for-byte; signatures not frozen — ECDSA non-deterministic).
- **Relay data plane is deployed and working** (createAlias/mint/provisioning, INV-PE02 `backendMinted`, G1–G6 merged). What is missing is the **App Attest admission layer only** — do not conflate the two.
- **Loox Link App Attest client** is live in **shadow** mode (`attestationEnabled=true, attestationRequired=false`). Register + assertion verified on real device (`challenges 201 → register 204 → create 201 + assertion`). Transcript `LOOX-APP-ATTEST-CREATE-SHARE-V1` binds ciphertext hash + iv + cryptoVersion + expiry + envelope — **but NOT `one_time`**.
- **Retry hygiene:** every attempt fetches a fresh single-use challenge; nonce/challenge/signature never reused. Relay retry rebuilds on `nonce_replay`, refreshes on `epoch_stale`.
- **Abuse-signal inputs already sent:** App Attest key ID, principal ID, epoch, operation kind. (App can add app-version / protocol-version headers on request.)
- **Interim auth:** `X-Loox-App-Token` — CI-injected, rotatable, ships in Release IPA. **Treat as public-to-determined-attacker, NOT a durable secret.**
- **No TLS pinning** (ATS default only). **No AutoFill-extension network mutations** (local-first).

---

## 2. Threat model (unchanged, restated for BE)

Assume the attacker can inspect the binary, endpoints, JSON fields, transcript structure, timing; run on jailbroken devices; hook before TLS; dump request bodies; **extract any static secret shipped in the app**; write a custom non-Loox client; rotate IPs; generate many local keypairs; replay captured requests unless the protocol prevents it. Do not assume undocumented APIs or HTTPS provide admission control.

Layer model — **no layer replaces another**:

```
TLS/ATS → (optional pinning) → App Attest (app-instance admission)
        → Relay Principal signature (logical authorization)
        → nonce/challenge/epoch/sign_count (replay)
        → backend abuse budgets (IP/device/principal/destination/storage)
```

---

## 3. Admission invariant (the core requirement)

```
INV-ADM-01
An unknown Relay Principal MUST NOT be admitted solely by presenting a
self-consistent public key and signature.

Genesis:
  Unknown Principal
      → valid principal signature?      (proves key ownership only)
      → valid App Attest admission?      (proves legitimate app instance)
          no  → REJECT
          yes → REGISTER principal atomically
```

**Nuance — App Attest is not genesis-only.** If only the first create is attested, an attacker who obtains one admitted principal can automate 1000 `createAlias`. Therefore App Attest assertion is REQUIRED on genesis **and** on every resource-consuming / security-sensitive mutation. Minimum set: `createAlias, rotateDestination, rotatePrincipal, disableAll`. `disableAlias / deleteAlias` are debatable, but the app team leans toward protecting **all** mutations for a consistent contract.

---

## 4. Workstreams

### B0 — Loox Link Transcript V2 (P0-1, independent, do first)

Smallest P0. Ship before enabling required mode anywhere.

Required order (do not reorder):

1. Freeze V2 field list — must include `one_time` and every other security-relevant field.
2. Production TS canonical encoder (single source).
3. Frozen vectors generator **imports the production encoder** — no independent re-implementation.
4. Emit frozen vectors → app updates Swift `LooxLinkCanonical` to V2 + asserts byte/hash parity.
5. Tamper/mutation tests: flipping `one_time` (true↔false) MUST change the asserted transcript hash.
6. V1 compatibility strategy (accept V1 while shadow; require V2 before `ASSERTION_MODE=required`).

Hard rule: **never enable required before V2 exists.** V1's `one_time` is unauthenticated → burn-after-read integrity is currently forgeable (ATTACK-S02).

### B1 — Relay App Attest Admission (P0-2)

Backend deliverables:

- Attestation **challenge** endpoint for relay (single-use, TTL, atomic consume).
- **Registration** flow (attestation key store, appIdHash validation against AASA).
- **Assertion verification** on protected relay mutations.
- **commandHash binding:** assertion MUST bind the exact relay command, not just host/path/method.

New transcript (separate from `LOOX-RELAY-AUTHZ-V1`, which stays as-is):

```
LOOX-RELAY-ASSERTION-V1 =
  MAGIC ‖ method ‖ normalizedPath ‖ challengeID ‖ SHA256(canonicalRelayCommandBytes)

clientDataHash = SHA256(canonicalAssertionTranscriptBytes)
```

Two layers bind the **same** command:

```
canonicalRelayCommandBytes
    ├── P256 principal signature        (logical authorization)
    └── SHA256(...) → App Attest assertion (app-instance admission)
```

Genesis order (client → backend; backend order optimizable, semantics must match):

```
Backend verify:
  1. challenge valid + unused
  2. App Attest assertion valid
  3. appIdHash valid
  4. sign_count CAS valid (monotonic)
  5. commandHash matches request body
  6. principal signature valid
  7. unknown-principal genesis rules valid
  8. abuse budgets permit
  9. register principal atomically
 10. create alias
```

### B2 — Multi-dimensional Abuse Budgets (P0-3)

Not IP-only. Rate keys:

**Private Email (relay):** per IP · per App Attest key · per Relay Principal · **per destination HMAC** · per operation kind · global.

**Share Link:** per IP · per App Attest key · per create velocity · per ciphertext bytes · per active links.

Destination-level control closes ATTACK-R02 (100 principals all forwarding to one victim, bypassing per-principal caps) **without** storing plaintext:

```
destination_rate_key = HMAC(serverRateKey, normalize(destination))
budget = new alias bindings per destination per time window
```

Do NOT require the app to send for analytics: Persona, bound domain, Login Item, alias label, or destination plaintext beyond the actual relay operation requirement.

### B3 — Required-mode Cutover (P1)

Loox Link: `shadow → required → remove interim token`.
Relay: `off → shadow → required`.

Token cutover (keep overlap to reduce rollback risk):

```
Stage A: token required + App Attest shadow
Stage B: token required + App Attest required     ← overlap
Stage C: App Attest required + token ignored server-side
Stage D: token removed from new app builds
```

Each stage needs metrics + rollback. Client flips `attestationRequired` / relay mode flags in lockstep with server `ASSERTION_MODE`.

---

## 5. Replay enforcement (restate — must be proven server-side)

The client generating a fresh nonce does **not** by itself prevent replay. Per service, backend MUST prove:

- **Loox Link:** challenge single-use + `sign_count` CAS (already demonstrated).
- **Relay:** nonce uniqueness scope, challenge/nonce TTL, atomic consume, race behavior under concurrent replays.

Do not mark "replay solved" from client contract alone.

---

## 6. Not in scope / not a bug (avoid scope creep)

- **Share Link revoke without App Attest.** If the revoke token is a high-entropy bearer capability, "possession = authority to revoke" is acceptable. Audit its entropy/scope/storage/one-link-only/rotation/leak semantics separately — do NOT force App Attest just for uniformity.
- **AutoFill extension.** Stays local-first, no relay network mutations. Only reopen App-Attest-in-extension feasibility if "Create Private Email inside extension" is ever pursued.

---

## 7. Acceptance criteria

1. Unknown Relay Principal genesis is rejected without a valid App Attest admission (INV-ADM-01).
2. App Attest assertion binds the exact relay commandHash on genesis + all resource-consuming mutations.
3. Loox Link transcript V2 binds `one_time`; flipping it changes the hash; parity frozen byte-for-byte with app.
4. Frozen-vector generators import the production encoders (no independent re-impl).
5. Replay enforcement proven server-side per service (atomic nonce/challenge consume + sign_count CAS).
6. Multi-dimensional budgets live, including per-destination HMAC.
7. Cutover staged with metrics + rollback; interim token demoted to throttle, then removed.
8. Core Vault and each optional capability degrade independently — no global `backendAvailable=false`.

---

## 8. Appendix — App-side responsibilities (for BE visibility of the split)

App team owns these; most are gated on BE contract freeze:

| Item | App work | Gate |
|---|---|---|
| B0 Loox V2 | Add `one_time`+missing fields to `LooxLinkCanonical`, bump magic, update frozen vectors + mutation tests, flip create→V2 | After BE freezes V2 field list + emits vectors |
| B1 Relay App Attest client | Fetch relay challenge, build `LOOX-RELAY-ASSERTION-V1`, `generateAssertion`, send `X-Loox-*` headers, genesis requires assertion, error mapping | After BE freezes challenge/register/assert contract |
| B3 cutover | Flip `attestationRequired` (loox) + relay mode in lockstep with server; later remove interim token from build | Lockstep with BE mode switch |
| B2 signals | Optionally add app-version / protocol-version headers | On BE request (trivial) |
| P1 enum | App Attest state boolean → enum (`unsupported/needsRegistration/registered/temporarilyUnavailable/needsRepair`) + capability UX | App-autonomous, non-blocker |

**Nothing meaningful ships app-side before BE freezes contracts, except the P1 enum.**

---

## 9. Open questions for BE

1. B1 relay App Attest — is a challenge/register/assert contract being drafted? Client has headers deferred and ready.
2. B0 V2 — confirm the full V2 field list (beyond `one_time`) so app parity is done once.
3. Per-destination HMAC budget — confirm `serverRateKey` scope + `normalize(destination)` rules so app expectations match.
4. Naming: keep `LOOX-RELAY-AUTHZ-V1` (authorization) and add `LOOX-RELAY-ASSERTION-V1` (attest). Confirm alignment — the earlier proposal's "LOOX-RELAY-COMMAND-V1" does not exist in code.
5. Replay scope for relay nonce (per-principal? global? TTL?) — needed to finalize acceptance criteria.
