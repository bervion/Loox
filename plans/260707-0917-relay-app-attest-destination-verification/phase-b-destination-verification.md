# Phase B — Destination Ownership Verification (client)

**Priority:** P0 · **Status:** unblocked (BE DEC-DST-01 deployed, `DESTINATION_VERIFICATION_MODE=off`) · **Base:** `develop`

Kind-7 protocol parity already merged (PR #62). This phase adds the functional client.

## Contract (BE, frozen)
- Sign **exact** user-entered destination in kind-7 (`alias_id` absent → `alias_id_forbidden`); backend derives all hashes (INV-DST-N01, no client hashing).
- `POST /v1/relay/destinations` (signed kind-7): `201/200 {destination_id,status:"pending",masked_email,resend_after_seconds}` (begin/resend, cooldown 60s doubling→1h cap; budget 5/dest-budget/day + 10/principal/day → 429 `destination_rate_limited`); `200 {…,status:"verified"}` idempotent when already VERIFIED; `503 verification_unavailable` (won't happen).
- Verify web (scanner-safe): `https://verify[-staging].looxpassword.com/email/<token>` GET renders, POST confirms (single-use, 30-min TTL). AASA live, `WDNL2F75V7.com.bervion.vaultify`, paths `/email/*`.
- After `required` flip: `rotateDestination.destination = destination_id` (VERIFIED, same principal) — unverified → `403 destination_not_verified`; ingress `550` unverified. DEC-MIG: no grandfather, existing inboxes re-confirm. `disableAll` revokes+scrubs destinations.

## B1 — functional backbone (no entitlement, ships now)
1. **Model:** `ForwardingInbox` + `ForwardingInboxSecret` gain `verificationStatus` (`unverified/pending/verified`) + opaque `relayDestinationID`. Growable sealed schema (`decodeIfPresent`), **no CloudKit column change**; bump `updatedAt` on change (LWW gate [[vaultify-sync-lww-updatedat-gate]]).
2. **API:** `RelayAPIClient` (or `RelayDestinationsClient`) — `POST /v1/relay/destinations` begin/resend; map `destination_rate_limited` 429 + `alias_id_forbidden`. Reuse principal sign + App Attest assertion path.
3. **Service:** `RelayService.beginDestinationVerification(inbox)` (kind-7, exact email) → store `relayDestinationID` + status=pending; `resend`; status refresh (see open question).
4. **UX:** extend `ForwardingInboxScreen` — status badge (unverified/pending/verified), "Confirm email" (begin) → "Check your inbox (masked)" pending state → "Check Verification" refresh (never self-confirm) + "Resend" (cooldown). Re-confirm entry for existing inboxes (DEC-MIG).
5. **Routing (gated):** keep sending plaintext email in `rotateDestination` until a `RelayConfig.destinationIdRoutingEnabled` flag flips lockstep with server `DESTINATION_VERIFICATION_MODE=required`; then bind `relayDestinationID`. Handle `403 destination_not_verified` → surface re-confirm.

## B2 — Universal Link (deferred; infra risk)
- Associated Domains entitlement (`applinks:verify.looxpassword.com`) in `Project.swift` → **needs the capability provisioned in the Apple portal + match profile**, or CI signing breaks (CLAUDE.md crash-trap). Requires owner portal action + device verify.
- Deep-link handler: app opens on link tap → explicit POST-confirm (app still never auto-confirms).
- **Not required for the feature to work:** B1 flow completes via web-confirm + in-app poll; Universal Link is a UX convenience.

## Open questions (BE)
1. **Status polling:** §6 lists only `POST /v1/relay/destinations` (begin/resend, shares cooldown+budget). How does the client poll VERIFIED **without** triggering a resend / burning budget? Is there a `GET /v1/relay/destinations/{id}` (or `/status`)? Needed for the pending→verified refresh UX.

## Success criteria
Model + kind-7 begin flow integrated; existing inboxes surface re-confirm; routing switch gated + ready; parity green; no CloudKit schema change; Core Vault unaffected. Device QA for the real App Attest-signed kind-7 + web-confirm round trip.
