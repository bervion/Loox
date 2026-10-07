# Auxiliary Domains — App Phases A1/A2/A3/A5

> Follow-up 2026-10-07: email-domain activation và device QA hiện được quản lý ở [plan Email riêng tư/Member](../261007-1825-loox-member-and-private-email-ux-overhaul/plan.md). Live production registry v14 có email-pw `createDisabled`; các host/vexla/registry version trong A6 bên dưới là lịch sử, không dùng làm current acceptance. Model/picker/authz reuse, không triển khai lại.

**Refs:** `plans/reports/backend-proposal-260707-2031-…` (SIGNED), `audit-260707-2020-…`, app-team proposal `proposal-260707-2020-…`
**Locked:** DEC-01 (no retroactive shorten), DEC-02 (persist short URL fragment-free only), DEC-03 (A4 waits for `relay-authz-v2-contract.md`), DEC-04 (apex `@loox.pw`). BE: shorten auth = scoped `shorten_token` (transient only); registry trust root = capability-manifest P256 root; reserved local-parts → indistinguishable 409.
**Out of scope:** A4 (V2 encoder — gated), A6 (device browser QA — manual), remote signed-registry fetch (byte layout unfrozen; bundled registry now, verifier lands with registry contract doc — same pattern as `CapabilityManifestVerifier`).

## Phases

- [x] **P1 (A1)** `VaultifyCore/Models/AuxiliaryDomainRegistry.swift` — capability/lifecycle/descriptor model + bundled registry (`relay-main` only; `loox.pw` arrives via remote registry later) + lookup/resolution helpers.
- [x] **P2 (A2)** `EmailAlias`/`EmailAliasSecret` + `relayDomainID` (decodeIfPresent → legacy `relay-main`); new aliases stamped with default domain ID. Sync-safe: sealed-blob growth pattern already used by `tier`/`backendMinted`.
- [x] **P3 (A3)** Per-alias domain resolution replaces global `RelayConfig.emailDomain` at all 6 display call sites; domain picker row in create sheet appears only when >1 active email domain (dormant until registry ships a 2nd domain).
- [x] **P4 (A5)** Loox Link shorten:
  - `LooxLinkCreateResponse.shortenToken?` (`shorten_token`, decodeIfPresent → button hidden until BE ships)
  - `CreatedLink.shortenToken` transient only; NEVER persisted (token dies with the sheet, like the fragment key)
  - `LooxLinkRecord.shortURLWithoutFragment/shortDomainID` (decodeIfPresent), fragment never at rest
  - `CapabilityID.shortLink` + health-probe endpoint (loox-link worker)
  - `LooxLinkAPIClient.createShortLink(shareId:shortenToken:)` — endpoint path constant (one-line change at B6 freeze)
  - `LooxLinkService.shorten(_:)` — appends original fragment in memory; failure never disturbs the created share
  - `QuickLinkResultView` — Shorten button → swap displayed/copy/share URL to short form; outage footnote
- [x] **P5** Localization EN+VI for all new strings (`Localizable.xcstrings`).
- [x] **P6** Tests: alias secret decode fallback/roundtrip, record decode legacy, registry lifecycle filtering + resolver fallback, create-response with/without token, short-URL fragment compose/persist split.
- [x] **P7** `tuist generate` + workspace compile check + `make test`.

## GATE 1 follow-up (BE shipped 260707 21:32 — A4 + A1-remote)

- [x] **P8 (A4)** `LOOX-RELAY-AUTHZ-V2`: `RelayCommand.domainID`, frozen-V1 + new `transcriptV2` (domainID after aliasID), client flipped to V2 everywhere (dual-accept live), wire `command_version`+`domain_id` (presence == transcript presence), createAlias always-explicit domain / kinds 2-4 legacy-absent / kinds 5-7 none, activate() fail-closed guard removed, escrow rotate signs V2. Parity: 10/10 frozen vectors byte + clientDataHash green.
- [x] **P9 (A1-remote)** Signed registry client: `DomainRegistryDocument` (+verbatim-wire transcript, lenient typed mapping), `DomainRegistryVerifier` (sig/schema/env/freshness/anti-rollback), `DomainRegistryClient` (fetch→verify→cache→apply, env-bound staging/prod), wired via AppEnvironment.applyCached + alias-screen probe refresh; capability raw values fixed to wire (`email`, camelCase lifecycle). Parity: 3/3 vectors + self-signed verifier suite green.
- [x] **P10 (A5-assertion)** `LOOX-APP-ATTEST-SHORTEN-LINK-V1`: transcript builder in `LooxLinkCanonical` (u16len fields + SHA256(token) raw — bearer never in transcript), `assertShortenLink` (fresh challenge per attempt — server consumes on verify), header trio on `createShortLink`, shadow posture behind `shortenAssertionRequired=false` (independent ladder). Endpoint corrected to frozen `POST /v1/short-links` (share_id in body). Registry client URL now env-split (`config-staging` for DEBUG — live doc verified serving). Parity: 5/5 vectors byte+hash green.
- [ ] **A6** device browser QA — GATE 3 CLOSED 260707 22:51: short host = apex **vexla.app** (prod registry v3 live: relay-main + email-vexla active, short-vexla primary short-link, loox.pw pair createDisabled pending account role). Verified from app side: prod doc env/key/shape map clean; unknown short code → 404 + no-store.
  **CAVEAT: staging registry still v1 (no vexla) → DEBUG builds show no picker and can't shorten on vexla.app; run QA on a Release/TestFlight build, or ask BE to publish staging registry with vexla active.**
  QA checklist (Release build):
  1. Private Email → create alias → picker shows "relay.looxpassword.com" + "vexla.app" → pick vexla → activate → send real mail to `local@vexla.app` → lands in destination inbox.
  2. Alias on vexla: pause/resume/delete round-trip (kinds 2/4 with explicit domain_id).
  3. Share → Quick Link → Shorten Link → `vexla.app/<code>#k=…` (one-time: `&o=1`).
  4. Fragment matrix: open short link in Safari, Chrome iOS, Messages in-app, Gmail in-app → viewer decrypts (fragment survives 302). One-time link opens exactly once. → result decides GATE 2 (302 vs landing page).
  5. Links history after sheet dismissed: no Shorten action, record shows short host, no `#` anywhere.
  6. Registry lifecycle: BE flips a domain to createDisabled → picker hides it after probe refresh, existing aliases keep rendering.

## Success criteria
Compiles both targets; all tests green; zero behavior change visible until BE ships (`shorten_token` absent → no button; 1 active domain → no picker); no fragment-bearing URL or shorten token persisted anywhere.
