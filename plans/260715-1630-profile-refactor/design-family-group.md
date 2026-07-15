# Design — Family full-group sharing + threat model

Status: **Design / ready to implement F2.** Grounds plan phase 05 ADR-F. No code here.

## Current architecture (verified)
- Sharing is **per item → per recipient**: `ItemShareRecord` (item, zone, recipient), `AccessGrant` (owner-signed P256 ECDSA, **not** sealed → tamper-evident but public), per-field capabilities. Field values are **HPKE-sealed** under the recipient's persistent (v1) or per-device (v2) key (`ApprovalShareService.publishGrant` :195–283). Recipient identity = `ParticipantIdentity` (synced) + `DeviceHPKEIdentity` (per-device, local keychain). HPKE **info binding** = grantId + fieldId (+ deviceKeyID in v2) resists envelope replay.
- **Revoke = delete the CKShare zone** (`ApprovalShareService` :410–424) — stops NEW reads; does **not** invalidate cached plaintext.
- **No group-key primitive.** "Share to N people" ⇒ **fan-out**: one grant + sealed blobs per member.

## Product model (proposed)
- `FamilyGroup` (owner-local, like `SharingStore` — device-local JSON): `{ name, members: [{ email, status, addedAt }], scope: Space id or item ids }`.
- **Add member** → run the EXISTING invite → accept → fingerprint → `publishGrant` ceremony for each in-scope item to that member.
- **Remove member** → revoke (delete their zones) across the group's items.
- **Scope** (v1): a chosen **Space (folder)** or hand-picked items shared to the whole group. "Share Space to Family" = fan-out per-item shares of every item in that Space to every member.

## Why fan-out, not a shared group key
A group key (one symmetric key sealed to each member, items re-sealed under it) is a **new crypto primitive** with its own membership-change re-seal + rotation cost — the same class of danger as vault-key rotation (see `design-devices-revoke.md`). Fan-out reuses the **proven per-item HPKE grant pipeline** → **no new crypto**, only orchestration + UI over `ApprovalShareService`. Cost: N members × M items grants (scale, below).

## Flows
1. **Create group / add member** — email → for each in-scope item, the existing share ceremony to that member; track under the group.
2. **Add item to scope** — share it to every current member (fan-out).
3. **Remove member** — revoke (delete zones) for that member across the group's items.
4. **Member (recipient) side** — unchanged: a family item is just N ordinary shares; "Shared with Me" already renders them.

## Threat model
- **Inherits existing sharing properties**: owner-signed grants (tamper-evident, public); values HPKE-sealed per recipient device; the fingerprint ceremony resists MITM on the recipient key.
- **Revocation is not cryptographic**: removing a member stops NEW reads, but their already-cached plaintext is permanent (same as today). **Must be stated in the UI.**
- **Owner observes member device fingerprints** (per-device HPKE keys in the recipient profile) — existing property; note for privacy.
- **No atomic membership change**: add/remove = many CKShare ops; partial failure leaves a member with partial access → needs **idempotent, resumable fan-out** + per-member status (reuse `ShareLifecycle`).
- **Scale**: a 200-item Space to 4 members = 800 grants + per-field HPKE seals → CloudKit op limits + battery. **Cap scope + member count**, batch, background, warn on large scopes.

## Recommendation (phased)
- **F1 — members list + manage (SHIPPED this PR):** read-only aggregation of existing shares by recipient → open `ShareRecipientDetailSheet` to revoke. No new crypto.
- **F2 — "Share a Space to people" (the real family group; NO new crypto):** fan-out the existing per-item ceremony over a chosen Space to chosen members; a lightweight `FamilyGroup` ties them together. Reuses `ApprovalShareService`. Needs: invite UI, resumable/idempotent fan-out, per-member status, cached-plaintext caveat copy, and a **two-account test matrix** before shipping.
- **F3 — true group-key semantics (optional, reviewed):** only if fan-out scale becomes a real problem. New crypto → its own threat model + security review.

**Proposed decision:** implement **F2** as "full family group" (delivers invite + shared-space + membership over proven crypto); treat **F3** as a later optimization. F2 is buildable now but its correctness (fan-out, CloudKit) needs 2-account device testing — it should be its own focused PR, not blind-shipped.

## F2 guardrails
Resumable, idempotent fan-out (per member×item status; retry only what's missing) · reuse `ShareLifecycle` for per-member state, surface partials · cap scope (items×members) with a warning · removal revokes zones per member + UI states the cached-plaintext caveat · **no change to the grant/HPKE crypto — orchestration only.**

## Red-team finding — fan-out into ONE zone is a BLOCKER (session 260715)
A first cut (`ShareSpaceSheet`: one zone + one ceremony, loop `SharedGrantComposer.publish` over the Space's items) was built and adversarially reviewed. **It does not work — the "fan-out is pure orchestration" assumption above is FALSE.** The Approval transport is **one grant per zone**:
- `ApprovalConfig.grantRecordName` / `displayEnvelopeRecordName` are FIXED singleton record names, and `publishGrant` **deletes every `ApprovalSharedField` record in the zone before writing**. Fanning N items into one zone therefore leaves **only the LAST item shared** (fail-safe: under-shares, not a leak) while the owner is told "Shared N logins." `SharingStore` is also zone-keyed (`id = zoneName`), so it structurally can't hold N items in one zone.
- **Capability over-share**: a blanket `.value(.shared)` ships EVERY non-Level-2 field — freeform Notes, `protected` custom fields, secure-note bodies — as an irreversible hand-over, without the per-field consent the per-item sheet enforces. Any real F2 MUST safelist login fields (username / password / url / email) and exclude notes / custom / protected.

**Conclusion:** "share a Space in one ceremony" needs a **transport-level change** — namespace grant / display / field records per `grant.id` within a zone (touches recipient projection, revoke, and `SharedGrantLiveCheck`) — OR N zones / N ceremonies (unacceptable UX). It is a **dedicated transport project, not orchestration.** The fan-out attempt was reverted; **F1 (members list) remains the shipped Family surface.**
