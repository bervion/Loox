---
phase: 7
title: "Revocation & share management"
status: pending
priority: P1
effort: "0.75d"
dependencies: [4, 5, 6]
---

# Phase 7: Revocation & share management

## Overview
Minimal, security-critical management: owner sees "Shared with" per item and can **revoke** a recipient;
recipient can **leave** a share. Revocation is enforced cryptographically via epoch bump (checked fresh on
every approve, Phase 5) + CKShare/zone removal. **Trimmed per red-team (M4):** no "edit capability"
re-seal path (model it as revoke + re-share), no foreground cleanup sweep, no sessions (cut in Phase 5).

## Requirements
- Functional: owner revoke recipient (destructive confirm); recipient leave a received share; revocation
  blocks all further requests immediately at verify time.
- Non-functional: revocation authoritative (epoch + server-side share delete), not just UI; localized
  EN+VI; DS-compliant; destructive actions use `PolarisModal.destructive`.

## Architecture
- **Owner — `SharedWithView`:** lists recipients (from `SharingStore`, Phase 4). Action = **Revoke**:
  bump `AccessGrant.epoch` (owner-signed) + delete the recipient's `CKShare`/zone. Because Phase 5 does a
  **fresh epoch fetch before every approve**, an in-flight request under the old epoch fails to be
  approved (closes the multi-device revoke race). `PolarisModal.destructive` confirm.
- **"Change what's shared" = revoke + re-share** (no separate re-seal/edit code path) — simpler, avoids
  half-revoked state.
- **Recipient — leave:** `SharedItemsListScreen` (Phase 6) gains "Leave share" → remove participant, stop
  syncing that zone, drop local projection.
- **Forward-secrecy reality (H5):** revoke stops *future* requests and *future* `shared` re-seals; it
  **cannot** claw back `shared` blobs already delivered to B (B holds them under its participant key). UX
  copy on both the share-config sheet and revoke confirm must state this. `askEachTime` (TOTP) has no
  retained secret — only ephemeral codes that already expired.
- **Expiry:** grants past `expiresAt` are treated as revoked at verify time (no background sweep needed).

## Related Code Files
- Create: `Vaultify/Features/Sharing/SharedWithView.swift`
- Modify: `Vaultify/Services/Sharing/ApprovalShareService.swift` (revoke/epoch bump + share delete),
  `ApprovalRecipientService.swift` (leave), `SharingStore.swift`, `Vaultify/Features/Sharing/ShareAccessSheet.swift`
  (entry to manage + forward-secrecy copy)
- Reference: `Vaultify/shared` PolarisModal, `Vaultify/Features/Settings/SyncSettingsView.swift` (list style)

## Implementation Steps
1. `SharedWithView`: recipient rows + Revoke (destructive confirm).
2. Revoke: epoch bump (signed) + delete share/zone; update `SharingStore`.
3. Recipient "Leave share": remove participant, stop zone sync, drop local projection.
4. Verify-time enforcement: confirm Phase-2/5 reject requests under bumped/old epoch and past `expiresAt`.
5. Forward-secrecy copy in share-config + revoke confirm.
6. Localize EN+VI; DS-compliant; `make check`.

## Success Criteria
- [ ] Owner revokes B → B's next request fails (fresh-epoch check); B's shared item shows "access removed".
- [ ] Recipient can leave a share; owner sees them gone.
- [ ] Past-`expiresAt` grants rejected at verify time (no sweep).
- [ ] Revocation needs no TOTP seed reset; UX states `shared` values already delivered are retained by B.

## Risk Assessment
- Multi-device revoke race (session on a 2nd owner device) — eliminated by cutting sessions + fresh epoch
  fetch before every approve (Phase 5).
- CKShare delete latency — epoch bump (fast, checked at approve) is the security boundary; zone delete is
  cleanup.
