# A0 Audit — Loox Auxiliary Domains (App Team Proposal §26)

**Date:** 2026-07-07 · **Input:** `proposal-260707-2020-loox-auxiliary-domains-app-team.md` (copied from Downloads)
**Related:** `proposal-260707-1937-…` (V1), `proposal-260707-2003-…` (V2 signed registry + AUTHZ V2)
**Scope:** verify the 12 audit items in proposal §26 against live code. No behavior changes.

---

## Verdict

Proposal is compatible with current architecture. **10/12 items verified clean.** 2 real findings:
- **F1 (design conflict):** "Shorten later" is impossible — the app deliberately does NOT persist the fragment key/canonical URL after the create sheet closes. Proposal §24's `ShareLinkPresentationMetadata.canonicalURL` would regress that security property.
- **F2 (coordination):** two separate proposals now claim `LOOX-RELAY-AUTHZ-V2` — this one (binds `domain_id`) and the locked Persona/Relay V3 (persona/transcript fields). Must be ONE unified V2 bump, not two.

---

## §26 item-by-item

### 1. Canonical Share Vault URL shape — VERIFIED
`{viewerBase}/s/{shareId}#k={fragmentKey}` + one-time hint `&o=1` **inside the fragment**.
`viewerBase` = `https://s.looxpassword.com` (prod) / `https://s-staging.looxpassword.com` (staging).
Source: `LooxLinkConfig.swift:106-107`, `:11-15`.

### 2. Decryption key fragment-only? — YES
AES-256-GCM content key, base64url, travels only in `#k=`. Server receives `ciphertextB64` + `ivB64` only (`LooxLinkCrypto.swift:5-13`). API client logging policy explicitly excludes bodies/fragment material (`LooxLinkAPIClient.swift:149`).

### 3. Fragment across 301/302/307/308 — NOT code-verifiable, device QA required
Spec behavior (WHATWG URL/fetch): browsers preserve the request fragment across 3xx when `Location` carries no fragment — but this MUST be QA'd on Safari, Chrome iOS, Messages in-app, Gmail in-app (proposal §14 Option A depends on it).
**Extra wrinkle found:** the fragment is not just the key — one-time links carry `k=…&o=1`. Short-link redirect must preserve the fragment **opaquely and completely**, or one-time gating breaks in the viewer.

### 4. Can API mint a short code without seeing fragment secret? — YES
`createShare` request = ciphertext/iv/expiry/oneTime (+ App Attest assertion headers). Server returns `shareId`/`revokeToken`/`expiresAt`; the app assembles the URL client-side (`LooxLinkService.swift:74-86`). A shorten endpoint keyed on `shareId` (with `revokeToken` as ownership proof) never needs the key. App then locally composes `https://<short-host>/<code>#k=…` — matches proposal §14 Option A.

**F1 — shorten is create-time-only.** `LooxLinkRecord` stores `shareId/revokeToken/itemId/dates/oneTime` and *deliberately* not the key or URL: "The content key is deliberately NOT stored: once the sheet is dismissed, only the recipient's URL can decrypt" (`LooxLinkRecordStore.swift` header). Consequences:
- "Shorten Link" must live in the post-create success sheet while `CreatedLink.url` is in memory. No retroactive shorten from the links list — that's consistent with the existing security model, keep it.
- Proposal §24 `ShareLinkPresentationMetadata.canonicalURL: URL` would persist the fragment key at rest → **reject that field**. Store only `shortURL?` + `shortDomainID?` (+ existing `shareId`). Even `shortURL` at rest is fine only because it does NOT contain the key (the app should store short URL *without* fragment, display-only, or store with fragment and accept the regression — decide; recommendation: without fragment, i.e. presentation metadata only, re-copy full short link only at create time).

### 5. Alias schema migration path — CLEAN
`EmailAliasSecret` uses custom `decodeIfPresent`-with-default decode, explicitly designed for sealed-schema growth (`EmailAlias.swift:93-141`). Adding `relayDomainID: String` with `?? legacyPrimaryDomainID` fallback matches the existing pattern (`tier`, `backendMinted` did the same). No plaintext column change needed.
**Sync caveat:** aliases flow through `CloudSyncService`; `VaultStore.upsertFromRemote` is whole-record LWW by `updatedAt` — any writeback that sets `relayDomainID` must bump `updatedAt` or it is dropped on pull.

### 6. Exact `LOOX-RELAY-AUTHZ-V1` encoder fields — VERIFIED
`RelayCommandCanonical.swift:14-31`:
```
"LOOX-RELAY-AUTHZ-V1" (raw) ‖ version=1 ‖ kind(u8) ‖ blob(principalID) ‖ u64(epoch)
‖ blob(nonce) ‖ i64(issuedAtUnixMs) ‖ opt-string(aliasID) ‖ opt-string(destination)
‖ opt-blob(newPublicKey)
```
Kinds: createAlias=1, disableAlias=2, rotateDestination=3, deleteAlias=4, disableAll=5, rotatePrincipal=6, beginDestinationVerification=7 (`RelayCommand.swift:6-16`).
Note: proposal §8's V2 field list includes `destination_id` and `public_key` — neither exists in V1 today (only `destination` string). V2 field set must be reconciled against actual V1, not the proposal's guess.

### 7. Can V2 be introduced alongside V1? — YES
Magic/version are constants (`RelayConfig.commandMagic`, `RelayCommandCanonical.version`); a parallel V2 transcript builder + server accepting both magics during cutover is straightforward. Frozen parity vectors are already the established contract style (file header comment). 

**F2 — one V2, not two.** ~~The locked Persona/Relay Proposal V3 (260706) already reserves a "transcript V2 required" bump for persona fields.~~ **CORRECTED post-review** (see "Post-audit corrections" below): V3's bump is the loox-link *assertion* transcript (`one_time`), a different MAGIC family — no collision on `LOOX-RELAY-AUTHZ-V2`. The governance concern stands: V2 must be one unified freeze (DEC-03), and the two transcript-family bumps must not be conflated.

### 8. Capability architecture `.shortLink` — TRIVIAL ADD, REGISTRY MACHINERY REUSABLE
`CapabilityID` is a 2-case `CaseIterable` enum (`Capability.swift:6-9`); `CapabilityStore` iterates `allCases`; only per-capability touchpoints are the health-probe endpoint switch (`CapabilityHealthProbe.swift:14`) and manifest mapping. Bonus verified: the capability manifest is **already signed** — P256 ECDSA over a canonical transcript with trusted key set + verifier (`CapabilityManifest.swift:108-148`, `CapabilityManifestClient` verify→cache→apply). §5 Option A (signed `LOOX-AUX-DOMAIN-REGISTRY-V1`) can reuse this machinery nearly verbatim (transcript writer, key pinning, silent-failure policy).

### 9. Private Email UI natural domain selector — NO PICKER TODAY, 6 CALL SITES
Addresses render via `AliasFormatting.address(…, relayDomain: RelayConfig.emailDomain)` at 6 sites: `AliasDetailScreen.swift:44`, `AffectedAccountsScreen.swift:18`, `PersonaAliasesScreen.swift:150`, `ItemEditorScreen.swift:117`, `:439`, `VaultRepository+AliasWriteback.swift:23`. There is no domain concept in UI. Plan: introduce `PrivateEmailDomainResolver` (aliasID → domain) replacing the constant at all sites; creation surfaces are PersonaAliasesScreen create flow AND the inline ItemEditor alias suggestion — the picker row (§9 mock) slots into the create sheet, but the inline editor path must also resolve a default silently.

### 10. `VaultForwardingInbox` unaffected? — YES
ForwardingInbox = the user's real destination inbox (sealed email + verification status, `ForwardingInbox.swift`). Orthogonal to the alias's namespace domain. Verification emails/verify host stay canonical (proposal §21 already excludes verify from aux domains). No coupling found.

### 11. Deep-link code assuming `loox.*` trusted? — NONE
Entitlement carries exactly one applink: `applinks:invite.looxpassword.com` (`Vaultify.entitlements:12`). `InviteLinkService.isInviteLink` requires exact `url.host == "invite.looxpassword.com"` AND `/i/` path prefix (`InviteLinkService.swift:103-105`). Remaining `onOpenURL` handlers are custom schemes (otpauth TOTP import, AutoFill shared-item hand-off) — no host wildcards, no `hasSuffix("loox…")` matching anywhere. INV-AD-03/§21 already holds.

### 12. Offline behavior: share created, follow-up fails — PATTERN ALREADY CORRECT
`createLink` is a single API call; success → local record → done. There is no follow-up request today, so nothing can retro-fail a created share. The optional-capability plumbing the proposal wants for shorten already exists: breaker gate (`allowRequest`), operator-signal vs infra-failure classification (`LooxLinkService.note`, INV-CAP-07). Shorten failure handling = mirror `note()` on `.shortLink`. INV-AD-SHORT-01 is satisfiable by construction (shorten runs after `CreatedLink` is returned).

---

## Extra findings (not in §26)

- **Env awareness:** staging pair `s-staging`/`api-staging` exists; the aux-domain registry + short-link hosts must be env-scoped (V2 proposal INV-MD-03 explicit host→env map covers this — carry it into the registry design).
- **Delta vs plans/reports V2 proposal:** V2 (260707-2003) made viewer-host user-selectable for Share Links; this proposal supersedes that with backend-selected short-link redirect over an unchanged canonical URL. Narrower and strictly less attack surface for the client — consistent with V2's locked decision #5 (share-viewer stays web-only) and drops the need for share-domain server validation on create.

## Recommended §27 phase adjustments

- A1: reuse `CapabilityManifest` canonical-transcript/verifier machinery for the registry (don't build a second signer).
- A4: blocked on unified V2 field freeze (F2) — coordinate with Persona/Relay V3 before any encoder work.
- A5: "Shorten Link" button only in the post-create sheet; persist short URL without fragment (F1).
- A6: QA matrix must include fragment `k=…&o=1` (one-time) preservation, not just `k=`.

## Post-audit corrections & locked decisions (owner session 2026-07-07 20:31)

**F2 scope correction (verified after owner review):** Persona/Relay V3 does NOT touch `LOOX-RELAY-AUTHZ` — its "transcript V2 before required" is the **loox-link create-share App Attest assertion transcript** (missing `one_time`; verified `from-dev-team-to-proposal-author-260706-1223-…:88`), a different MAGIC family. So there is no second claimant on `LOOX-RELAY-AUTHZ-V2`; unified V2 = V1 base + `domain_id` only. DEC-03 governance (backend owns field order, one freeze, no V2a/b/c) stands regardless. Two independent V2 bumps exist and must not be conflated: relay AUTHZ V2 (`domain_id`) and loox-link assertion transcript V2 (`one_time`).

All former open questions closed by owner:
- **DEC-01** (was Q2): no retroactive shortening; shorten only in create-success session. New INV-SHORT-01.
- **DEC-02** (was Q3): persist short URL WITHOUT fragment; `ShareLinkPresentationMetadata` = `shortURLWithoutFragment?` + `shortDomainID?`; `canonicalURL` deleted. New INV-SHORT-02/03.
- **DEC-03** (was Q1): one unified `LOOX-RELAY-AUTHZ-V2`; backend owns canonical field order + production encoder, app parity-signs off, security owner approves semantics. No speculative fields.
- **DEC-04** (was Q4): apex `<localPart>@loox.pw`, with reserved local-part exclusion (INV-DOM-RESERVED-01).

Follow-up: companion backend proposal delivered — `backend-proposal-260707-2031-loox-auxiliary-domains-registry-shortlink-relay-v2.md`. App phases A1/A2/A3/A5 unblocked in parallel; A4 gated on `relay-authz-v2-contract.md` freeze.
