# Backend Go-Live Work Order — Relay App Attest + Destination Verification + Abuse Ceilings

**From:** Vaultify app team
**To:** Loox backend (`workers/loox-relay`, `workers/loox-link`)
**Date:** 2026-07-07
**Prereq shipped:** iOS **Phase A** (relay App Attest assertion) is implemented, compiled, and unit-tested (branch `feat/relay-app-attest-assertion`; full suite 324/324). The relay assertion parity is frozen. This is the work order to turn everything live.

---

## 0. State now

- **Relay App Attest client is done.** Protected relay mutations register the device key with loox-relay (`POST /v1/relay/attestation/register`) and send `X-Loox-App-Attest-Key-Id` + `X-Loox-App-Attest-Assertion`, binding `clientDataHash = SHA256(LOOX-RELAY-AUTHZ-V1 command bytes)`. Shadow-safe (`attestationEnabled=true`, `attestationRequired=false`). Awaiting real-device QA (user).
- **Relay/Private Email data plane is live** (`FORWARD_MODE=send`), forwarding to arbitrary per-alias destinations with **no ownership check** — the open abuse surface.
- **Loox Link** App Attest in shadow; `one_time` still unbound in the V1 assertion transcript.

---

## 1. Enable NOW (no further app dependency)

### 1.1 Relay App Attest → shadow
Flip `ASSERTION_MODE=off → shadow` on loox-relay (staging + prod). Verify + log only; principal signature stays live auth. Gives observability before `required`.

**Relay parity check (do this to unlock `required`).** For each frozen command vector, `SHA256(relayCommandTranscript(command))` must equal the iOS-frozen `client_data_hash_hex` (fixture `VaultifyTests/Fixtures/relay-authz-command-vectors-v1.json`):

| command (epoch) | clientDataHash (SHA256 of canonical bytes) |
|---|---|
| createAlias (1) | `5aaf72694ffc0b8c9c74339bad103ced345b1a7739ec5de07c7fdbd4d18b2a8b` |
| disableAlias (2) | `a26357df672de242e5416c298bbfc11fc3f40b84b7a2a1c302597ae985361da6` |
| rotateDestination (3, dest `me@x.com`) | `7eab24871f69c404ebca9a4e9e9a0376a802df8a13daccff4f7245acec9be51e` |
| deleteAlias (4) | `396dca6391db098f6d450c43c265249d0d191f86e4e0f2f4bab5458735ada788` |
| disableAll (5) | `b29e2ab6baf5e98407835c3872eb03faa557f7956b657a1504c7993f124c8de6` |
| rotatePrincipal (6, newKey 0x33×65) | `e620da3c42bb5ebc67653d1dcc7a72da9acc7ba143002cce6e5d62ff7b689245` |

(Fixed inputs: principalID `0x11×32`, nonce `0x22×16`, issuedAtUnixMs `1760000000000`.) A backend test importing the production encoder should reproduce these 6 hashes.

### 1.2 Multi-dimensional abuse ceilings (P0 — abuse is live today)
`FORWARD_MODE=send` + arbitrary destinations ⟹ N self-signed principals can all forward to one victim, burning `relay.looxpassword.com` sending reputation + Email Sending quota + bill. Ingress currently caps only `alias_in` + `sender_domain`. Add:

- **Per-destination budget:** `destination_rate_key = HMAC(serverRateKey, normalize(destination))` — new alias bindings + inbound forward volume per destination per window. Closes the amplification-at-a-victim vector without plaintext analytics.
- **Global outbound send ceiling:** protect the sending domain reputation + Email Sending quota + bill.
- Return **429** with problem+json `code` + `Retry-After` (app maps it to the existing capability/breaker taxonomy — please confirm the exact shape).

---

## 2. Build for go-live (BE greenfield → then app follows)

### 2.1 DEC-DST-01 — Destination ownership verification
Third auth layer (App Attest = app instance · Principal = command authz · **Destination = inbox consent**).

- **Table `verified_destinations`**: `destination_id, principal_id, destination_hash = HMAC(lookupKey, normalizedEmail), destination_enc (AEAD), dest_key_version, status (PENDING|VERIFIED|REVOKED), verified_at, created_at, updated_at`; `UNIQUE(principal_id, destination_hash)` (NOT global).
- **Command kind 7 `beginDestinationVerification`** (principal-signed; App Attest per rollout) → `POST /v1/relay/destinations` → `{destination_id, status:"pending", masked_email, resend_after_seconds}`.
- **Verify flow (scanner-safe):** send confirm email → `GET verify.looxpassword.com/email/<token>` renders a page, **does NOT consume** → explicit **POST confirm** atomically consumes → `VERIFIED`. Token: 256-bit, `SHA256`-stored, single-use, 15–30 min TTL, purpose-bound. Web POST is authoritative; app never self-confirms.
- **Routing switch (INV-DST-01):** `createAlias`/`rotateDestination` bind a verified `destination_id`, not plaintext email → an alias MUST NOT forward to a non-`VERIFIED` destination of the same principal.
- **Lifecycle:** verification survives principal epoch rotation (`principal_id` stable); Erase Vault `disableAll` → destinations `REVOKED` + plaintext scrubbed.
- **Verification-endpoint limits:** per principal / App Attest key / destination HMAC / IP; resend ≥60s cooldown, exponential. Anti-phishing copy ("Someone requested to use this email…confirm only if it was you"), never "Verify your Loox account".
- **Host:** provision `verify.looxpassword.com` + publish AASA for the Universal Link (app needs it for the deep-link entitlement).

### 2.2 Loox Link `one_time` transcript V2
`create-assertion.ts canonicalRequestHash` omits `one_time` though `shares.ts` sends it (ATTACK-S02). Freeze V2 field list (current hashed body **+ `one_time`** + any other security-relevant field) → production TS encoder → generator **imports** it → emit frozen vectors. App then updates `LooxLinkCanonical` V1→V2, mutation-tests that flipping `one_time` changes the hash, and flips link `shadow→required`. **Never enable required before V2 exists.**

---

## 3. Go-live sequence

1. **Now:** relay `off→shadow` (§1.1) + abuse ceilings live (§1.2). Confirm the 6 relay clientDataHash parity values.
2. **Relay required:** after parity confirmed + real-device QA → app flips `attestationRequired` in lockstep with `ASSERTION_MODE=required`.
3. **DEC-DST-01:** BE ships `verified_destinations` + kind-7 + verify host → app ships Phase B (destination_id routing + verify UX). Migration decision needed (§4).
4. **Loox V2:** BE field list + vectors → app parity → flip link required.
5. **Token cutover (loox-link):** `token required + attest shadow → +attest required (overlap) → attest required + token ignored → drop token from app build`.

## 4. BE must confirm (blocks app Phase B/C)

1. Kind-7 `beginDestinationVerification` lives in the same `LOOX-RELAY-AUTHZ-V1` encoder family (enum 1..6 → 1..7)? App freezes a matching vector; BE reproduce byte-for-byte.
2. Live-alias migration under current `send` mode: **grandfather existing destinations as VERIFIED** (app preference — avoids breaking active forwarding) vs force re-verify?
3. 429 problem+json `code` + `Retry-After` shape for the new ceilings.
4. Loox V2 complete field list (beyond `one_time`).
5. `verify.looxpassword.com` AASA `appID` (team `WDNL2F75V7`, bundle `com.bervion.vaultify`) for the app entitlement.

## 5. Acceptance (whole abuse-hardening live)

- Relay: unknown-principal genesis + resource mutations require a valid App Attest assertion (`required`); the 6 clientDataHash parity values match.
- Destination: no alias forwards to a non-`VERIFIED` destination; verification is backend-authoritative + scanner-safe.
- Ceilings: per-destination + global outbound live; 429 taxonomy wired.
- Loox: `one_time` bound in V2; link `required`; interim token dropped.
- Core Vault + each capability degrade independently (no global `backendAvailable=false`).
