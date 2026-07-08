# Multi-Domain Proposal **V2** — Signed Domain Registry + Relay AUTHZ V2

**Date:** 2026-07-07 · **Status:** Proposal (pre-implementation), architecture locked after security review
**Supersedes:** V1 (`proposal-260707-1937-…`) on architecture. **V1 §1 current-state audit still holds** and is the factual base for this doc.
**Goal:** add `loox.pw` (+ future domains) as user-selectable domains for Share Links + Private Email, consistent with the signed control-plane + App-Attest architecture already shipped, and generalize deep links.

---

## 0. What changed from V1 (security review)

| V1 said | V2 corrects to |
|---|---|
| `relay_domain` **unsigned**, server-recorded | **Signed** — `domain_id` bound into a new **`LOOX-RELAY-AUTHZ-V2`** transcript (INV-MD-01) |
| `GET /v1/domains` **unsigned** = source of truth | **Signed** `LOOX-DOMAIN-REGISTRY-V1` (reuse cap-manifest machinery) or bundled-allowlist + remote enable-subset (INV-MD-02) |
| Cross-account Option B ⟹ must duplicate D1/principal/attest | **Option C exists**: thin ingress adapter in account B → authenticated bridge to central authority in A (identity plane stays central) |
| "Signed-contract impact **NONE**" | **Per-surface**: alias namespace = V2 required; share presentation host = possibly none; deep-link = not crypto; registry = authenticated |
| One `Domain{aliasDomain,viewerHost,verifyHost}` object | **Split** user-selectable `DomainChoice` (branding) from fixed `ServiceEndpoints` (control-plane API host stays canonical) |
| Migration = ADD COLUMN + composite index | **Table-rebuild** migration (old `UNIQUE(alias_hash)` must be dropped) using `domain_id`, `UNIQUE(env, domain_id, alias_hash)` |
| Path-only deep-link router | **(host, path)** router, fail-closed (INV-DL-01) |
| `envFromHost` "-staging" convention (extend it) | **Explicit host→env map**, unknown → reject (INV-MD-03) |
| "extensible for more domains later" | true for non-applink surfaces; **Universal-link hosts are build-time allowlisted** (Apple entitlement) |
| Share Links "stateless" | "**identity-light**" (still stateful: expiry/one-time/revoke; just not coupled to principal identity) |

---

## 1. Locked decisions (owner, 2026-07-07)

1. **Account:** **Option A — consolidate the `loox.pw` zone into the primary Cloudflare account** (if ownership allows). Document Option C (thin ingress adapter) as fallback; do **not** default to splitting the principal plane.
2. **Features on `loox.pw`:** Share Link **first**; Private Email **after**; verify host only when Private Email on that domain is actually offered. Don't provision everything at once.
3. **Alias namespace:** **independent per domain** — `alice@…looxpassword.com ≠ alice@…loox.pw`. Identity = `UNIQUE(env, domain_id, alias_hash)`.
4. **Domain choice signed?** Private Email = **signed (Relay AUTHZ V2 binds `domain_id`)**, mandatory. Share presentation domain = lighter, but **server-validated** against the trusted registry.
5. **Share-viewer Universal Links:** **V1 stays web-only.** Open-in-app is a later, separate scope (avoid creep).
6. **Host naming / env:** do **not** confirm the substring convention — replace `envFromHost("-staging")` with an explicit trusted host→env mapping (fail closed).
7. **Default + migration:** existing objects stay on `looxpassword.com`; new domain opt-in; precedence item → persona → global → product default; **never migrate an existing alias's address**.

**Still open (product):** apex `alice@loox.pw` vs subdomain `alice@relay.loox.pw` (§8) — affects MX / Email Routing / corporate-mail use; must be decided before provisioning.

---

## 2. Invariants

```
INV-MD-01  Any field that selects the NAMESPACE of a Relay resource (domain_id)
           MUST be cryptographically bound to the authorized command.
INV-MD-02  Remote configuration MUST NOT introduce a new TRUSTED Loox service
           hostname without authenticated policy (signed registry or bundled
           allowlist + remote enable-subset). Unknown host/domain_id → ignore/reject.
INV-MD-03  Environment classification MUST use an explicit trusted host→env map.
           Unknown hosts fail closed.
INV-MD-04  The domain of an ACTIVATED email alias is immutable. Changing domain
           creates a NEW alias relationship (the address is externally different).
INV-DL-01  Deep-link dispatch MUST validate BOTH the trusted host AND the allowed
           path family. A path match on the wrong host does not dispatch.
```

---

## 3. Target architecture

### 3.1 Two layers: `DomainChoice` (branding) vs `ServiceEndpoints` (control plane)
User picking `loox.pw` changes the **address/presentation**, NOT the API control host.
```
DomainChoice {              // user-selectable, from trusted registry
  id                        // opaque stable, e.g. "lp-main", "lp-short"
  aliasAddressDomain        // "relay.looxpassword.com" | "relay.loox.pw" (or apex — §8)
  sharePresentationHost     // "s.looxpassword.com" | "s.loox.pw"
  capabilities              // [share_link, private_email]
  availability              // per-op lifecycle (§3.9)
}
ServiceEndpoints {          // FIXED, canonical — not per branding domain
  relayAPIBase   = api-relay.looxpassword.com
  shareAPIBase   = api.looxpassword.com
  configBase     = config.looxpassword.com
}
```
Benefit: one canonical control-plane host ⇒ minimal cross-host replay surface (§7), no `api.loox.pw` needed. `domain_id` (not raw hostname) is the stable identity token — hosts can migrate/rebrand/retire without rewriting rows.

### 3.2 Signed Domain Registry (`LOOX-DOMAIN-REGISTRY-V1`)
Reuse the **already-shipped** capability-manifest machinery (CanonicalWriter, anti-rollback `registry_version`, expiry, `key_id` pin, bundled fallback) — do not invent new, do not open an unsigned side-door.
```
{ schema_version, registry_version, issued_at, expires_at,
  domains:[ {id, alias_address_domain, share_presentation_host, verify_host,
            capabilities, availability} ],
  key_id, signature }
```
- iOS: **bundled fallback allowlist** (works offline/first-launch) + signed refresh; consume only known `domain_id`s.
- **Lighter V1 acceptable fallback:** bundle `trustedDomains` in-app; remote **unsigned** response only toggles an `enabled_domain_ids` subset of the bundled set (unknown id → ignore) — endpoint compromise can't inject `attacker.example`. Prefer the signed registry since the signed-config stack already exists.

### 3.3 Relay AUTHZ **V2** (binds `domain_id`)
Keep `LOOX-RELAY-AUTHZ-V1` for compatibility. Freeze `LOOX-RELAY-AUTHZ-V2`:
```
magic("LOOX-RELAY-AUTHZ-V2") ‖ version ‖ kind ‖ principal_id ‖ epoch ‖ nonce
  ‖ issued_at ‖ alias_id ‖ domain_id  ← NEW ‖ destination/destination_id ‖ new_public_key
```
Production encoder → frozen vectors → Swift byte-parity (same discipline as the relay/loox vectors). `createAlias` (+ any per-domain op) signs `domain_id`; server verifies + validates it's a create-enabled registry domain. **This is P0 before Private Email multi-domain** (INV-MD-01).

### 3.4 Alias namespace migration (D1 — table rebuild, not ADD COLUMN)
Old `aliases.alias_hash UNIQUE` (globally unique) blocks same-localPart-different-domain, so a plain add-column+index is insufficient in SQLite/D1:
```
CREATE aliases_new( ... , domain_id TEXT NOT NULL, ...,
    UNIQUE(env, domain_id, alias_hash) )
INSERT ... SELECT ..., '<primary domain_id>' FROM aliases   -- backfill
-- recreate indexes → swap
```
Ingress: recipient domain → **exact allowlisted `domain_id`** → localPart hash → composite lookup `WHERE env=? AND domain_id=? AND alias_hash=?`; **unknown domain → reject** (no more collide-to-one-row).

### 3.5 iOS sealed, immutable alias domain
`EmailAliasSecret` gains sealed `relayDomainId` (`decodeIfPresent` → primary legacy). Thread through `AliasAddress.display` (replace the global `RelayConfig.emailDomain`). **Immutable after activation** (INV-MD-04) — no address rewrite.

### 3.6 Share presentation domain (identity-light, ship first)
`shareId` opaque, key fragment-only → not coupled to principal identity (still stateful: expiry/one-time/revoke). Create API stays canonical `api.looxpassword.com`; request carries `presentation_domain_id`; server validates against registry; response returns the `s.<domain>/s/<id>` URL. Lowest risk → Phase 2.

### 3.7 Deep-link (host, path) router
```
DeepLinkRouteKey { trustedHostID, pathKind }
invite host  → /i/*      share viewer host → /s/*      verify host → /email/*
```
- **Preserve scanner-safe verify:** GET renders/validates only; explicit user action → POST confirm → atomic consume. `onOpenURL` MUST NOT auto-consume (regression risk).
- **Universal-link hosts are build-time allowlisted** (Apple Associated Domains entitlement + AASA per host). Registry is runtime-extensible for **non-applink** surfaces (alias address, share presentation); a brand-new UL host needs a new app build + entitlement + AASA.

### 3.8 Explicit host→env map (fix tech debt now)
Replace `envFromHost(host contains "-staging")`:
```
HOST_ENV = { "api-relay.looxpassword.com":"prod", "api-relay-staging.…":"staging",
             "verify.looxpassword.com":"prod", … , loox.pw hosts … }
unknown host → REJECT   // INV-MD-03, fail closed
```

### 3.9 Domain retirement lifecycle
Registry carries per-op availability (mirrors the capability-shutdown architecture):
```
availability { create, existingTraffic, verify }  // active | create_disabled | retiring | retired
```
e.g. `loox.pw` gets pricey → `create_disabled` (existing aliases keep forwarding + warn + migrate) → `retired`. Email domains must never vanish abruptly.

### 3.10 Domain selection UX (no forced picker)
Precedence: **explicit per-item → persona default → global user default → product default.** Inline change when needed; existing objects never migrate. (Persona-level default is natural for Private Email.)

---

## 4. Signed-contract impact — corrected (per surface)

| Surface | Contract impact |
|---|---|
| Relay alias namespace (`domain_id`) | **`LOOX-RELAY-AUTHZ-V2` required** + new frozen vectors (iOS + worker) |
| Share viewer presentation host | Possibly **none** (server-validated `presentation_domain_id`; sign only if share identity must bind it) |
| Domain registry | **New authenticated contract** `LOOX-DOMAIN-REGISTRY-V1` (or bundled-allowlist + enable-subset) |
| Deep-link routing | Not a crypto contract (host+path policy) |
| App Attest | No transcript change (rpId = appID, host-independent) — **but** host is not in the transcript, so multi-host needs a cross-host replay test (§7) |

---

## 5. Cross-account option matrix

| Option | Identity plane | Ops cost | Note |
|---|---|---|---|
| **A. Move `loox.pw` zone → primary account** | central | low | **Recommended.** Then ≈ config: `RELAY_DOMAINS` + routes + Email Routing + one D1 migration |
| B. Full duplicate deployment in account B | split (own D1/principal/attest) | high | strongest isolation; users on `loox.pw` don't share alias/principal state |
| C. Thin ingress adapter in account B | central | medium | account-B Worker receives mail → authenticated bridge (POST raw MIME) → central relay ingestion API in A → central D1 |

Option C feasibility (must benchmark, not Cloudflare-guaranteed): Email Worker gives a `raw` stream — streaming/forwarding cross-account via `fetch()` needs to handle **message size limits, auth of the bridge, and failure/retry semantics**. Cloudflare confirms Workers can call external HTTP and D1 access is per-binding; it does **not** promise turnkey cross-account email ingestion. Recommend **A**; keep **C** documented so B isn't assumed mandatory.

---

## 6. Phases (V2)

- **P0 — Ownership + naming decision.** Account (A/C), apex `@loox.pw` vs `@relay.loox.pw`, independent namespace, default policy.
- **P1 — Trusted Domain Registry.** `LOOX-DOMAIN-REGISTRY-V1` (or bundled+enable-subset) + iOS registry replacing the ~6 constants (split `DomainChoice`/`ServiceEndpoints`). **Also fix `envFromHost` → explicit host→env map.**
- **P2 — Share presentation domain.** `s.loox.pw`; canonical share API; `presentation_domain_id` (server-validated). Ships value early, low risk.
- **P3 — Relay AUTHZ V2.** Freeze transcript binding `domain_id`; production encoder → vectors → Swift parity.
- **P4 — D1 alias namespace migration.** Table rebuild → `UNIQUE(env, domain_id, alias_hash)`; backfill primary; ingress exact-domain lookup; unknown → reject.
- **P5 — iOS sealed alias `relayDomainId`.** `decodeIfPresent` legacy; immutable after activation; domain picker w/ precedence.
- **P6 — Email Routing second domain.** Only after the account decision (A: catch-all on moved zone; C: bridge).
- **P7 — Deep-link host/path matrix.** `(host, path)` router; build-time applinks allowlist; AASA per host; **scanner-safe GET/POST preserved**.
- **P8 — Cross-host adversarial QA** (§7).

---

## 7. Adversarial QA (multi-domain / multi-host)
```
ATTACK-MD-01  Cross-host replay: obtain challenge/assertion for host A → replay the
              same logical request to host B → MUST reject (or prove equivalence is
              intentional). Mandatory because host is NOT in the transcript.
ATTACK-MD-02  Domain mutation: valid signed createAlias with domain_id=A, tamper wire
              to B → MUST fail (V2 binds domain_id) — the whole point of AUTHZ V2.
ATTACK-MD-03  Unknown/attacker registry host or domain_id → ignored/rejected (INV-MD-02).
ATTACK-MD-04  Retired domain create attempt → refused; existing traffic still forwards.
ATTACK-MD-05  Deep-link confusion: verify path on a non-verify host → not dispatched (INV-DL-01);
              GET verify link → renders only, never auto-consumes.
ATTACK-MD-06  Staging/prod host confusion: unknown host → fail closed (INV-MD-03).
```

## 8. Remaining open decisions
1. **`@loox.pw` (apex) vs `@relay.loox.pw` (subdomain)** — apex gives the most brand value for the address but ties up the zone's MX (affects support/security mail + any future website email). Decide before Email Routing provisioning.
2. **Account A vs C** — confirm you can move the `loox.pw` zone into the primary account (A). If ownership forces it to stay separate, C (bridge) keeps the identity plane central; benchmark feasibility first.
3. **Registry: full signed (`LOOX-DOMAIN-REGISTRY-V1`) vs bundled-allowlist + enable-subset** for V1 — recommend signed since the machinery already exists.

## 9. Bottom line
V2 keeps V1's correct core insight (cross-account + alias namespace are the heavy parts, not UI constants) but fixes the security posture: **`domain_id` is signed (AUTHZ V2)**, the **registry is authenticated**, and **branding is decoupled from the control-plane host**. `domain_id` for Private Email is not a UI choice — it selects the namespace of an externally-reachable security resource, so it belongs in the signed command even at the cost of a V2 transcript + new parity vectors. Ship order: registry + host→env fix → share presentation domain → AUTHZ V2 → alias migration → iOS field → email routing → deep-link matrix → adversarial QA.
