# Loox Quick View — Backend Proposal
## Rendezvous sessions + blind mailbox for one-shot browser handoff

**Date:** 2026-07-08 · **Status:** Direction APPROVED by owner (review 260708, ~8.5/10); this revision incorporates the owner's P0/P1 corrections. Contract freezes (B3) remain the first deliverable and must reflect them.
**Audience:** Backend team (Cloudflare workers, config plane, web `/open` page)
**Companion:** `proposal-260708-1016-loox-quick-view-app-team.md` (protocol rationale, reuse map, invariants INV-QV-01…17)

---

## 0. What the backend is — and is not

```text
IS:      rendezvous (session create/resolve/bind) + BLIND one-shot mailbox for one
         ciphertext + signed session envelopes + rate limiting + capability state
IS NOT:  an authority over vault/item/field selection. There is NO endpoint that
         names a vault_id/item_id/field path. Browser owns an empty receive
         session; only the app writes one encrypted payload into it.
```

Server never sees plaintext fields, item titles (inside ciphertext), or browser private keys.
Compromise of the mailbox yields ciphertexts bound to ephemeral keys that died with browser tabs.

## B1 — Session service

**Recommended: one Durable Object per session** (single-writer state machine, no CAS races, TTL alarm
for GC). D1 only if a lightweight audit/counters table is wanted; KV is not suitable (no atomicity).

```text
states: CREATED → APPROVED(payload stored, atomic claim) → CONSUMED
                  ↘ EXPIRED (TTL alarm from any pre-CONSUMED state)
```

(Owner P0-2: the former exclusive `BOUND` state is REMOVED — an attacker who photographs/CCTVs the
QR must not be able to dead-lock a session by binding first. Bind is advisory metadata on the DO,
not a state; **the one-winner point is the first cryptographically valid approval upload**, which
atomically transitions CREATED→APPROVED. Everything after a claim — second upload, foreign upload —
gets the same generic failure.)

- `session_id` = 256-bit random. TTL **180 s** from create to approval-upload; payload TTL **90 s**
  from upload to consume (unconsumed → purge). All timers server-side; browser UI shows countdown.
- **Keys immutable after create** (INV-QV-01): no update/PATCH surface exists at all.
- **Advisory bind** (app scan/enter): records `{bound_at, attest_key_dim?}` for browser "phone
  connected" UI + telemetry only; repeatable; never consulted for authorization; never blocks approval.
- One approval per session (INV-QV-10/16): `APPROVED` rejects any further upload; `CONSUMED` terminal.

## B2 — Endpoints (canonical host only, e.g. `api.looxpassword.com/v1/quick-view/…`)

```text
POST /sessions            browser: {enc_pub, sig_pub, browser_nonce, protocol_version}
                          → {signed_session_envelope, human_code, sas_inputs, poll/SSE ref}
POST /sessions/resolve    app: {code} in BODY (owner P1-3: never a GET query — codes must not land
                          in access logs/browser history/proxy traces) → signed_session_envelope.
                          Rate-budgeted (B4); logging = path+status only, never the body.
POST /sessions/{id}/bind  app: ADVISORY (browser UI signal + telemetry; App Attest shadow + rate
                          budget; never exclusive, never authorization)
POST /sessions/{id}/payload
                          app: {ciphertext, app_eph_pub, aad_fields…} + X-Loox-App-Attest-* trio
                          over LOOX-APP-ATTEST-QUICK-VIEW-V1 (B5). Size cap ≈ 16 KB.
                          FIRST VALID UPLOAD ATOMICALLY CLAIMS THE SESSION (CREATED→APPROVED).
POST /sessions/{id}/challenge → {challenge}          browser PoP step 1
POST /sessions/{id}/consume   {challenge_sig}        browser PoP step 2: verify sig with sig_pub
                          → ciphertext envelope; ATOMIC transition APPROVED→CONSUMED (DO single-writer)
GET  /sessions/{id}/events    SSE "payload ready" (or long-poll fallback) — signaling only,
                          NEVER authorization (INV: socket says ready; PoP still required to read)
```

Failure discipline: unknown/expired/consumed/bound-elsewhere are **indistinguishable** to both sides
(same status + generic code). Path+status logging only — same policy as loox-link.

## B3 — Frozen contract artifacts (deliverable #1, before any client code)

Same governance as DEC-03/shorten: **BE owns canonical encoders; generators IMPORT the production
encoder; frozen JSON vectors; app/web parity sign-off byte-for-byte.**

```text
1. LOOX-QUICK-VIEW-SESSION-V1   signed session envelope (P256, same trust root as
   cap-manifest/domain-registry — distinct MAGIC, registry-style key_id):
   magic ‖ version ‖ session_id ‖ enc_key_hash ‖ sig_key_hash ‖ browser_nonce ‖
   server_nonce ‖ issued_at ‖ expires_at ‖ env       (env INSIDE signed payload, like registry)
2. LOOX-QUICK-VIEW-PAYLOAD-V1   KDF/AEAD transcript + AAD (owner P0-1 — KDF context must be as
   rich as the AAD, INV-QV-18):
   kdf_transcript = "LOOX-QUICK-VIEW-KDF-V1" ‖ version ‖ session_id ‖ browser_enc_key_hash ‖
                    browser_sig_key_hash ‖ app_eph_pub_hash ‖ env
   ECDH P-256(app_eph, browser_enc) → HKDF-Extract(salt = SHA256(kdf_transcript))
   → HKDF-Expand(info = magic ‖ version ‖ role-label) → AES-256-GCM;
   AAD = magic ‖ session_id ‖ enc_key_hash ‖ approval_id ‖ field_manifest_hash ‖
   issued_at ‖ expires_at              (WebCrypto-native by design — no ChaCha/HPKE)
3. LOOX-QUICK-VIEW-POP-V1       browser proof-of-possession (owner P1-2 — unified rich transcript;
   guards challenge mix-up, cross-env replay, reuse, endpoint/operation confusion):
   magic ‖ version ‖ operation("consume") ‖ session_id ‖ challenge_id ‖ challenge ‖
   sig_key_hash ‖ issued_at ‖ expires_at ‖ env — signed with ephemeral P-256 ECDSA key.
   Challenge single-use, consumed on successful verify.
4. LOOX-APP-ATTEST-QUICK-VIEW-V1  upload assertion binding (owner P0 fix #4 — prove the EXACT
   upload, not just its context): u16len(method) ‖ u16len(path) ‖ u16len(challengeId) ‖
   u16len(session_id) ‖ SHA256(canonicalUploadBody) — where canonicalUploadBody covers the AAD
   bytes, ciphertext, and app_eph_pub in a frozen serialization (endpoint path pinned by the
   transcript, as with shorten-link).
5. SAS derivation: words(HKDF("LOOX-QV-SAS-V1", session_id ‖ enc_key_hash ‖ sig_key_hash));
   wordlist + truncation frozen in the same doc (browser and app compute independently —
   server never picks the phrase).
```

Vector sets: golden + mutation pairs per artifact (session/browser/approval/field-manifest swaps),
lowercase-method normalization, env cross-replay rejection.

## B4 — Human code

- Crockford-style alphabet minus `0O1IL`, 8 chars + checksum char, format `XXXX-XXXX`. TTL = session TTL.
- Budgets: per-IP, per-code-prefix, per-session, global circuit; constant-shape 404 on miss
  (exists/expired/foreign indistinguishable). Code maps → session envelope only — it is a locator,
  never key material (INV-QV-07); brute force yields a ciphertext-less session someone else owns.

## B5 — Assertion ladder & abuse

- `QUICK_VIEW_ASSERTION_MODE off → shadow → required`, independent ladder (per-surface, as with
  create-share/shorten). Challenge consumed on successful verify (adopt the shorten rule).
- Mint/resolve budgets: sessions per IP/hour; binds per session (1); uploads per session (1);
  consume attempts per session (small); SSE connection caps.
- CI guard: payload handler rejects any body smelling like plaintext fields (defense-in-depth assert:
  reject if decrypted-looking JSON keys `username|password` appear un-encrypted — cheap tripwire).

## B6 — Web `/open` page (canonical domain only)

- Static, self-contained: **no third-party JS/analytics/tag-manager/CDN**, strict CSP
  (`default-src 'none'`-style + `frame-ancestors 'none'` — the page must never be iframe-embeddable —
  + Trusted Types where supported), `Cache-Control: no-store`, no service-worker caching,
  no IndexedDB/localStorage of anything session-related.
- Hardened headers (owner addition): `Cross-Origin-Opener-Policy: same-origin`,
  `Cross-Origin-Embedder-Policy: require-corp`, `Cross-Origin-Resource-Policy: same-origin`,
  `Referrer-Policy: no-referrer`, restrictive `Permissions-Policy`, `X-Frame-Options: DENY`
  (legacy backstop for frame-ancestors).
- WebCrypto: ephemeral P-256 ECDH (`extractable:false`) + P-256 ECDSA sig key; keys and decrypted
  fields live in tab memory only; render TTL 5 min max, auto-lock after 2 min tab-hidden
  (owner-locked); `[Close & Clear]`; copy action shows "copied to THIS computer's clipboard" warning.
- Reuse the s.looxpassword.com viewer's envelope rendering (payload plaintext = `LooxLinkEnvelope`
  JSON schema: label/value/concealed/kind, ordered).
- SAS phrase + human code + QR (the signed envelope) + expiry countdown; SSE/poll state updates.

## B7 — Capability + config plane

- New `quick_view` capability in the signed manifest + `X-Loox-Service-State` on the worker
  (`/v1/quick-view/service-state`); message keys `quick_view_maintenance|disabled|retired`.
- Feature is optional-network by definition: outage never touches the core vault; app breaker wiring
  already exists.

## B8 — Rollout

```text
1. Freeze B3 artifacts + vectors  → GATE QV-1 (unblocks app QV-A1)
2. Worker + /open staging (dark; service-state disabled)
3. App QV-A2/A3 integration on staging; adversarial matrix QV-A4
4. Browser matrix QA (QV-A5) → assertion shadow → enable prod (manifest flip)
5. required ladder after shadow verdicts are clean
```

## Owner decision log (review 260708 — supersedes the original open questions)

- **Suite:** P-256 ECDH + HKDF-SHA256 + AES-256-GCM; no hand-rolled JS HPKE. KDF transcript per P0-1.
- **State machine:** Durable Object per session; states CREATED→APPROVED→CONSUMED→EXPIRED;
  bind = advisory metadata (P0-2); first valid approval upload wins.
- **PoP:** unified rich transcript (B3 item 3), challenge consumed on verify.
- **Upload assertion:** binds `SHA256(canonicalUploadBody)` (P0 fix #4).
- **Resolve:** POST body only (P1-3); path+status logging.
- **TTLs:** 180 s pre-approval / 90 s post-upload / 5 min render / 2 min hidden auto-lock.
- **Signal:** SSE primary, long-poll fallback — signaling only, never authorization.
- **Bind attest:** shadow + rate budgets from day one; not hard-required.
- **Hosting:** dedicated `quick-view` worker (independent capability, ladder, CSP, DO, blast radius).
- **SAS:** derived, 2 words + 2 digits, human confirmation signal; app hard-blocks on mismatch.

## Unresolved questions

1. **QR payload density benchmark (pre-freeze):** variant A = full signed envelope in QR
   (offline-verifiable) vs variant B = compact locator + signed digest (app fetches envelope).
   Decide by real-device scan reliability; outcome shapes `LOOX-QUICK-VIEW-SESSION-V1` and whether
   the code path and QR path share one envelope-delivery route.
2. SAS wordlist (source, 2048 EN words assumed) — freeze with the SAS spec.
3. `canonicalUploadBody` exact serialization (field order/encoding) — BE encoder decision inside the
   B3 freeze; generator imports it as usual.
