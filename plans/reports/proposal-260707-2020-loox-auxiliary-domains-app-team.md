# Loox Auxiliary Domains — App Team Proposal
## Private Email Domain Pool + Backend-Selected Short Links

**Date:** 2026-07-07  
**Status:** Proposed for app-team audit and implementation planning  
**Audience:** iOS app team / AutoFill team  
**Follow-up required:** App team must produce a companion Backend Proposal so app + backend can execute in parallel after contract review  
**Scope:** `Vaultify` iOS client, Private Email UX/model, Share Link post-create short-link UX, trusted auxiliary-domain configuration  
**Primary canonical platform domain:** `looxpassword.com`

---

# 0. Executive decision

This proposal intentionally does **not** make Loox a fully multi-domain platform.

Instead:

```text
looxpassword.com
= permanent canonical product / API / deep-link / share-link domain

Auxiliary domains
= optional resource namespaces used for:
  1. Private Email address diversity
  2. Short-link presentation for existing Share Vault links
```

Examples:

```text
Private Email:
r7k2p9@loox.pw
n4x8qa@future-domain.tld

Canonical Share Vault link:
https://s.looxpassword.com/s/<long-share-id>#k=<fragment-key>

Optional short link:
https://loox.pw/x7Qk2
```

Key product decision:

```text
The app NEVER chooses the short-link domain.

Backend selects the current primary short-link domain.
```

No auxiliary domain is used for:

- API base URLs
- App Attest host identity
- invitation Universal Links
- email-verification Universal Links
- config control plane
- canonical Share Vault storage identity
- generic deep links

Only `looxpassword.com` remains the canonical platform anchor.

---

# 1. Why this narrower architecture is preferred

The previous broad multi-domain proposal coupled:

- Share Link viewer hosts
- Private Email domains
- verify hosts
- deep links
- AASA
- API host selection

That creates unnecessary operational and security surface.

The narrower model recognizes that auxiliary domains provide two concrete user benefits:

## 1.1 Private Email diversity

Users may prefer different anonymous email suffixes:

```text
@relay.looxpassword.com
@loox.pw
@future-domain.tld
```

This improves:

- address variety
- shorter addresses
- aesthetics
- reduced visual uniformity
- optional Persona-level preference later

## 1.2 Share Vault short links

Canonical Share Vault URLs can be long.

A short link provides presentation convenience:

```text
Canonical:
https://s.looxpassword.com/s/<opaque-long-id>#k=<fragment-key>

Short:
https://loox.pw/aB7kQ
```

The short link is not the share object identity.

It is a redirect/presentation layer to the canonical Share Vault URL.

---

# 2. Core invariants

```text
INV-AD-01
looxpassword.com remains the permanent canonical platform domain.

INV-AD-02
Auxiliary domains MUST NOT become API endpoint selectors.

INV-AD-03
Auxiliary domains MUST NOT become dynamic deep-link hosts.

INV-AD-04
Private Email domain choice is an external resource namespace and MUST
be cryptographically bound to the authorized Relay command.

INV-AD-05
The app MUST NOT choose the global short-link domain.

INV-AD-06
Backend selects the active primary short-link domain.

INV-AD-07
A short link MUST resolve to a canonical Share Vault link or canonical
share resource; it MUST NOT become a second independent share object.

INV-AD-08
Existing aliases and issued links MUST NOT silently change domain.

INV-AD-09
Removing a domain from new creation MUST NOT silently delete historical
local records or break existing resources without an explicit retirement plan.

INV-AD-10
Unknown remotely supplied hosts/domains MUST NOT become trusted merely
because a config endpoint returned them.
```

---

# 3. Domain concepts must be separated

Do not create one generic object that mixes:

```text
API host
alias domain
share viewer host
verify host
deep-link host
```

Use narrow domain roles.

Recommended model:

```swift
enum AuxiliaryDomainCapability: String, Codable, Sendable {
    case privateEmail
    case shortLink
}
```

```swift
struct AuxiliaryDomainDescriptor: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let displayName: String

    let emailAddressDomain: String?
    let shortLinkHost: String?

    let capabilities: Set<AuxiliaryDomainCapability>
    let lifecycle: AuxiliaryDomainLifecycle

    let isPrimaryEmailChoice: Bool
    let isPrimaryShortLinkChoice: Bool
}
```

Lifecycle:

```swift
enum AuxiliaryDomainLifecycle: String, Codable, Sendable {
    case active
    case createDisabled
    case retiring
    case retired
}
```

Important:

```text
emailAddressDomain
```

and:

```text
shortLinkHost
```

are separate optional roles.

A domain may support:

```text
privateEmail only
shortLink only
both
```

---

# 4. Primary domain policy

The app bundle must pin the canonical product identity:

```text
looxpassword.com
```

This is not remotely replaceable.

Canonical services remain:

```text
api-relay.looxpassword.com
api.looxpassword.com
s.looxpassword.com
config.looxpassword.com
invite.looxpassword.com
verify.looxpassword.com
```

Auxiliary domains do not replace them.

Remote policy may:

- enable auxiliary domains
- disable creation
- mark retiring
- select current primary short-link domain
- select default email-domain policy

Remote policy must not silently replace:

```text
canonicalPlatformDomain = looxpassword.com
```

---

# 5. Trusted auxiliary-domain registry

The app needs a registry, but it must not trust arbitrary unsigned hosts.

Recommended options, in priority order:

## Option A — Signed registry

Preferred.

Contract concept:

```text
LOOX-AUX-DOMAIN-REGISTRY-V1
```

Example payload:

```json
{
  "schema_version": 1,
  "registry_version": 7,
  "issued_at": 0,
  "expires_at": 0,
  "key_id": "auxdom-2026-01",
  "domains": [
    {
      "id": "main-email",
      "display_name": "Loox Standard",
      "email_address_domain": "relay.looxpassword.com",
      "short_link_host": null,
      "capabilities": ["private_email"],
      "lifecycle": "active",
      "is_primary_email_choice": true,
      "is_primary_short_link_choice": false
    },
    {
      "id": "short-pw",
      "display_name": "Loox Short",
      "email_address_domain": "loox.pw",
      "short_link_host": "loox.pw",
      "capabilities": ["private_email", "short_link"],
      "lifecycle": "active",
      "is_primary_email_choice": false,
      "is_primary_short_link_choice": true
    }
  ],
  "signature": "..."
}
```

Required:

- signature verification
- anti-rollback
- expiry
- key rotation
- bundled fallback

## Option B — Bundled trusted allowlist + remote subset

Acceptable V1 fallback.

The app bundles exact trusted descriptors.

Remote config may only:

- enable known domain IDs
- disable creation
- mark lifecycle
- choose primary short-link domain from known IDs

Unknown remote domain IDs:

```text
IGNORE
```

Remote config must not inject arbitrary hosts.

---

# 6. Private Email architecture

Private Email supports N address namespaces.

Example:

```text
relay-main
→ relay.looxpassword.com

short-pw
→ loox.pw

future-01
→ another-domain.tld
```

## 6.1 Stable domain identity

Store:

```text
relayDomainID
```

not only raw host.

Recommended sealed model addition:

```swift
struct EmailAliasSecret: Codable, Sendable, Equatable {
    // existing fields...

    let relayDomainID: String
}
```

Backward compatibility:

```text
decodeIfPresent(relayDomainID)
  ?? bundledPrimaryLegacyDomainID
```

Existing aliases remain on their original domain.

---

# 7. Email alias domain is immutable after activation

Mandatory:

```text
INV-AD-EMAIL-01

Once an alias is activated, its domain namespace is immutable.
```

Example:

```text
abc@relay.looxpassword.com
```

must not mutate into:

```text
abc@loox.pw
```

Changing domain means creating a new alias relationship.

Reason:

These are different externally reachable email identities.

---

# 8. Private Email domain choice must be signed

The existing Relay command contract reportedly uses:

```text
LOOX-RELAY-AUTHZ-V1
```

Do not add an unsigned request field:

```json
{
  "alias_id": "abc",
  "domain_id": "short-pw"
}
```

while leaving `domain_id` outside authorization.

Recommended:

```text
LOOX-RELAY-AUTHZ-V2
```

binds:

```text
kind
principal_id
epoch
nonce
issued_at_unix_ms
alias_id
domain_id
destination / destination_id where applicable
new_public_key where applicable
public_key where applicable
```

Invariant:

```text
INV-AD-EMAIL-02

Any field selecting the namespace of an externally reachable Relay
resource MUST be cryptographically bound to the authorized command.
```

App team must not implement Private Email multi-domain before V2 parity is frozen.

---

# 9. Private Email UI

Do not force a large picker every time.

Recommended create sheet:

```text
Create Private Email

Address
r7k2p9@loox.pw

Email Domain
Loox Short                           >

Forward to
ch***@gmail.com                       >

[Create Private Email]
```

Domain picker:

```text
Choose Email Domain

● Loox Short
  loox.pw

○ Loox Standard
  relay.looxpassword.com
```

Only show domains:

```text
capability includes privateEmail
AND lifecycle == active
```

---

# 10. Private Email default precedence

Recommended:

```text
explicit selection for current alias
    >
Persona default
    >
global user default
    >
backend/product default
    >
bundled legacy fallback
```

V1 may implement only:

```text
explicit selection
>
global user default
>
product default
```

Persona default can follow later.

Do not migrate existing aliases when default changes.

---

# 11. Domain lifecycle UX for Private Email

## active

- may create new aliases
- existing aliases work

## createDisabled

- do not show for new alias creation
- existing aliases remain visible and usable

## retiring

- no new creation
- existing aliases visible
- show contextual warning
- show linked affected accounts where possible

## retired

- no new creation
- preserve local records/history
- behavior of existing routing follows explicit backend shutdown policy

Never hard-delete a domain record from local history merely because remote registry no longer advertises it.

---

# 12. Short-link architecture

Short links are a separate feature from Share Vault object creation.

Canonical Share Vault flow remains:

```text
Create encrypted Share Vault object
    ↓
Backend returns canonical Share Vault URL
    ↓
App shows success
```

Example canonical URL:

```text
https://s.looxpassword.com/s/<share-id>#k=<fragment-key>
```

Then the app may offer:

```text
Shorten Link
```

Important:

```text
The app does not choose the short-link domain.
```

Backend chooses current primary short-link host.

---

# 13. Short-link product semantics

Recommended model:

```text
Canonical Share Vault Link
    ↓
optional shorten operation
    ↓
Short Link
    ↓
redirect/resolution
    ↓
Canonical Share Vault Link
```

The short link is not:

- a second share object
- a copy of ciphertext
- a new vault item
- a second authorization state

It is a presentation/redirect resource.

---

# 14. Critical fragment-key issue

Share Vault links reportedly place encryption key material in the URL fragment:

```text
#k=<key>
```

Fragments are not sent to the HTTP server during normal navigation.

Therefore the backend cannot safely create a redirect target by “reading the fragment” from a browser request.

The app already knows the complete canonical URL after share creation, including the fragment.

Recommended shorten request:

```text
App sends only the minimum canonical share locator required by the
shortener contract according to the existing privacy model.
```

App team must audit before implementation:

1. Does the canonical URL include a fragment-only decryption key?
2. Is sending the full canonical URL including `#k=` to backend acceptable?
3. If not, can short-link resolution preserve fragment secrecy another way?

Preferred security direction:

```text
Do NOT send fragment decryption key to backend merely to shorten a URL.
```

Recommended design if fragment secrecy must remain:

### Option A — Short code maps only to canonical server-visible share path

Backend stores:

```text
shortCode → canonical path/shareId
```

App constructs/copies:

```text
https://loox.pw/<shortCode>#k=<same-fragment-key>
```

Browser requests:

```text
GET /<shortCode>
```

without fragment.

Backend redirects to:

```text
https://s.looxpassword.com/s/<share-id>
```

The browser must preserve the fragment across redirect for this design to work.

This behavior MUST be verified across Safari, Chrome iOS, in-app browsers,
and relevant WebViews before relying on it.

### Option B — Client-side short-link landing page

Short host returns a minimal page that resolves the short code and performs client-side navigation while preserving the fragment.

Must be carefully audited.

### Option C — New short-link envelope design

If required, design a dedicated short-link contract rather than leaking the fragment key.

The app team must not assume generic redirect semantics preserve the security model without real-device/browser testing.

---

# 15. Short-link creation UX

After Share Vault success:

```text
Share Link Created

https://s.looxpassword.com/s/...

[Copy Link]
[Shorten Link]
```

Tap:

```text
Shorten Link
```

Loading:

```text
Creating short link...
```

Success:

```text
Short Link Ready

https://loox.pw/aB7kQ

[Copy Short Link]
[Share]
```

The app does not show a domain picker.

---

# 16. Short-link domain selection

Backend owns:

```text
primaryShortLinkDomainID
```

The app asks for:

```text
create short link
```

not:

```text
create short link on loox.pw
```

Conceptual API:

```http
POST /v1/share-links/{shareId}/short-link
```

or equivalent.

Response:

```json
{
  "short_url": "https://loox.pw/aB7kQ",
  "domain_id": "short-pw"
}
```

The app treats returned short URL as authoritative only after normal trusted API validation.

---

# 17. Why backend chooses the short-link domain

Benefits:

- one consistent short domain across the app
- operator can change primary domain later
- app releases are not required for preference changes
- no user-facing domain complexity
- easy capacity/abuse migration
- easier retirement

Example:

```text
Today:
primaryShortLinkDomainID = short-pw

Future:
primaryShortLinkDomainID = short-02
```

New short links use the new primary.

Existing short links continue on old host.

---

# 18. Short-link domain lifecycle

A short-link domain needs stronger lifecycle semantics than simple deletion.

Recommended:

```text
active
createDisabled
retiring
retired
```

## active

- may mint new short links
- existing links resolve

## createDisabled

- no new short links
- existing links still resolve

## retiring

- no new creation
- existing resolution maintained during migration period

## retired

- no new creation
- resolution behavior follows explicit shutdown policy

Never silently remove a domain while issued short links still exist.

---

# 19. Short-link fallback UX

If shortener is unavailable:

```text
Share Link Created
```

must still succeed because the canonical Share Vault link already exists.

Show:

```text
Short links are temporarily unavailable.
Your Share Vault link is ready to use.
```

Canonical actions remain:

```text
Copy Link
Share
```

Invariant:

```text
INV-AD-SHORT-01

Short-link failure MUST NOT convert a successful Share Vault creation
into a failed share operation.
```

This integrates with Optional Network Capabilities architecture.

---

# 20. Short-link capability state

Recommended distinct capability:

```swift
case shareLink
case shortLink
case privateEmail
```

Do not hide short-link health inside Share Link health.

Examples:

```text
Share Link healthy
Short Link outage
```

Result:

```text
canonical share creation works
shorten option unavailable
```

---

# 21. No auxiliary-domain deep links

Explicit decision:

```text
Only looxpassword.com hosts participate in app deep links / Universal Links.
```

Do not add auxiliary domains to:

```text
com.apple.developer.associated-domains
```

No AASA requirement for:

```text
loox.pw
future-domain.tld
```

unless a future separately approved proposal changes this.

This avoids:

- entitlement expansion
- provisioning churn
- host+path router complexity
- mail verification scanner/deep-link coupling
- runtime domain injection into deep-link trust

---

# 22. No auxiliary API hosts

Do not create:

```text
api.loox.pw
api-relay.loox.pw
config.loox.pw
```

merely because `loox.pw` exists.

Canonical APIs remain under:

```text
looxpassword.com
```

This prevents cross-host App Attest replay/confusion and reduces operational surface.

---

# 23. Registry vs app constants

App team should replace only auxiliary-domain-specific constants.

Do not over-generalize canonical service endpoints.

Good:

```swift
AuxiliaryDomainRegistry
PrivateEmailDomainResolver
ShortLinkCapability
```

Keep canonical service config explicit:

```swift
RelayConfig.apiBaseURL
LooxLinkConfig.apiBaseURL
CapabilityManifestClient.baseURL
InviteLinkService.canonicalHost
```

The goal is to avoid a generic “domain object controls every host” abstraction.

---

# 24. App-side models

Recommended:

```swift
struct AuxiliaryDomainRegistrySnapshot: Codable, Sendable {
    let schemaVersion: UInt8
    let registryVersion: UInt64
    let domains: [AuxiliaryDomainDescriptor]
}
```

Private Email:

```swift
struct EmailAliasSecret {
    // existing fields...
    let relayDomainID: String
}
```

Short Link result:

```swift
struct ShortLinkResult: Codable, Sendable {
    let shortURL: URL
    let domainID: String
}
```

Optional local Share metadata:

```swift
struct ShareLinkPresentationMetadata: Codable, Sendable {
    let canonicalURL: URL
    let shortURL: URL?
    let shortDomainID: String?
}
```

Do not make short URL the sole stored identity.

---

# 25. Existing data migration

## Existing aliases

Backfill client semantics:

```text
missing relayDomainID
→ legacy primary email domain ID
```

Do not rewrite addresses.

## Existing Share Vault links

Remain canonical:

```text
s.looxpassword.com
```

No automatic short-link generation.

No migration required.

---

# 26. App-team audit tasks before coding

The app team must verify current code and report:

1. Exact Share Vault canonical URL shape.
2. Whether decryption key is fragment-only.
3. Exact behavior of fragment across 301/302/307/308 redirects in:
   - Safari
   - Chrome iOS
   - Messages in-app browser
   - Gmail in-app browser
   - common WebViews if relevant
4. Whether current Share Link API can mint a short code without seeing fragment secret.
5. Exact current alias schema migration path.
6. Exact `LOOX-RELAY-AUTHZ-V1` encoder fields.
7. Whether V2 can be introduced alongside V1.
8. Whether current capability architecture can add `.shortLink`.
9. Whether existing Private Email UI has a natural domain selector.
10. Whether `VaultForwardingInbox` is unaffected by alias-domain choice.
11. Whether any deep-link code accidentally assumes all `loox.*` hosts are trusted.
12. Current offline behavior when share creation succeeds but a follow-up request fails.

---

# 27. App-team implementation phases

## A0 — Audit + contract report

No behavior changes.

Deliver:

- current URL semantics
- fragment handling
- alias schema migration impact
- Relay transcript impact
- capability integration report

## A1 — Auxiliary domain registry client

Implement:

- signed registry verification or bundled-allowlist subset model
- cache
- anti-rollback if signed
- bundled fallback
- lifecycle filtering

Do not change canonical API/deep-link hosts.

## A2 — Private Email sealed domain model

Implement:

```text
relayDomainID
```

with legacy fallback.

No backend multi-domain create until AUTHZ V2 contract is ready.

## A3 — Private Email domain UX

Implement:

- selector
- default preference
- lifecycle-aware visibility
- immutable alias domain

## A4 — Relay AUTHZ V2 client

After backend contract freeze:

- production vectors
- Swift parity
- tamper tests
- domain mutation tests
- V1 compatibility

## A5 — Short-link capability UX

Implement post-create optional action:

```text
Shorten Link
```

Shortener failure never fails canonical Share Vault creation.

## A6 — Short-link security/browser QA

Verify fragment behavior and no key leakage.

## A7 — Lifecycle/offline QA

Test:

- email domain active → createDisabled
- retiring
- registry unavailable
- shortener outage
- primary short-link domain changes
- old short links remain
- canonical share still works

---

# 28. Required companion Backend Proposal

After A0 audit, the app team must create:

```text
Loox Auxiliary Domains — Backend Proposal
```

for backend team execution in parallel.

The backend proposal must cover at minimum:

## B1 — Auxiliary domain registry

- signed registry or trusted allowlist model
- stable domain IDs
- lifecycle
- primary short-link domain selection
- primary email-domain policy
- anti-rollback
- key rotation
- operator tooling

## B2 — Private Email multi-domain schema

Recommended direction:

```text
domain_id
alias_hash
env
```

with uniqueness:

```text
UNIQUE(env, domain_id, alias_hash)
```

Audit existing unique constraints.

If `alias_hash UNIQUE` exists, table rebuild may be required.

## B3 — Relay AUTHZ V2

Bind:

```text
domain_id
```

to exact authorized command.

Required:

- production encoder
- frozen vectors
- generator imports production encoder
- Swift parity
- mutation tests
- V1 migration/cutover

## B4 — Email ingress routing

Recipient:

```text
localPart@domain
```

must resolve:

```text
allowlisted recipient domain
→ domain_id
→ alias hash
→ composite lookup
```

Unknown domain:

```text
reject
```

## B5 — Dynamic domain lifecycle

Support:

```text
active
createDisabled
retiring
retired
```

Adding a domain should not require schema changes.

Removing from creation should not delete issued resources.

## B6 — Short-link service

Must define:

- short code generation
- collision handling
- canonical mapping
- TTL or no-TTL policy
- abuse limits
- enumeration resistance
- redirect status
- logging/privacy policy
- domain lifecycle
- backend-selected primary short-link domain

## B7 — Fragment-key security

Backend proposal must prove one of:

- backend never receives fragment key
- fragment key handling is explicitly accepted and justified
- dedicated envelope design preserves secrecy

No accidental key ingestion in:

- logs
- analytics
- D1
- request tracing

## B8 — Short-link capability degradation

Shortener independent from canonical Share Link creation.

## B9 — Cross-account domain plan

For any auxiliary domain in another Cloudflare account, compare:

- move zone to primary account
- full duplicate deployment
- thin ingress/edge adapter to central authority

Do not assume duplicate principal plane is mandatory without analysis.

## B10 — Operator controls

Required:

```text
add domain
enable capability
disable new creation
select primary short-link domain
start retirement
complete retirement
```

All changes auditable.

---

# 29. Parallel execution contract

Recommended coordination:

```text
App A0 audit
        │
        ├──────────────┐
        ▼              ▼
App A1/A2          Backend B1/B2/B3
registry/model      registry/schema/V2
        │              │
        └──── contract freeze ────┐
                                  ▼
                            App A4 parity
```

Separately:

```text
App short-link UX + browser audit
        │
        ▼
Backend short-link proposal/service contract
        │
        ▼
integration
```

Do not let either team independently invent:

- domain IDs
- lifecycle states
- V2 transcript fields
- short-link fragment behavior

---

# 30. Acceptance criteria

The architecture is ready when:

1. `looxpassword.com` remains canonical platform anchor.
2. Auxiliary domains never become implicit API hosts.
3. Auxiliary domains never become implicit deep-link hosts.
4. App can display N Private Email domains from trusted policy.
5. Existing aliases preserve original domain.
6. Relay V2 cryptographically binds `domain_id`.
7. Adding a new email domain requires no D1 schema change.
8. Disabling new creation does not break existing aliases.
9. Backend can select one primary short-link domain.
10. App never asks user to select short-link domain.
11. Shortener outage does not fail Share Vault creation.
12. Canonical Share Vault URL remains valid independently.
13. Fragment decryption key is not accidentally leaked to backend/logging.
14. Old short links survive primary-domain changes.
15. Domain lifecycle is explicit and auditable.

---

# 31. Non-goals

- full multi-domain API platform
- dynamic API host selection
- auxiliary Universal Links
- auxiliary AASA
- alternate invite domains
- alternate config domains
- alternate App Attest hosts
- user-selected short-link domain
- automatic migration of existing aliases
- automatic shortening of every Share Vault link
- hard deletion of issued domain namespaces

---

# 32. Final recommendation

Adopt the following product architecture:

```text
looxpassword.com
= canonical platform

Auxiliary domain pool
= optional Private Email suffixes
+ optional short-link hosts
```

For Private Email:

```text
User may choose among active email domains.
Alias domain is immutable.
Relay AUTHZ V2 binds domain_id.
```

For Share Vault:

```text
Canonical link remains on looxpassword.com.
After successful creation, user may optionally shorten it.
Backend—not the app—selects the current primary short-link domain.
```

For deep links:

```text
Only approved looxpassword.com hosts participate.
Auxiliary domains remain ordinary web/email infrastructure.
```

This design keeps the value of short, diverse domains while avoiding a general multi-host trust architecture.
