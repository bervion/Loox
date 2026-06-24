# Identity & Profile Feature Shipped — But a Sync Design Decision Pivot Made The Path Messier

**Date**: 2026-06-24 12:00  
**Severity**: Medium  
**Component**: Data model, sync layer, onboarding, ProfileScreen  
**Status**: Resolved  
**Branch**: `feat/identity-profile` (ready to merge main)

## What Happened

Completed the 4-phase "Identity & Profile" feature: default identity at onboarding, per-item avatar with cross-device sync, and a new Profile screen. All phases tested in TDD, code-reviewed, committed, and passing. The feature ships.

But the journey exposed a critical gap in how we approach multi-device sync decisions — and cost us a phase of rework.

## The Brutal Truth

**We picked the sync schema wrong the first time, discovered it during implementation, and had to reverse course.** Not a breaking change, not a bug, but a design pivots that should have been caught by reading the persistence layer harder, earlier. The frustration isn't failure; it's recognizing the pattern we missed: **every sync-touching decision MUST trace through `VaultStore.upsertFromRemote` (the LWW gate) before the schema is final.**

That one read would have saved a 2-hour pivot on day 2 of implementation.

## Technical Details

**Original plan (Phase 1 brainstorm, validated by red-team):**
- Default identity = dedicated sync column `defaultIdentitySetAt: Date?` (timestamp of when the default flag was set).
- Rationale: it cleanly separates "when was this item last edited" (`updatedAt`) from "when did the user last choose this as default" (a separate concern).
- Tie-break rule: `max(defaultIdentitySetAt) → max(updatedAt)` for sync conflicts.

**Discovery (Phase 1–2 implementation):**
- Opened `VaultStore.upsertFromRemote` to understand how sync conflicts are resolved.
- Found: `guard updatedAt > existing.updatedAt else { return }` — **the entire CloudKit record is accepted or rejected as a unit by `updatedAt`.**
- Any column change that isn't reflected in a bump to `updatedAt` is **silently dropped** on the next sync pull.
- Therefore: `setDefaultIdentity` (which would only touch `defaultIdentitySetAt`, not `updatedAt`) → columns persist locally but never sync cross-device.

**Result (Phase 1 rework):**
- Dropped the `defaultIdentitySetAt` column entirely.
- Changed `setDefaultIdentity` to bump `updatedAt = .now` (column-only write, no re-seal).
- Tie-break rule simplified to: `max(updatedAt) → max(createdAt)`.
- Trade-off: changing default floats the identity up "Recently Modified" (rare action, acceptable).
- Code: committed in `4b048e9`, tests green.

**Avatar decision (F4 validation finding):**
- Initially planned as device-local attachment (consistent with existing `AttachmentStore` blob pattern).
- Red-team flagged: orphaned blobs on permanent delete (disk bloat + data residue).
- Validation clarified: AppGroup is synced, so avatars should also sync for zero-knowledge multi-device.
- Solution: ≤256px JPEG, sealed with AES-GCM, stored directly in `ItemRecord.avatarSealed: Data?` → rides the item's CloudKit record (column dies with record, no orphans).
- Committed in `4b048e9`.

## What We Tried

1. **Read the red-team report** (F1 finding flagged the sync tie-break concern, but framed it as "needs decision").
2. **Opened `VaultStore.upsertFromRemote`** to understand the gate mechanics.
3. **Traced `setDefaultIdentity` spec**: "column-only + dirty, then reload" → realized the column change would be invisible to sync.
4. **Proposed the fix in sync review** (pre-code-review with user).
5. **Re-spec'd Phase 1–2** (swap `defaultIdentitySetAt` for `updatedAt` bump).
6. **Re-ran Phase 1–2 tests** (all passed; implementation was column-only anyway, just a flag change).

## Root Cause Analysis

**Why didn't we catch this before Phase 1 started?**

The red-team report *did* surface the issue (F1), but phrased it as a "needs decision" between 3 options:
- (a) Bump `updatedAt` on `setDefaultIdentity`.
- (b) Dedicated `defaultIdentitySetAt` column.
- (c) Accept arbitrary conflict winner.

We chose (b) because it seemed cleanest semantically. **But we didn't verify (b) against the actual sync gate before finalizing.**

The gap: **assumptions about the sync layer were never traced to the source code.** We should have opened `VaultStore.upsertFromRemote` as part of the red-team validation review, not during implementation.

Pattern violation: treated sync-touching decisions as "TDD black boxes" (trust the test harness) instead of **reading the persistence layer first.**

## Lessons Learned

1. **Sync schema decisions require tracing the gate.** Every sync-touching schema decision must pass through a read of `VaultStore.upsertFromRemote`, `CloudSyncService` push/pull, and relevant migrations. Don't assume; don't defer to test-time discovery. 15 minutes of reading saves 2 hours of rework.

2. **Distinguish "design concern" from "sync constraint."** Default identity is a *design concern* (which item is the profile?); the way it syncs is a *sync constraint* (must ride `updatedAt` or it's invisible cross-device). Design can be flexible; sync constraints are hard walls. Validate constraints against the layer, not the plan.

3. **Red-team findings phrased as "decision needed" still require a spec read.** The three options the reviewer offered were *semantically sensible*, but option (b) violated a sync constraint that only the source code could reveal. If a finding touches persistence, validate the proposed options against the code before locking.

4. **Column-only writes are cheaper than you think, but only if they sync.** The original aversion to floating identity's `updatedAt` was understandable (recency pollution), but it was based on aesthetic concern, not a hard constraint. The actual constraint (updatedAt = sync gate) was harder than the concern (Recent list ordering is noisy). Tracing the gate reveals which one matters.

## Next Steps

1. **Merge `feat/identity-profile` to `main`** (all phases complete, code-reviewed, tests passing).
2. **Document the sync-layer-first pattern** in `docs/development-rules.md` under a new section "Sync schema decisions" — add this as a mandatory pre-implementation step.
3. **Link from code-review checklist**: when a PR touches sync columns, verify it traced `VaultStore.upsertFromRemote`.

**Owner**: Code review (future reviews will catch this pattern).  
**Timeline**: document immediately in parallel with merge; no blockers.

## Unresolved Questions

None. Pivoted decision is user-confirmed; implementation complete; ready for main.
