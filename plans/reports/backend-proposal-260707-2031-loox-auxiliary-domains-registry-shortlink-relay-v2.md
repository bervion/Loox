# Loox Auxiliary Domains — Backend Proposal

**Date:** 2026-07-07 · **Status:** **SIGNED** — BE reviewed + answered Q1/Q3 (2026-07-07 20:46); both teams cleared to run parallel. Remaining opens are gate-driven, not blocking (see Unresolved questions).
**Audience:** Backend team (loox-relay worker, loox-link worker, config plane, Cloudflare infra)
**Inputs:** app-team proposal (`proposal-260707-2020-…`), A0 code audit (`audit-260707-2020-…`), owner decision session 2026-07-07 20:31
**Companion:** app phases A1/A2/A3/A5 run in parallel; A4 blocked on §B3 freeze.

---

## 0. Locked owner decisions (binding)

```text
DEC-01  No retroactive shortening. Shorten exists only while the
        fragment-bearing CreatedLink is in transient app memory.
DEC-02  App persists short URL WITHOUT fragment only (presentation metadata).
DEC-03  ONE unified LOOX-RELAY-AUTHZ-V2. Backend owns canonical field order +
        production encoder; app parity-signs off; security owner approves the
        semantic field set. No incremental V2a/V2b/V2c.
DEC-04  loox.pw Private Email uses APEX addresses: <localPart>@loox.pw
        (auxiliary namespace, not corporate mail primary).
```

### 0.1 Scope correction on the V2 "conflict" (supersedes audit F2 framing)

A0 audit F2 warned that Persona/Relay V3 also claims `LOOX-RELAY-AUTHZ-V2`. Verified against the V3 docs: **false alarm on the family** — V3's "transcript V2 before `required`" is the **loox-link create-share App Attest assertion transcript** (missing `one_time`; `from-dev-team-to-proposal-author-260706-1223-…:88`), a different MAGIC family. Persona phases add no Relay command fields.

Consequences (DEC-03 process unchanged, inputs simplified):
- Unified `LOOX-RELAY-AUTHZ-V2` field collection = **V1 base + `domain_id`** + only fields backed by a real frozen command contract. No persona fields to merge. No speculative `destination_id`/`public_key`/`service_id`/`persona_id`.
- There are **two independent V2 bumps** in flight, do not conflate:
  1. `LOOX-RELAY-AUTHZ-V2` (relay command transcript, this doc §B3) — adds `domain_id`.
  2. loox-link **create-assertion transcript V2** (App Attest clientData) — adds `one_time`; prerequisite for `ASSERTION_MODE=required` on loox-link; owned by the abuse-hardening workstream, referenced here only where the shorten endpoint touches it (§B6.4).

---

## 1. Invariants (consolidated)

Carry over INV-AD-01…10 and INV-AD-EMAIL-01/02 from the app-team proposal verbatim. New/confirmed:

```text
INV-SHORT-01      A Share Vault link MAY be shortened only while the
                  fragment-bearing CreatedLink remains in transient memory.
                  The app MUST NOT persist the canonical fragment-bearing URL
                  solely to enable retroactive shortening.
INV-SHORT-02      No persistent local model may contain the fragment-bearing
                  canonical Share Vault URL or fragment-bearing short URL.
                  Fragment-bearing URLs are transient session artifacts only.
INV-SHORT-03      Short-link creation MUST NOT require transmitting the URL
                  fragment to backend.
INV-DOM-RESERVED-01  System, abuse, operational, and RFC-relevant local parts
                  MUST be excluded from anonymous alias allocation.
INV-MD-03         Environment classification MUST use an explicit trusted
                  host→env map. Unknown hosts fail closed.
```

---

## B1 — Auxiliary domain registry (`LOOX-DOMAIN-REGISTRY-V1`)

**Trust root — DECIDED (BE, 2026-07-07): same P256 root as the capability manifest** (same private key, same bundled pubkeys → app A1 assumption holds, zero constant changes), with a registry-specific `key_id` label allowed in the keyset, under two mandatory conditions BE set:
1. **Distinct MAGIC** — registry transcript gets its own domain separator; a capability manifest must never verify as a registry or vice versa (manifest signs `raw(MAGIC)‖…‖string(key_id)‖…`, registry follows the same pattern with a different MAGIC).
2. **Independent anti-rollback** — `registry_version` monotonic, fully independent from `manifest_version`.

**MAGIC naming drift to freeze:** app-team proposal §5 wrote `LOOX-AUX-DOMAIN-REGISTRY-V1`; the earlier multi-domain V2 doc and BE's sign-off wrote `LOOX-DOMAIN-REGISTRY-V1`. This doc adopts **`LOOX-DOMAIN-REGISTRY-V1`** (BE owns the signer); the registry contract doc freezes the exact bytes — nobody re-invents the string after that.

**Model: signed registry (Option A).** Reuse the shipped capability-manifest primitives, NOT its semantic transcript:

```text
same:      CanonicalWriter transcript primitives, P256 ECDSA raw-64 signature,
           trusted key set + key_id rotation, verify→cache→apply pipeline,
           silent-failure policy (bad sig/rollback/timeout = keep last good,
           never a policy signal)
different: MAGIC ("LOOX-DOMAIN-REGISTRY-V1"), schema, field list, semantics
```

Payload per app-team proposal §5 Option A: `schema_version`, `registry_version` (anti-rollback, monotonic), `issued_at`/`expires_at`, `key_id`, `domains[]` with `{id, display_name, email_address_domain?, short_link_host?, capabilities[], lifecycle, is_primary_email_choice, is_primary_short_link_choice}`.

Requirements:
- Anti-rollback: reject `registry_version` lower than cached.
- Bundled fallback registry in the app binary (descriptor for `relay.looxpassword.com` legacy + launch-set domains).
- **Env-scoped**: separate staging/prod registries; hosts classified by explicit host→env map (INV-MD-03). A staging registry must not be replayable against prod (env or audience field inside the signed payload).
- Exactly one `is_primary_short_link_choice=true` and one `is_primary_email_choice=true` among `lifecycle=active` — validate at signing time in operator tooling.
- Serve from `config.looxpassword.com` (canonical control plane; auxiliary domains never serve config — INV-AD-02 family).

## B2 — Private Email multi-domain schema (D1)

- Composite identity: `UNIQUE(env, domain_id, alias_hash)`. Audit current schema: if `alias_hash UNIQUE` exists, plan a **table rebuild** migration (D1/SQLite can't drop a UNIQUE constraint in place).
- Backfill: existing rows → `domain_id = 'relay-main'` (legacy `relay.looxpassword.com`).
- New domain = new registry entry + allowlist row, **no schema change** (B5 requirement).
- **DEC-04 apex**: `loox.pw` MX/Email Routing on the apex. Provisioning must include SPF/DKIM/DMARC for the apex and standard mailbox handling for postmaster/abuse per RFC 5321/2142.
- **Reserved local parts (INV-DOM-RESERVED-01)** — reject at alias creation AND at ingress, per domain, minimum set:

```text
postmaster abuse admin administrator root hostmaster webmaster
support security noreply no-reply mailer-daemon info contact
billing legal privacy dmca help sales marketing team hello
```

  Store as data (extensible per domain), not code constants. **Error contract (BE-decided):** reserved local part returns the same indistinguishable `409 alias_exists` as a taken alias — reserved-vs-taken must not be distinguishable (anti-enumeration, consistent with the existing `createAliasOp` "never reveal" invariant). App re-rolls on 409, which is already its behavior — no new error code, no app change.

## B3 — Unified `LOOX-RELAY-AUTHZ-V2` (DEC-03)

**Verified V1 base** (byte-for-byte, `RelayCommandCanonical.swift:14-31`, kinds 1–7):

```text
"LOOX-RELAY-AUTHZ-V1" (raw) ‖ version=1 ‖ kind(u8) ‖ blob(principalID)
‖ u64(epoch) ‖ blob(nonce) ‖ i64(issuedAtUnixMs)
‖ opt-string(aliasID) ‖ opt-string(destination) ‖ opt-blob(newPublicKey)
```

**V2 = V1 semantic base + `opt-string(domainID)`.** Nothing else unless backed by a real frozen command contract (owner rule). Field position: after `aliasID` is recommended (namespace next to resource id), but **backend owns canonical order** — decide once, freeze.

Kind-specific semantics: `domainID` REQUIRED on `createAlias`; MUST match the alias's issued domain (or be absent → legacy) on `disableAlias`/`deleteAlias`/`rotateDestination`; absent on `disableAll`/`rotatePrincipal`. Server rejects mismatches (forbidden-combination matrix).

**Freeze process (no encoder code before step 2 completes):**

```text
collect V2-required fields → freeze one field set (security owner approves)
→ backend production encoder → vector generator IMPORTS production encoder
→ frozen JSON vectors → Swift byte parity + tamper/domain-mutation tests
```

Generator MUST import the production encoder (lesson from the attest-vectors hand-mirror gap, verification report 260706-1223). Deliverable: `relay-authz-v2-contract.md` covering (1) MAGIC bytes (2) version (3) field order (4) encodings (5) optional-presence semantics (6) kind-specific allowed fields (7) forbidden combinations (8) canonical examples (9) tamper matrix (10) V1→V2 compatibility/cutover.

**Cutover:** server accepts V1+V2 during migration; V1 `createAlias` implies `domain_id='relay-main'`; deprecate V1 per-kind once app floor version passes. App Attest layer unchanged: `clientDataHash = SHA256(V2 command bytes)` — same admission mechanism, new bytes.

## B4 — Email ingress routing

```text
recipient localPart@domain
→ domain ∈ allowlisted recipient domains?  no → REJECT (5xx at SMTP edge)
→ domain → domain_id (explicit map, fail closed)
→ localPart ∈ reserved set for domain? → route to operational handling, never alias lookup
→ alias_hash = H(localPart)  → composite lookup (env, domain_id, alias_hash)
→ forward per verified destination policy (existing DEC-DST rules unchanged)
```

Unknown domain/local part: reject; do not create shadow state. Per-domain ingress metrics for lifecycle decisions.

## B5 — Domain lifecycle

States `active | createDisabled | retiring | retired` (per capability: email vs short-link tracked independently). Rules:
- Adding a domain: registry entry + routing allowlist + (email) MX/SPF/DKIM — no schema change.
- `createDisabled`/`retiring`: creation rejected server-side (not just hidden client-side); existing aliases keep forwarding, existing short links keep resolving.
- `retired`: explicit shutdown policy doc required (bounce vs drop for mail; 410 vs redirect for short links). Never silent removal while issued resources exist (INV-AD-08/09).

## B6 — Short-link service

### B6.1 Contract (locked flow)

```text
POST <shorten-endpoint>                         (loox-link worker)
auth: scoped shorten_token (§B6.4 — DECIDED) + standard client authenticity
body: { "share_id": ..., "shorten_token": ... } ← NO URL, NO fragment (INV-SHORT-03)
resp: { "short_url": "https://loox.pw/aB7kQ",   ← fragment-free base (freeze in B6 doc)
        "domain_id": "short-pw",
        "expires_at": <same as share> }
errors: 404 for invalid-token AND nonexistent-share (indistinguishable)
```

Backend selects host from `primaryShortLinkDomainID` (INV-AD-05/06). App composes `short_url + '#' + <opaque original fragment>` in memory only (DEC-01/02). Server stores `shortCode → shareId` (map to canonical path, never a second share object — INV-AD-07).

### B6.2 Resolution

`GET /<code>` on short host → 302 redirect (`Cache-Control: no-store`) to `https://s.looxpassword.com/s/<shareId>` with **no fragment in Location** (browser then re-attaches the request fragment). 302 chosen over 301 (revocation/retirement must not be cached forever) and over 307/308 (no method preservation needed). Fallback if browser QA (app phase A6) finds fragment loss in any target browser: minimal client-side landing page (app-team proposal §14 Option B) — decision gate after A6 matrix.

- Expired/revoked/one-time-consumed share → short link returns the same terminal page as the canonical viewer (redirect anyway and let the viewer render state; simplest, no state duplication).
- Fragment is opaque to backend; QA must cover `#k=…&o=1`, not just `#k=`.

### B6.3 Code + abuse properties

- Short code: ≥6 chars, unambiguous alphabet (no `0O1lI`), CSPRNG, collision = re-roll; enumeration resistance = keyspace ≥ 2^35 vs share count + per-IP resolve rate limits; resolving a nonexistent code = generic 404, constant-time-ish.
- TTL: short link lifetime == share lifetime (no orphans; revoke share ⇒ short link dies with it). No separate revoke surface in V1.
- Mint rate limits per device/attested identity; one short link per shareId (idempotent re-mint returns the same code while valid).
- Logging/analytics/D1/tracing: path+status only, mirroring loox-link client policy (`LooxLinkAPIClient.swift:149`); fragments never arrive by design (B7).

### B6.4 Ownership proof — **DECIDED (BE, 2026-07-07): scoped `shorten_token`**

`revokeToken` rejected: reusing it for shorten silently broadens a destructive capability's scope (every shorten transmits a revoke-capable bearer across one more surface; becomes a cross-service bearer if the shortener later runs as its own worker on the `loox.pw` zone). House pattern is purpose-bound + domain-separated everywhere (per-purpose HMAC keys, per-transcript MAGICs) — shorten follows it.

Mechanics: `createShare` response gains `shorten_token` (32B random, returned once, like `revoke_token`); server stores SHA-256 (one column); shorten endpoint checks the hash. Shares minted before the column exists cannot be shortened — accepted (re-create if needed).

Contract sketch (exact shape frozen in the B6 contract doc): `POST <shorten-endpoint> {share_id, shorten_token}` → `201` / `404` (invalid token vs nonexistent share indistinguishable). **App-side synergy with DEC-01:** `shorten_token` lives ONLY in transient memory alongside `CreatedLink` — never persisted to `LooxLinkRecord` (no retroactive shorten ⇒ no reason to store it; INV-SHORT-01 alignment for free).

For the B6 freeze doc: response should carry the full fragment-free `short_url` + `domain_id` (not a bare `short_id`) so the app never derives the host itself — keeps INV-AD-05/06 mechanical. Also: shorten is a new protected loox-link mutation — extend the create-assertion transcript family once, jointly with the `one_time` V2 bump (§0.1 item 2).

## B7 — Fragment-key security proof

By construction: shorten request carries no URL (B6.1), resolution receives no fragment (HTTP), Location carries none (B6.2). Backend never possesses key material → nothing to scrub from logs/analytics/D1/tracing. CI check: shorten + resolve handlers reject any request body containing `#` or `k=` patterns (defense-in-depth assert, not a parser).

## B8 — Capability degradation

New `short_link` capability in the signed capability manifest + `X-Loox-Service-State`, independent of `share_link` (INV-AD-SHORT-01; app `CapabilityID` gains `.shortLink`). Shortener outage ⇒ share creation unaffected; app shows canonical link + "short links temporarily unavailable".

## B9 — Cross-account domain plan

Locked earlier (multi-domain V2 decision #1): **consolidate the `loox.pw` zone into the primary Cloudflare account**; fallback = thin ingress/edge adapter in account B bridging to central authority (Option C). Do NOT duplicate D1/principal/attest planes. Short-link resolution worker and Email Routing for `loox.pw` deploy in the primary account post-consolidation.

## B10 — Operator controls (all auditable)

```text
add domain · enable capability(domain, email|short_link) · disable new creation
select primary short-link domain · select primary email domain
start retirement · complete retirement (with shutdown policy doc)
edit reserved local-part set · rotate registry signing key
```

Registry signing is an offline/CI ceremony reusing the capability-manifest key-management pattern; every publish bumps `registry_version` and is logged.

---

## Execution & gating

```text
NOW (parallel):   B1 registry + tooling │ B2 schema audit/rebuild plan │ B6 short-link service
                  App A1 (registry client) │ A2 (relayDomainID sealed) │ A3 (UI resolver) │ A5 (shorten UX)
GATE 1:           relay-authz-v2-contract.md freeze (B3) ──→ unblocks App A4 + B2 create-path
GATE 2:           App A6 browser fragment QA matrix ──→ confirms B6.2 redirect vs landing-page fallback
GATE 3:           loox.pw zone consolidation (B9) ──→ unblocks prod DNS/MX/short-host deploys
```

## Acceptance criteria (delta over app-team proposal §30)

1. Registry signed, anti-rollback, env-scoped; unknown domains ignored by construction.
2. `UNIQUE(env, domain_id, alias_hash)` live; legacy rows backfilled `relay-main`; no schema change to add a domain.
3. One frozen `LOOX-RELAY-AUTHZ-V2` contract; generator imports production encoder; Swift parity green incl. domain-mutation tamper tests.
4. Apex `@loox.pw` ingress live with reserved-local-part rejection at create + ingress.
5. Shorten endpoint never receives a URL/fragment; resolve redirects fragment-free; one-time `&o=1` preserved in browser QA matrix.
6. `short_link` capability independently degradable; shortener outage never fails share creation.
7. Old short links survive `primaryShortLinkDomainID` changes; lifecycle transitions audited.

## Decision log (BE sign-off 2026-07-07 20:46)

- ~~Q1~~ **CLOSED**: scoped `shorten_token` (32B, returned once by `createShare`, SHA-256 at rest, 404 indistinguishable). Old shares (pre-column) can't shorten — accepted. See §B6.4.
- ~~Q3~~ **CLOSED**: same P256 root, registry-specific `key_id` label allowed; mandatory distinct MAGIC + independent `registry_version`. See §B1.
- ~~Q4~~ **CLOSED** (contract-wise): reserved local parts return indistinguishable `409 alias_exists`; final word list is a product/legal data pass, not a contract blocker. See §B2.
- **A4 gate confirmed by BE**: contract doc + production encoder + frozen vectors deliverable in one pass (same-day pattern proven on kind-7 and link-V2). Constraint: `LOOX-RELAY-AUTHZ-V1` magic stays frozen; V2 = new magic + dual-accept during the migration window.
- **Q5 bonus (BE note)**: new `loox.pw` zone = its own catch-all slot — also resolves the "one zone, one catch-all" constraint that kept staging ingress dormant.

## Unresolved questions (gate-driven, none blocking parallel start)

1. **B6.2** redirect vs client-side landing page — decided by app A6 browser QA matrix results (Gate 2). BE notes landing page is the zero-ambiguity fallback if the matrix is mixed across browsers/in-app webviews; fragment never reaches the server in either option.
2. `loox.pw` zone ownership/account consolidation timeline (B9) — infra prerequisite for prod only (Gate 3).
3. Freeze-doc leftovers (mechanical, frozen at contract-doc time, no discussion needed): exact registry MAGIC bytes (`LOOX-DOMAIN-REGISTRY-V1` adopted here), exact shorten endpoint path + response shape (`short_url` + `domain_id` recommended over bare `short_id`, INV-AD-05/06).
