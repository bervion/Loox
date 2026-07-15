# Phase 05 — Family (full family group) — NET-NEW (large)

Type: net-new · Depends: 01 · **Needs a dedicated design pass + ADR before coding.**

## Decision (user)
Full family group: an owner invites members and shares vault items / a Space to the whole group — beyond today's per-item shares.

## Current primitives (the foundation to build on)
- Per-item sharing: `ItemShareRecord` (item → recipient email, status lifecycle inviteSent→accepted→readyForCeremony→active), `AccessGrant` (recipient crypto identity + capabilities), CKShare via Approval Mode (`ApprovalConfig`, `ApprovalShareService`, `ApprovalCoordinator`). Recipient identity is opaque (`recipientId` UUID; owner stores email locally).
- **No group / members / family aggregate exists today.**

## ADR-F (finalize in the design pass)
- Model `FamilyGroup` { owner, members[email/identity + status], createdAt } and a group sharing target (share a Space or item set to all members).
- Build over CKShare/Approval primitives: decide **group share = fan-out of per-member grants** vs **a dedicated shared CloudKit zone**. Trade-offs: fan-out reuses existing crypto but scales O(members×items); a shared zone is cleaner but new infra.
- Persona: which persona's items may be shared to family (owner-persona scoping, INV-R03).
- Respect ADR-2 (`approvalModeEnabled` ≠ vault sync).

## First slice (this phase only)
- `FamilyScreen`: list members derived from existing shares (dedup `SharingStore.shares` by recipient) + group metadata; an invite entry (email) that seeds the first group + share.
- Defer the full shared-space + per-member permissions to follow-up phases.

## Risks / open
- Large, product-heavy, **security-sensitive** (sharing crypto). Strongly recommend a dedicated design + ADR and a `/ak:security` threat pass BEFORE implementation.
- Scope creep — keep the first slice to a members list + invite over existing sharing.

## Validation
- Design/ADR approved first. Then: `make check`; no persona leakage; EN + VI; existing sharing crypto unchanged and re-verified.
