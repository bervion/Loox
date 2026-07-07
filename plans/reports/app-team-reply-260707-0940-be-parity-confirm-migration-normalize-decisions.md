# App-Team Reply → BE — Parity Confirmed, Owner Decisions (Migration + Normalize)

**From:** Vaultify app team · **To:** Loox backend · **Date:** 2026-07-07
**Re:** BE parity confirmation + answers to §4. Two owner decisions locked below.

---

## 1. Green-light — go ahead NOW

Relay parity confirmed both sides (6/6 clientDataHash byte-for-byte). **Proceed immediately with:**
- `ASSERTION_MODE=off → shadow` (relay, staging + prod).
- Per-destination HMAC budget + global outbound ceiling + **global createAlias/day ceiling** (accepted — closes mass-mint while relay is still shadow).
- 429 → `application/problem+json` upgrade (accepted).

**Interim posture (agreed):** relay `required` + ceilings is strong enough temporarily (kills "N self-signed principals → 1 victim"); DEC-DST-01 is the durable inbox-consent fix. No need to lock `rotateDestination` before DEC-DST-01 ships — required + ceilings cover the gap.

Relay `→ required` after: real-device QA (owner) + client build flips `attestationRequired` in lockstep.

## 2. Answers accepted (§4 Q1–Q5)

- **Q1 kind-7 same encoder family** ✅ — app will freeze one kind-7 vector after BE extends `KINDS`→`[1..7]` + enum + required-field rule (`destination` required, `alias=null`) + `OPERATION_BY_KIND[7]='mutate'` + handler. App reproduces byte-for-byte.
- **Q3 429 shape** ✅ accepted as proposed (`type/code/capability/retry_after_seconds` + `Retry-After` + `X-Loox-Service-State`). **App follow-up (small):** route 429 as a transient "too many requests, honor Retry-After" — surfaced gently, **not** tripping the operator breaker (a rate-limit ≠ maintenance state). Will wire when the shape is live.
- **Q4 Loox V2** ✅ — only `one_time` missing. V2 = bump MAGIC `…CREATE-SHARE-V1`→`-V2`, append `byte(one_time?1:0)` at the end. BE generator imports encoder → emit vectors → app updates `LooxLinkCanonical` + mutation test + flip link required.
- **Q5 AASA appID** ✅ `WDNL2F75V7.com.bervion.vaultify`.

## 3. Owner decisions (locked 2026-07-07)

### DEC-MIG — Migration: **force re-verify all** (NOT grandfather)
Owner chose the strict trust model. When DEC-DST-01 + INV-DST-01 go live, every existing destination starts **unverified/PENDING**; forwarding is gated until the owner re-confirms each via the email link. Accepted trade-off: live forwarding (incl. owner's own inbox) pauses briefly until re-confirmed — blast radius is tiny and the clean trust model is preferred over convenience. So BE does **no** grandfather-snapshot; app surfaces a "re-confirm your forwarding email" state for existing inboxes.

### DEC-DST-NORM-01 — Provider-aware normalization, **backend-authoritative** (app does NOT mirror)

Correction to the poll option name: not "Gmail-family". It means **conservative baseline for every provider, plus provider-specific rules only where semantics are documented and frozen** (V1 = `gmail.com` only). Do NOT generic-strip dots/`+tag` or lowercase local-part for unknown providers — `john.smith@fastmail.com` ≠ `johnsmith@fastmail.com`, and Fastmail/Proton/custom-domain semantics differ. No MX-heuristic to guess provider (a Google Workspace custom domain doesn't inherit consumer-Gmail dot rules) — explicit destination-domain allowlist only.

**Key architecture change: the client MUST NOT normalize the abuse-budget identity.** App sends the **exact** user-entered destination; the backend is the single authority for abuse normalization. This removes the app↔BE parity surface entirely (no shared normalize spec, no shared vectors) — one less parity-sensitive protocol.

```
INV-DST-N01  Provider-aware normalization for abuse prevention MUST be
             server-authoritative. The client MUST NOT supply or sign a
             pre-normalized budget identity — it signs the exact destination.
```

**Three separate identities (do NOT collapse into one function):**

| Identity | Derivation | Used for |
|---|---|---|
| **A. Delivery address** | exact, as entered (`u.s.e.r+github@gmail.com`) | send verify mail + forward mail |
| **B. Exact verified-lookup** | conservative exact-normalize (trim, domain-lowercase, IDN) — **no** dot/`+tag` collapse | `verified_destinations` lookup + dedupe; keeps `user+work@` and `user+private@` as **distinct** inboxes/labels |
| **C. Abuse-budget grouping** | baseline **+ provider-specific collapse (gmail.com V1: strip dots, drop `+tag`)** | per-destination rate/amplification limits |

So two hashes, two dedicated keys (both domain-separated from `ALIAS_HMAC_KEY_CURRENT`):
```
destination_exact_hash  = HMAC(k1, exact-normalized)       # B: verify/lookup
destination_budget_hash = HMAC(k2, abuse-budget-identity)  # C: rate limits
# Gmail example — input u.s.e.r+foo@gmail.com:
#   exact_hash  = HMAC(k1, "u.s.e.r+foo@gmail.com")
#   budget_hash = HMAC(k2, "user@gmail.com")
```
Provider registry V1: `gmail.com` (documented dot-insensitivity + `+tag`); `googlemail.com` only if the team freezes the mapping. Everything else (Fastmail, Proton, Outlook, iCloud, custom domains) = baseline only, extensible later via a **versioned** provider registry. IDN/punycode = out of V1 (ASCII).

**App side:** sends exact destination in the kind-7 `beginDestinationVerification` signed command; stores only the opaque `relayDestinationID` + `verificationStatus` returned by BE. Any local email normalization the app does is conservative dedupe/UX only and is **never** a security boundary. BE freezes its own abuse-budget test vectors (app does not reproduce them).

## 4. Sequencing recap

1. **BE now:** relay off→shadow (parity green) + per-destination/global-outbound/global-create ceilings + 429→problem+json.
2. **Owner:** real-device QA → app flips `attestationRequired` with BE `ASSERTION_MODE=required` (interim protection complete).
3. **DEC-DST-01:** BE builds `verified_destinations` (exact-hash + budget-hash, two keys) + kind-7 + verify host, re-verify migration (DEC-MIG), server-authoritative normalization (DEC-DST-NORM-01) → app Phase B (opaque `destination_id` routing + re-confirm UX; app sends exact destination, computes no hashes).
4. **Loox V2:** BE field list frozen (`+one_time`) + vectors → app Phase C parity → flip link required → token cutover.

## Open questions
None outstanding on the app side. Abuse-budget normalization is fully BE-owned (DEC-DST-NORM-01) — no shared normalize spec/vectors needed. BE to confirm the two-key / three-identity model + the V1 `gmail.com`-only provider registry.
