# Multi-Domain Proposal — `loox.pw` (+ future domains) for Share Links, Private Email, Deep Links

> **⚠️ SUPERSEDED (architecture) by V2:** `plans/reports/proposal-260707-2003-multi-domain-v2-signed-registry-authz-v2.md`.
> The **current-state audit (§1) still stands** and is referenced by V2. Three V1 architecture calls were reversed after security review: (1) domain choice must be **signed** (Relay AUTHZ V2), not server-recorded; (2) the domain registry must be **authenticated**, not an unsigned `/v1/domains`; (3) cross-account has a **third option** (thin ingress adapter) — Option B is not forced. See V2.

**Date:** 2026-07-07 · **Status:** V1 — audit valid, architecture superseded by V2 · **Scope:** iOS `Vaultify` + `workers/{loox-link,loox-relay,loox-config}`
**Goal:** add `loox.pw` as a second user-selectable domain for Share Links + Private Email aliases, architected so more domains can be added later, plus generalize in-app deep links across domains/features.
**Primary domain today:** `looxpassword.com`. **New domain:** `loox.pw` (currently shared to a **different** Cloudflare account — Edwardph0713@gmail.com).

---

## 0. TL;DR — is it easy?

| Surface | Difficulty | Why |
|---|---|---|
| **Share Link** second domain | 🟢 Easy | shareId is opaque; no identity coupling to domain. Config + new viewer host/route + one constant. |
| **Private Email** second domain | 🟠 Moderate–Hard | Alias identity is `HMAC(localPart)` **globally UNIQUE, no domain column** → needs a D1 schema change + a sealed per-alias domain field on iOS. |
| **Cross-account infra** (`loox.pw` on Edwardph0713's account) | 🔴 Hard / structural | Email Routing + D1 + Workers are per-account. This — not code — is the dominant cost. |
| **Deep links** across domains/features | 🟠 Moderate | Infra already exists (invite Universal Link + URL schemes); generalize to a path-router + per-host AASA + `applinks` entries. |
| **Signed crypto contracts** | 🟢 None | Neither the relay command nor the App-Attest transcript embeds a host/domain → **no parity-vector break** (as long as domain stays server-recorded, not signed). |

**The one decision that dominates everything (§2): keep `loox.pw` on the separate account (full 2nd deployment) vs. move the `loox.pw` zone into the primary Cloudflare account (then it's ≈ config).** Strong recommendation: **consolidate the zone into the primary account** for the email/relay plane.

---

## 1. Current-state audit (facts, `file:line`)

### 1.1 iOS host constants (shallow — ~6 spots)
- `Vaultify/Features/Sharing/LooxLink/LooxLinkConfig.swift:11-15` — share API + viewer bases (`api[-staging].looxpassword.com`, `s[-staging].looxpassword.com`), DEBUG-overridable via UserDefaults.
- `VaultifyCore/Relay/RelayConfig.swift:15-18` — `apiBaseURL`, `stagingAPIBaseURL`, **`emailDomain = "relay.looxpassword.com"`** (single alias mail domain).
- `Vaultify/Services/Capabilities/CapabilityManifestClient.swift:13` — `config.looxpassword.com/v1/capabilities`.
- `Vaultify/Services/Sharing/InviteLinkService.swift:38` — `host = "invite.looxpassword.com"` (invite Universal Link mint + match).
- `Vaultify/Vaultify.entitlements:10-13` — Associated Domains = only `applinks:invite.looxpassword.com`.
- App Attest appID = `WDNL2F75V7.com.bervion.vaultify` (`Project.swift:23,45`) — **host-independent**.

### 1.2 Alias address model — domain is GLOBAL, not per-alias
- `VaultifyCore/Models/EmailAlias.swift` — `EmailAlias`/`EmailAliasSecret` store **only `localPart`**; no domain field (sealed schema is growable via `decodeIfPresent`).
- `VaultifyCore/Models/AliasAddress.swift:11-15` — `display(localPart:relayDomain:…)` takes domain as a **param**, but all 6 call sites pass the single `RelayConfig.emailDomain` (`AliasDetailScreen`, `PersonaAliasesScreen`, `ItemEditorScreen ×2`, `AffectedAccountsScreen`, `VaultRepository+AliasWriteback`).

### 1.3 Backend alias identity — no domain, collides across domains
- `loox-relay/src/aliases.ts:60-61` — full email = `${localPart}@${parseRelayDomains(env.RELAY_DOMAINS)[0]}` (first entry = primary; domain derived from env, **not stored**).
- `loox-relay/src/alias-crypto.ts:40-50` — `alias_hash = HMAC(normalizedLocalPart)`; **domain not in the hash**.
- `loox-relay/migrations/0001_init.sql` — aliases table: `alias_hash UNIQUE`, `principal_id`, `destination_ciphertext`, `status`, `env` — **no domain column** (old site-domain col dropped in `0003`).
- `loox-relay/src/ingress.ts:37` — inbound lookup `WHERE alias_hash = ? AND env = ?` **ignores recipient domain** → `x@loox.pw` and `x@looxpassword.com` collide to one row.

### 1.4 Backend hosts are env-driven (good)
- `loox-relay/wrangler.jsonc` — `RELAY_DOMAINS` (comma-list), `RELAY_SENDER`, `VERIFY_LINK_BASE`, routes `api-relay.*` + `verify.*` (custom_domain). Ingress via **zone-wide Email Routing catch-all → `email()` handler** (`index.ts:6`, guard `ingress.ts:58-65`).
- `loox-link/wrangler.jsonc` — routes `s.*` (viewer), `api.*`.
- `loox-config/wrangler.jsonc` — route `config.*`.
- **All 3 workers hardcode `account_id = f318e1b1…`** (`wrangler.jsonc:8`). `envFromHost` infers env from the `-staging` substring (`attest-challenge.ts:20-22`).

### 1.5 Signed contracts do NOT contain a domain
- Relay command `LOOX-RELAY-AUTHZ-V1` (`relay-command.ts:49-62` / `RelayCommandCanonical.swift:19-32`): kind, principalID, epoch, nonce, issuedAt, aliasID(local-part), destination, newPublicKey. **No domain.**
- App-Attest `LOOX-APP-ATTEST-CREATE-SHARE-V2`: method, path, challengeId, ciphertextHash, iv, cryptoVersion, expires, envelope, oneTime. **No host.**
- Capability manifest `LOOX-CAP-MANIFEST-V1` signs capability names/policies/ops only — **no hosts**.
- → Adding a domain touches **zero** frozen parity vectors, provided the domain choice is server-recorded (not signed).

### 1.6 Deep-link infra already exists
- URL schemes (`Project.swift:80-92`): `otpauth://` (TOTP import), `vaultify://` (AutoFill hand-off) → `VaultifyApp.swift:72-82 onOpenURL`.
- Universal Link: `invite.looxpassword.com/i/<token>#k=<key>` → scene delegate → `InviteLinkService.acceptInvite` (cold-launch buffered). Host match hardcoded (`InviteLinkService.swift:103`).
- Verify host AASA: served by `loox-relay/src/verify-host.ts:47-48` (`appID: EXPECTED_APP_ID, paths: ['/email/*']`). Share viewer `s.looxpassword.com` is **web-only** (not an applink).

---

## 2. The crux: cross-account (`loox.pw` on Edwardph0713's account)

Cloudflare **Email Routing, D1, and Worker routes are per-account.** A zone on account B cannot route inbound mail into a Worker deployed on account A, and account A's D1 (aliases, principals, attested keys) is unreachable from B.

**Option A — Move the `loox.pw` zone into the primary account `f318e1b1…` (RECOMMENDED).**
Then a second domain is mostly **config**: add `loox.pw` to `RELAY_DOMAINS` + a viewer route `s.loox.pw` + `verify.loox.pw` custom_domain + Email Routing catch-all on the moved zone + one D1 schema change. One deployment, one trust store, one D1. Zones are movable between accounts (Cloudflare dashboard) as long as you control both.

**Option B — Keep `loox.pw` on Edwardph0713's account (full 2nd deployment).**
Requires, in that account: a Worker deployment of loox-relay/loox-link (or zone-scoped), its own D1 (⇒ **duplicated principal + App-Attest trust state** — a principal/attest key registered on account A is unknown to account B), its own Email Routing + MX, its own `verify.loox.pw` + AASA. Cross-account = 2× the operational surface + a split identity plane. Only worth it if there is a hard ownership/billing reason to keep the zone separate.

**Recommendation:** For the **email/relay** plane, use **Option A** (consolidate the zone). Share Links are stateless (opaque IDs, no principal/D1 identity) so they *could* live cross-account more cheaply, but keeping everything on one account is simplest. If the zone must stay on Edwardph0713's account, treat `loox.pw` email as a **separate relay instance** (its own D1/principals) — users on `loox.pw` won't share alias/principal state with `looxpassword.com`.

---

## 3. Target architecture (extensible to N domains)

### 3.1 Domain registry (single source of truth)
Introduce a small **domain descriptor** list instead of scattering hosts:
```
Domain {
  id            // opaque stable key, e.g. "lpw", "lxpw"
  displayName   // "looxpassword.com", "loox.pw"
  aliasDomain   // "relay.looxpassword.com" | "relay.loox.pw"
  viewerHost    // "s.looxpassword.com"     | "s.loox.pw"
  verifyHost    // "verify.looxpassword.com"| "verify.loox.pw"
  capabilities  // which features this domain offers: [shareLink, privateEmail]
  isDefault     // one default
}
```
- **Backend source of truth**, published to the client. Cleanest near-term: a small **unsigned** `GET /v1/domains` (loox-config) — domains are not security-sensitive (they're public hostnames + a namespace choice). Avoids bumping the signed capability manifest. (If we later want domains authenticated, add to `LOOX-CAP-MANIFEST-V1` with a `schema_version` bump.)
- **iOS**: bundle a fallback registry (so the app works offline / first-launch) + refresh from `/v1/domains`. Replace the ~6 hardcoded constants with lookups keyed by `domain.id`.

### 3.2 Alias identity gains a domain
- **D1**: add `relay_domain TEXT NOT NULL DEFAULT '<primary>'` to `aliases`; change uniqueness to `UNIQUE(relay_domain, alias_hash)` (or a `domain_id`); include domain in `createAliasOp` return + `ingress` lookup (`WHERE alias_hash=? AND relay_domain=? AND env=?`). Migration backfills existing rows to the primary domain.
- **iOS**: add sealed `relayDomainId` (opaque) to `EmailAliasSecret` (`decodeIfPresent` → default primary, back-compat). Thread it through `AliasAddress.display` (replace the global `RelayConfig.emailDomain`). Alias picker offers domains where `capabilities` includes `privateEmail`.
- **Signed or not?** The alias's domain choice should be **server-recorded, NOT signed** in V1: it's the user's own alias, not a consent boundary (unlike the forwarding destination). This keeps `LOOX-RELAY-AUTHZ-V1` frozen (no new vectors). `createAlias` gains an unsigned `relay_domain` request field validated server-side against the registry. (A signed variant is a future option → transcript V2 both sides.)
- **Namespace decision** (§7): is `alice@looxpassword.com` distinct from `alice@loox.pw` (independent namespaces, `UNIQUE(domain, hash)`) or one shared namespace? Independent is the natural user expectation and what the schema above assumes.

### 3.3 Share links per domain
- `shareId` is opaque + content key is fragment-only → **no identity coupling.** Create response returns the domain-scoped viewer URL; client picks the create host per selected domain. On the moved-zone/primary account this is `s.loox.pw` route + a registry entry. Lowest-risk surface → ship first.

### 3.4 Deep-link generalization
- **Unify** `applinks:` to a host list: `invite.looxpassword.com`, `s.looxpassword.com`(if opened-in-app), `verify.looxpassword.com`, plus the `loox.pw` equivalents.
- **Path router**: one entry point that dispatches by path, not host — `/i/*` invite, `/s/*` share-open-in-app, `/email/*` verify, extensible for future features. Replaces the host-hardcoded `InviteLinkService.isInviteLink` match.
- **AASA** served per host with the same `appID` (verify host already does via `verify-host.ts:47`; add for the new hosts). Associated Domains entitlement lists all hosts (requires portal capability already enabled + provisioning regen — same infra note as prior DEC-DST-01 B2).
- Decide whether share-viewer links become Universal Links (open in app) or stay web-only.

---

## 4. Signed-contract impact — NONE (if domain unsigned)
No change to `LOOX-RELAY-AUTHZ-V1`, `LOOX-APP-ATTEST-CREATE-SHARE-V2`, or `LOOX-CAP-MANIFEST-V1`. App Attest rpId = appID (host-independent) → new domain needs no attestation change. **Only caveat:** any new host MUST follow the `-staging` naming convention so `envFromHost` classifies it correctly (prod host has no `-staging`; staging host contains `-staging`).

---

## 5. Phased plan
- **Phase 0 — Decision + provisioning.** Resolve §2 (account) + §7 questions. Provision `loox.pw`: DNS, Email Routing catch-all (if email), `s.loox.pw` / `verify.loox.pw` hosts, AASA, App-Attest host naming. Move zone into primary account if Option A.
- **Phase 1 — Domain registry + Share Link 2nd domain.** `GET /v1/domains` (unsigned) + iOS registry (replace constants) + `loox.pw` share route + domain picker in the share sheet. Low risk, ships value first.
- **Phase 2 — Private Email 2nd domain.** D1 migration (`relay_domain` col + composite UNIQUE + ingress/lookup/createAlias) + iOS sealed `relayDomainId` + alias-creation domain picker. Backfill primary. (Only meaningful if the account/infra decision supports `loox.pw` email.)
- **Phase 3 — Deep-link generalization.** Path router + multi-host `applinks` + AASA per host + entitlement/provisioning. (Infra-gated like DEC-DST-01 B2.)
- **Phase 4 (optional) — fold domain list into signed manifest** if domains ever need to be authenticated.

## 6. Effort estimate (relative)
- Share Link multi-domain: **S** (config + route + picker).
- Domain registry + iOS de-hardcode: **M**.
- Private Email multi-domain: **M** code (schema + sealed field + picker) + **L** infra if cross-account (Option B).
- Deep-link generalization: **M** (+ portal/provisioning for Associated Domains).

## 7. Open questions / decisions (need owner)
1. **Account (dominant):** move `loox.pw` zone into the primary Cloudflare account (Option A, recommended) or keep it on Edwardph0713's account with a separate relay/D1 deployment (Option B)?
2. **Which features on `loox.pw`:** share links only, or private email too (email = the heavy path), or verify host too?
3. **Alias namespace:** independent per domain (`alice@looxpassword.com` ≠ `alice@loox.pw`, `UNIQUE(domain, hash)`) — assumed — or one shared namespace?
4. **Domain choice signed?** Recommend **server-recorded/unsigned** in V1 (no parity bump). Confirm acceptable, or require signing (→ transcript V2 both sides).
5. **Share-viewer Universal Links:** should `s.<domain>/s/…` open in-app (needs AASA + applinks) or stay web-only (today)?
6. **Host naming:** confirm `loox.pw` prod + a `-staging`-named staging host so `envFromHost` classifies correctly.
7. **Default domain + migration:** existing aliases/share links stay on `looxpassword.com`; is `loox.pw` opt-in per new item (assumed), and is there a per-persona default?

---

## 8. Bottom line
Adding `loox.pw` is **not** blocked by the crypto/signed layer (clean — no parity impact) and the host coupling is shallow (env + ~6 iOS constants → a domain registry). The real work is (a) the **cross-account decision** and (b) the **alias-identity schema change** for email. Share links + a domain registry can ship quickly and independently; private email is the heavier lift and hinges on the account decision. Recommend: **Option A (consolidate zone)** + **Phase 1 first (registry + share-link `loox.pw`)**, then email, then deep-link generalization.
