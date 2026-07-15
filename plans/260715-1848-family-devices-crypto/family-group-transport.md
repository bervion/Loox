# Project A — Family full-group sharing (transport: N grants per zone)

Goal: share a whole Space to a member in **one ceremony**, recipient projects **all** logins, owner can manage/revoke. Fixes the red-team blocker (PR #106): the Approval transport is one-grant-per-zone; make it **N grants per zone, namespaced by `grant.id`**.

## Root cause (verified)
- `ApprovalConfig.grantRecordName = "grant"` and `displayEnvelopeRecordName = "display-envelope"` are **fixed singletons**; `ApprovalShareService.publishGrant` **deletes every `ApprovalSharedField` record in the zone** before writing; recipient projection + `SharedGrantLiveCheck` read the single `"grant"`. `SharingStore` identity is `zoneName`. → only the last item in a zone survives.

## Design — per-grant namespacing (additive, back-compatible)
1. **`ApprovalConfig` / `ApprovalRecordMapping`**: grant record name → `"grant-\(grantId)"`; display envelope → `"display-\(grantId)"`; shared-field records already keyed per field — key them per `grantId+fieldId`. Keep reading legacy `"grant"` on the recipient side for back-compat (existing single-item shares).
2. **`publishGrant`**: write to `grant-\(grantId)`; **delete only THIS grant's** shared-field/display records (scope the wipe by grantId prefix), never other grants' in the zone.
3. **Recipient projection** (SharedItems): **query ALL `grant-*` records** in the zone and project each item, instead of fetching one `"grant"`. HPKE info binding already includes `grantId` (+ fieldId/deviceKeyID) → cross-grant replay stays blocked; **verify** the binding covers grantId for every field kind.
4. **`SharedGrantLiveCheck`**: look up by `grantId` (per-item live/approval check).
5. **`revoke`**: keep zone-level (remove member = delete zone — the family semantic). Add optional per-grant delete for "unshare one item from a member".
6. **`SharingStore`**: identity → `zoneName + itemId`; rework `upsert`/`remove`/`updateStatus`/`shares(forItem:)` to key on the pair. Add `shares(forRecipient:)`.
7. **Capability safelist** (INV-08): blanket space-share grants ONLY login fields — `.username`, `.password`, `.url`, `.email` → `.value(.shared)`; everything else (`.multiline`/notes, custom `.text`/`.monospace`/`.fileRef`, any `protected`, TOTP, passkey) → `.none`. Never blanket hand-over. Copy must say exactly what ships.
8. **UI — `ShareSpaceSheet` (rebuilt)**: pick recipient + Space → one `createShare` zone → poll → **one** `TrustFingerprint` ceremony → fan-out `publishGrant` (safelisted caps) over the Space's `items(inFolder:)`. **Persist a pending `ItemShareRecord` per item** on createShare (so resume works); store `normalizedEmail`; dedupe re-share (reuse the recipient's existing family zone).
9. **`FamilyScreen`**: "Share a Space" entry + per-member view (their shared items, revoke member = delete zone).

## Phases (each: implement → `make check`+unit → your 2-account checklist → fix)
- **A1 — Transport**: per-grant record names + scoped publish wipe + recipient projection over all grants + live-check by grantId + legacy read. Unit-test record mapping. *2-account check: manually publish 2 grants in one zone → recipient projects both.*
- **A2 — SharingStore** per-item identity + queries. Unit-test. *Check: owner sees both items' share state.*
- **A3 — Capability safelist + `ShareSpaceSheet`** (one-ceremony fan-out, pending records, dedupe, copy). *2-account check: share a 3-login Space → recipient sees 3; a note/2FA item is NOT shared.*
- **A4 — Member management + revoke** in Family. *Check: revoke member → all their access gone; re-share → no duplicate zone.*

## Threat model
Cached plaintext not revocable (UI states it) · safelist blocks over-share · per-grant HPKE info binding must include `grantId` (verify) so a field envelope can't be replayed across grants · zone-level revoke removes the whole member atomically.

## Test matrix (2 iCloud accounts, both sides)
share Space(N) → recipient projects N · add item → appears · revoke member → all gone · re-share same Space → no dup zone · `Foo@x`≡`foo@x` dedup · notes/2FA/passkey/protected NOT shared · existing single-item shares still work (legacy read) · live/approval check per item.

## Risks
Recipient-side projection change lives on the OTHER device — must test both sides · back-compat with existing single-grant zones (keep legacy `"grant"` read) · scale (N grants + fields per zone — cap Space size, batch).
