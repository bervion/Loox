# Project A — Family full-group sharing (transport: N grants per zone)

Goal: share a whole Space to a member in **one ceremony**; recipient projects **all** logins; owner manages/revokes per-member and per-item. Fixes the red-team blocker (PR #106): the Approval transport is one-grant-per-zone → only the last item survives.

Grounded by scout `plans/reports/scout-260715-1955-crypto-surface-map.md` (every file:line below verified there). Review incorporated: P0-A1..A4, P1-A5..A7, INV-FAM-01/02/03.

## Root cause (verified)
`ApprovalConfig.grantRecordName = "grant"` / `displayEnvelopeRecordName = "display-envelope"` are **fixed singletons**; `ApprovalShareService.publishGrant` **deletes every `ApprovalSharedField` record in the zone** before writing; recipient projection + `SharedGrantLiveCheck` read the single `"grant"`; `SharingStore` identity is `zoneName`. → only the last item in a zone survives (fail-safe: under-shares, no leak).

---

## A0 — CONTRACT FREEZE (do this first; no code until frozen)
Six contracts, each a written decision + unit-testable spec. Freezing them is phase A0.

### 1. Zone identity — `FamilyZoneIdentityV1` (NEW — today zones bind nothing)
Scout §3: today `ApprovalConfig.opaqueZoneName()` = `apz-<20B CSPRNG hex>`, binds **nothing** (no persona, recipient, item); each share mints a fresh random zone; email is the CKShare-invite ACL + UI dedupe only, **never** a security identity (email is not in any HPKE `info`, not in the signed grant; `recipientId` is opaque). So the family redesign must **define** zone identity rather than fix one:
- `FamilyZoneIdentityV1 = (ownerPersonaId, recipientParticipantId)` where `recipientParticipantId` = the resolved `ParticipantIdentity` (Curve25519), resolved **after** CKShare accept — **not** email.
- One reused zone per (active owner persona, recipient): re-sharing to the same member reuses their zone; Personal-persona vs Work-persona shares to the same person get **separate** zones (persona isolation, INV-R03).
- Normalized-email dedupe/discovery stays UI-only; the zone binds the resolved participant identity.

### 2. HPKE transcript **v3** (extend the existing v1/v2 ladder — INV-FAM-02)
Scout §2: the per-field `info` binds only `tag + grantId + fieldId (+ deviceKeyID v2)`; **no AAD** (`HPKE.Sender.seal` plain overload). `itemId` + `capability` are bound in the owner **signature** (`AccessGrant.signingBody`), but **not** in the field envelope → a field envelope can be replayed across items/grants inside a zone. Fix = a new transcript (v1/v2 already exist → clean precedent):
```
info = CanonicalWriter:
  string("Loox shared field v3")
  string(zoneIdentityHash)      // hash of FamilyZoneIdentityV1
  string(ownerPersonaId)
  blob(ownerSigningPubKey)
  string(recipientParticipantId)
  string(grantId)
  string(itemId)
  string(fieldId)
  string(fieldKind)
  string(capabilityTag)
  blob(deviceKeyID)             // per-device
```
Recipient re-derives identically; open fails on any mismatch. **Legacy v1/v2 read preserved** (existing single-item shares keep working). Ship freeze vectors (KATs) so the transcript can never silently drift.

### 3. Record schema — authenticated metadata, **not** recordName prefixes (INV-FAM-01)
Review P0-A1: do **not** infer ownership/cleanup from a `grant-<id>` string prefix — that couples security-critical cleanup to string parsing. Each record carries explicit fields:
- `ApprovalGrantRecord   { grantID, itemID, recordRole:"grant",   schemaVersion }`
- `ApprovalDisplayRecord { grantID, itemID, recordRole:"display", schemaVersion }`
- `ApprovalSharedFieldRecord { grantID, itemID, fieldID, recordRole:"field", schemaVersion }`

Deterministic recordName (`grant:<grantID>`, `display:<grantID>`, `field:<grantID>:<fieldID>`) is allowed for **direct fetch/delete only**. Recipient projection **and** cleanup **query by the `grantID` / `recordRole` fields**, never by name-prefix scan. `publishGrant` deletes only records where `grantID == thisGrant` — never the zone, never other grants.

### 4. Space-share semantics — **LIVE MEMBERSHIP** (DEC-FAM-01) ⟵ confirm
Review P0-A4: the test "add item → appears" implies live membership, not a one-shot snapshot. Decision: **a Family Space share = the live Space membership.** Consequences:
- Owner-side `SpaceShareMembershipReconciler`: `desired = eligible(items in Space) × members`, `ops = desired − published = {create, update, revoke}`; **idempotent + resumable**.
- Add item to Space → publish grant. Move/remove item out of Space → revoke that grant. Item→Note or becomes protected-only → revoke. Password changed → republish that field. Item deleted → tombstone + revoke.
- Makes per-grant revoke **mandatory** (contract 5).
- *This is the largest scope item and the one genuine product fork — see plan.md open decision. Snapshot semantics is the cheaper alternative (share exactly what exists at ceremony time; no reconciler).*

### 5. Revoke — zone-level **and** per-grant (both mandatory)
- Remove member = delete their zone (atomic, whole-member) — the family semantic.
- Per-grant delete (item leaves Space / deleted / becomes ineligible / owner unshares one) — required by live membership; not optional.

### 6. Capability safelist — field-**instance** based (INV-08 + review P1-A7)
A blanket space-share grants ONLY eligible login fields → `.value(.shared)`. **Eligible** = kind ∈ {`.username`, `.password`, `.url`, `.email`} **AND** not `guard2`/extra-protected (`SecretGuard` L2) **AND** not `.fileRef`/attachment **AND** not derived/virtual. **The normal masked flag (`protected`) does NOT exclude** — `.password` is `protected: true` by default (`FieldKind.defaultsProtected`), but masking is display, not a sharing signal; a family login share MUST include the password (the feature's purpose; user-confirmed 260715). Everything else (notes/`.multiline`, custom `.text`/`.monospace`, TOTP, passkey, any EXTRA-protected) → `.none`. Copy states exactly what ships: "This shares usernames, passwords, email addresses, and websites for every eligible login currently in this Space."

---

## Ground truth (verified from the transport read — smaller than feared)
The full blast radius is **6 call sites**; shared-field records need no schema change:
- **Shared-field records already self-describe**: `ApprovalRecordMapping.sharedFieldRecord` (`:110-119`) uses a **random** recordName and already carries cleartext `grantId` + `fieldId` fields. → No schema change. The bug is only that `publishGrant` **deletes every `ApprovalSharedField` in the zone** (`ApprovalShareService.swift:278`, `:325`). Fix = filter that delete to `sharedField(from:).grantId == thisGrant` (INV-FAM-01: scope by the cleartext `grantId` FIELD, never by parsing a recordName).
- **Only grant + display are singletons**: `grantRecord` name `"grant"` (`ApprovalRecordMapping.swift:36`), `displayEnvelopeRecord` name `"display-envelope"` (`:94`). → deterministic per-grant names `grant:<grantId>` / `display:<grantId>`. The grant blob already encodes `grantId`; the display record already carries a `grantId` field.
- **Singleton fetch-by-name callers** (must take a `grantId`): `ApprovalRecipientService.swift:274` (grant), `:338` (display); `SharedGrantLiveCheck.swift:36`; `PasskeyApprovalTransport.swift:44`.
- **v3 transcript is a SEPARATE slice, NOT A1.** A1 ships per-grant transport on the **existing v1/v2 field binding** (grantId+fieldId[+deviceKeyID]) — zero crypto change. The v3 hardening (INV-FAM-02: bind zone/persona/item/fieldKind/capability) needs A2's `FamilyZoneIdentityV1` threading (ownerPersonaId, zoneIdentityHash, recipientParticipantId don't flow into `publishGrant` today), so it lands with A2. Note: itemId + capability are ALREADY bound in the owner *signature* (`AccessGrant.signingBody`), so A1's per-grant transport does not regress replay resistance.

## Design — per-grant namespacing (additive, back-compatible)
1. **`ApprovalConfig`**: add `grantRecordName(grantId:)` / `displayEnvelopeRecordName(grantId:)` (deterministic `grant:`/`display:` + grantId); keep the legacy `"grant"`/`"display-envelope"` constants for back-compat reads.
2. **`ApprovalRecordMapping`**: `grantRecord` / `displayEnvelopeRecord` take a per-grant name; add/keep the `grantId` field so records self-describe.
3. **`publishGrant`**: write this grant's grant+display under per-grant names; delete only field/display records whose cleartext `grantId == thisGrant` (fetch records, filter by field — not IDs, not name-prefix); never wipe the zone or other grants.
4. **Recipient projection** (`ApprovalRecipientService` / SharedItems): enumerate **all** `ApprovalGrant` records in the zone (decode each blob → grantId) and project each item's fields (matched by `sharedField.grantId`); **legacy fallback**: also read the singleton `"grant"`/`"display-envelope"` so existing single-item shares keep working.
5. **`SharedGrantLiveCheck` + `PasskeyApprovalTransport`**: fetch the grant by `grant:<grantId>` (legacy singleton fallback), threading a `grantId` from the caller.
6. **`SharingStore`**: identity → `(zoneName, itemId)`; rework `upsert`/`remove`/`updateStatus`/`shares(forItem:)`; add `shares(forRecipient:)`. *(A2)*
7. **`SpaceShareMembershipReconciler`** (new, A2): the desired−published diff engine (A0-4); resumable per-op.

## Phases (each: implement → `make check` + unit → your 2-account checklist → fix)
- **A0 — Contract freeze**: the 6 contracts above; unit tests for record mapping + v3 transcript vectors. *No device test.*
- **A1 — Transport kernel**: per-grant records w/ authenticated metadata; scoped publish (delete own grant's fields only); recipient projection by grantID query; live-check by grantId; v3 seal/open + legacy read. Unit-test mapping + transcript. *2-account: publish 2 grants in one zone → recipient projects both.*
- **A2 — Store + reconciler**: `SharingStore` per-(zone,item) identity; `SpaceShareMembershipReconciler` (desired−published); tombstones; resumable batches. Unit-test the diff. *2-account: owner sees both items' state; add/remove item reconciles.*
- **A3 — Ceremony + async publication UX**: one `TrustFingerprint` ceremony; publication as a **resumable background op** with states `PREPARING → PUBLISHING x/y → PARTIAL → ACTIVE → FAILED_RETRYABLE` (not a held sheet); field-instance safelist; cap items×members + batch (20–50/batch, cap V1 ~100–200 items). *2-account: share a 3-login Space → recipient sees 3; a note/2FA item is NOT shared; kill mid-fan-out → resumes.*
- **A4 — Family management + revoke**: member view; member revoke (delete zone); per-item revoke; re-share (no dup zone). *2-account: revoke member → all their access gone; re-share same Space → no dup zone.*

## Invariants
- **INV-FAM-01** — grant ownership + cleanup determined from authenticated grant metadata, never inferred from CKRecord name prefixes.
- **INV-FAM-02** — every shared-field envelope is cryptographically bound (v3 `info`) to zone, owner persona, owner signing key, recipient, grant, item, field, field kind, capability, and recipient device key.
- **INV-FAM-03** — a Space share has explicit **live-membership** semantics; V1 does not mix snapshot + membership.
- **INV-R03** — persona isolation: a zone binds `ownerPersonaId`; only the active persona's Space items are shared.
- **INV-08** — hand-over is irreversible → field-instance safelist; cached plaintext is not revocable (UI states it).

## Threat model
- Field-envelope replay across item/grant/zone/persona → blocked by v3 binding (INV-FAM-02).
- Cleanup mis-scoping (wiping another grant's fields) → blocked by authenticated-metadata queries (INV-FAM-01).
- Persona cross-contamination in a reused member zone → blocked by `ownerPersonaId` in zone identity (INV-R03).
- Over-share of notes/2FA/passkey/protected → blocked by field-instance safelist (INV-08).
- Partial fan-out (CloudKit op failure) → resumable reconciler + per-op status; recipient sees a deterministic partial state.
- Revocation is not cryptographic: cached plaintext persists (UI states it); zone-level revoke removes the whole member atomically.

## Test matrix (2 iCloud accounts, both sides)
publish grant A then B → A untouched · republish A → B untouched · delete A → B remains · move item out of Space → A revoked · Login→Note → grant revoked · update password during publish → latest revision wins · recipient opens during partial fan-out → deterministic partial · duplicate fieldIDs across grants → no collision · malicious field envelope replayed into another grant/item → rejected (v3) · legacy singleton + new grants coexist → each projects exactly once · `Foo@x`≡`foo@x` dedupe (UI) → one zone · notes/2FA/passkey/protected NOT shared · revoke member → all gone · re-share → no dup zone.

## Risks
Recipient-side projection change lives on the OTHER device — test both sides · back-compat with existing single-grant zones (keep legacy read) · scale (N grants + fields per zone — cap + batch) · reconciler correctness is the new load-bearing logic — unit-test the diff exhaustively before any device test.
