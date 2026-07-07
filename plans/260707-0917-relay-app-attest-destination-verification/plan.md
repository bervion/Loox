# Relay App Attest + Destination Ownership Verification — Plan

**Created:** 2026-07-07 · **Branch base:** `develop` · **Role:** app team (BE contract received, see reports below)

**Context:**
- Audit: `plans/reports/analysis-260706-2208-loox-api-abuse-client-authenticity-report.md`
- App proposal (2 points corrected by BE): `plans/reports/backend-proposal-260706-2223-relay-loox-abuse-hardening.md`
- BE response + app plan: `plans/reports/app-team-response-260707-0903-relay-assertion-destination-verification-plan.md`

**Goal:** close the relay admission boundary (App Attest on relay) + add destination-ownership verification, without breaking Core Vault or coupling capabilities.

---

## Phases

| # | Phase | File | BE dependency | Status |
|---|-------|------|---------------|--------|
| **A** | Relay App Attest assertion (iOS) | `phase-a-relay-app-attest-assertion.md` | **none** — BE endpoints live (`ASSERTION_MODE=off`) | ✅ Done (branch `feat/relay-app-attest-assertion`, 324/324) — device QA + BE parity pending |
| B | Destination ownership verification client | `phase-b-destination-verification.md` | BE DEC-DST-01 live | ✅ B1 done (PR #62 kind-7, #63 client, 325/325). B2 (Universal Link entitlement) deferred — owner portal action |
| C | Loox Link `one_time` transcript V2 | (gated — outline below) | **hard** — BE freezes V2 field list + vectors | Blocked on BE |
| D | Required-mode cutover + drop interim token | (gated — outline below) | lockstep with BE mode switch | Blocked on A–C |
| P1 | App Attest state enum + abuse-signal headers | folded into A | none | Ready (non-blocker) |

**Start now (no BE dep):** Phase A + P1. Phase A is highest leverage — the only thing blocking relay `shadow→required`.

---

## Validation status (done 2026-07-07)

Verified in code (iOS + BE), so the plan rests on facts not assumptions:

- ✅ BE relay App Attest is built: `POST /v1/relay/attestation/challenges`, `POST /v1/relay/attestation/register` (returns 204), `verifyCommandAssertion` gated by `ASSERTION_MODE` (`control-handlers.ts:127-135`). iOS is the missing half.
- ✅ Assertion `clientDataHash = SHA256(relayCommandTranscript)` (`command-assertion.ts:46`); **no per-command challenge** — challenge consumed at register only; freshness = nonce single-use (`consumeNonce` `control-handlers.ts:138`) + `sign_count` CAS.
- ✅ App Attest **key reusable across backends, but register is per-backend** — loox-relay has its own `attest_keys`/`attest_challenges` D1 (relay needs its own register + registered-flag).
- ✅ `RelayAPIClient` has **no header hooks** today (principal-sig only, sig in JSON body) — assertion headers are net-new plumbing.
- ✅ Assertion gate applies to **all control mutations**; sending `X-Loox-App-Attest-Key-Id` also feeds rate dimension `device` (`control-handlers.ts:123-124`).
- ✅ Destination is **plaintext** in signed kind-3 (`RelayCommand.destination: String`); `ForwardingInbox` has no `destinationId`/status; verified_destinations + kind-7 = greenfield both sides.

**Still to validate — with BE (blocks B/C/D, not A):**
1. Kind-7 `beginDestinationVerification` in the same `LOOX-RELAY-AUTHZ-V1` encoder family? (enum 1..6 → 1..7)
2. Live-alias migration: grandfather existing destinations as VERIFIED vs force re-verify?
3. `verify.looxpassword.com` host + AASA for Universal Link.
4. 429 problem+json + `Retry-After` shape for per-destination/global ceiling.
5. Loox V2 full field list (beyond `one_time`).

**Device QA (both A and B):** real device only (sim lacks DeviceCheck + CloudKit escrow) — one happy-path run each, mirroring loox-link.

---

## Gated phase outlines (fleshed into phase files once BE unblocks)

### Phase B — Destination ownership verification (client)
- `ForwardingInbox` + `ForwardingInboxSecret`: add `verificationStatus` (`unverified/pending/verified/expired/revoked`) + opaque `relayDestinationID`. New sealed columns → **bump `updatedAt` on change** (LWW gate) + CloudKit schema note.
- `RelayCommandKind` 1..6 → add `beginDestinationVerification = 7`; extend canonical encoder + frozen vectors (byte-parity with BE).
- Routing switch: `createAlias`/`rotateDestination` bind a verified `relayDestinationID`, **not** plaintext email (INV-DST-01). Removes plaintext email from the rotate transcript.
- UX: add-inbox → "sending link" → pending; poll status on `scenePhase active`; button "Check Verification" (never self-confirm); Universal Link opens app → explicit POST-confirm.
- Lifecycle: verification survives epoch rotation (`principalID` stable); Erase Vault revokes destinations (extend existing offline-erase gate).

### Phase C — Loox Link one_time V2
- After BE freezes V2 field list + emits vectors: add `one_time` (+ fields) to `LooxLinkCanonical`, bump magic `…-V1`→`-V2`, regen `app-attest-create-share-vectors` fixture, mutation test (flip `one_time` ⇒ hash changes), route create to V2. Then flip link `shadow→required`.

### Phase D — Cutover
- Relay `off→shadow→required`, Loox `shadow→required`, in lockstep with BE `ASSERTION_MODE`. Handle 429 via `CapabilityCircuitBreaker`. Drop `X-Loox-App-Token` from build after attest `required`.

---

## Risks
- **Apple `attestKey` rate limits** — relay register is one-time per device+env; acceptable. Optional future: consolidate to one shared App Attest key across loox-link + relay to halve attestations.
- **Shadow correctness** — while `ASSERTION_MODE=off/shadow`, a failed/absent assertion must never block a relay mutation (principal sig remains the live auth). Gate all assertion logic behind a client `attestationEnabled` flag mirroring `LooxLinkConfig`.
- **Extension** — relay is never called from AutoFill (local-first); no appex App Attest needed. Do not add DeviceCheck to `VaultifyCore`/appex.
- **B LWW trap** — new sealed `ForwardingInbox` fields dropped on pull unless `updatedAt` bumps (see [[vaultify-sync-lww-updatedat-gate]]).

## Open questions
See "Still to validate — with BE" (5 items). No app-internal blockers for Phase A.
