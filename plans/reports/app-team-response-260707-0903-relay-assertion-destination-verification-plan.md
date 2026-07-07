# App-Team Response + Plan — Relay Assertion Parity, Destination Ownership (DEC-DST-01), one_time V2

**From:** Vaultify app team
**To:** Loox backend
**Date:** 2026-07-07
**Re:** BE response to app-team proposal (`plans/reports/backend-proposal-260706-2223-relay-loox-abuse-hardening.md`) — accepting C1/C2 corrections + DEC-DST-01.

---

## 1. Corrections accepted

### C1 — Relay assertion reuses `LOOX-RELAY-AUTHZ-V1`. We retract `LOOX-RELAY-ASSERTION-V1`.

Confirmed against BE code: `command-assertion.ts:46` `clientDataHash = SHA-256(relayCommandTranscript(command))`; freshness = nonce single-use + `sign_count` CAS (`:71`); no challenge, no method/path. Our proposal's separate assertion transcript is dropped.

**App will build:** `DCAppAttestService.generateAssertion(keyId, clientDataHash: SHA256(canonical LOOX-RELAY-AUTHZ-V1 command bytes))` reusing the **existing frozen command encoder** (`VaultifyCore/Relay/RelayCommandCanonical.swift`), send `X-Loox-App-Attest-Key-Id` + `X-Loox-App-Attest-Assertion` on protected relay mutations, freeze a relay-assertion parity fixture. Understood: **BE relay App Attest is already done** (`ASSERTION_MODE=off`) — no BE contract wait; unblock = iOS assertion + fixture, then BE flips `off→shadow→required`.

### C2 — Destination gap accepted as real P0.

Agreed: `FORWARD_MODE=send` live + `rotateDestination` arbitrary + no per-destination/global cap ⟹ ATTACK-R02 real even against non-consenting victims, and abusable from a genuine app instance (App Attest doesn't cover destination consent).

---

## 2. DEC-DST-01 — app understanding + what we'll build

Accepted as-specified. Maps cleanly onto our shipped `VaultForwardingInbox` (0..N multi-inbox, `VaultForwardingInbox` CK type, G2). App does **not** self-confirm — backend-authoritative token consume is the source of truth; app only observes state.

App-side deltas:

- **`VaultForwardingInbox`** gains `verificationStatus` (`unverified/pending/verified/expired/revoked`) + opaque `relayDestinationID`. Sealed record still holds email/label/Persona prefs (BE never sees Persona).
- **Kind-7 `beginDestinationVerification`** client: extend `RelayCommandKind` 1..6 → 1..7, add to canonical encoder + frozen vectors, `RelayService` builds/signs/sends, App Attest per rollout mode.
- **`destination_id` routing (INV-DST-01):** create/rotate now bind a verified `destination_id`, not plaintext email. Removes plaintext email from the signed transcript on rotate.
- **Verify-pending UX:** "Add inbox → sending link → Check your inbox (masked)" → poll status on `scenePhase active`; refresh button = **"Check Verification"** (never "I Confirmed"). Universal Link (`verify.looxpassword.com`) opens app as UX-only; app still drives explicit POST-confirm.
- **Lifecycle:** verification survives principal epoch rotation (`principalID` stable via `RelayPrincipalIdentity.rotated()`); Erase Vault → after `disableAll`, destinations revoked (app already gates offline erase on active aliases).

---

## 3. App implementation plan (phases)

| Phase | Scope | Depends on |
|---|---|---|
| **A — Relay assertion parity** | assertion over `SHA256(AUTHZ-V1)`, headers, relay-assertion parity fixture, error mapping | none (BE done) → unblocks relay `shadow→required` |
| **B — Destination verification client** | kind-7 command + canonical/vectors, `destination_id` routing, `VaultForwardingInbox.verificationStatus`+`relayDestinationID`, verify-pending UX, poll, revoke-on-erase | BE ships `verified_destinations` + kind-7 + landing/confirm endpoints + `verify.looxpassword.com` AASA |
| **C — Loox one_time V2** | add `one_time`+fields to `LooxLinkCanonical`, bump magic, regen frozen vectors + mutation test, flip create→V2 | BE freezes V2 field list + emits vectors |
| **D — Cutover** | flip `attestationRequired`/relay mode lockstep with `ASSERTION_MODE`; handle **429**; drop interim `X-Loox-App-Token` from build | lockstep with BE |
| **P1 (anytime)** | App Attest state boolean → 5-case enum; add `app-version`/`protocol-version` headers | none |

Can start **now, no BE dependency:** Phase A (relay assertion + fixture) and the P1 enum. Phase A is the highest-leverage app item — it's the only thing blocking relay `shadow→required`.

---

## 4. App-side answers + questions back to BE

**Answers (app owns):**
- `VaultForwardingInbox` already multi-inbox — no product regression to support 0..N. ✅
- App will treat destination verification as backend-authoritative; no self-confirm command. ✅
- 429 on create/rotateDestination: app will handle gracefully via existing `CapabilityCircuitBreaker` + surface localized "Too many requests, try later" (needs Retry-After contract, see below).

**Questions to BE:**
1. **Kind-7 transcript family** — confirm `beginDestinationVerification` lives in the same `LOOX-RELAY-AUTHZ-V1` encoder (enum extends to 7) so principal sig + App Attest reuse the existing byte layout. We'll add the frozen vector; please reproduce byte-for-byte.
2. **Migration for live aliases** — aliases already forwarding under old plaintext `rotateDestination`: force re-verify, or grandfather existing destinations as VERIFIED? Affects users live on `send` mode now. (App preference: grandfather existing as VERIFIED to avoid breaking active forwarding, new binds require verified `destination_id`.)
3. **`verify.looxpassword.com`** — confirm host + provide AASA so we can register the Universal Link + `applinks` entitlement (needs `tuist generate` + entitlements update on both bundle IDs).
4. **429 contract** — confirm problem+json code + `Retry-After` header shape for the new per-destination/global ceiling, so app maps it to the existing capability/breaker taxonomy (not a hard error).
5. **B0 Loox V2 field list** — send the complete V2 field set (beyond `one_time`) so Swift parity is one-shot.

---

## 5. Acknowledged BE-now items (no app dependency)

Per-destination HMAC budget + global outbound ceiling **enabled now**; relay `off→shadow` now for observability; `verified_destinations` + kind-7 + landing/confirm endpoints. App will begin Phase A + P1 in parallel and pick up Phase B as endpoints land.
