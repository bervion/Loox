---
name: vaultify-ambient-share-status-plan
description: Plan 260712-1500 ambient invite→accept status — silent accept push, local notif, badge/copy, dirty-flag perf, conflict-safe publishProfile, recipient verify gate
metadata:
  type: project
---

Plan `plans/260712-1500-icloud-invite-accept-ambient-status/` (7 phases, ~13h), from audit report `from-flow-audit-260712-1453`.

**Why:** owner acceptance detection was foreground-poll only (no sub covers `ApprovalParticipantProfile` create); UI promised a ping that didn't exist (ShareInviteSentSheet:34). User LOCKED S1 as implement (recipient safety-code verify gate replacing silent auto-TOFU), not document.

**How to apply:**
- P1 silent `CKQuerySubscription` `approval-accept-<zone>` on profile create (next to saveOwnerAlertSubscription, ApprovalShareService.swift:95); silent ≠ phantom-alert problem the req-sub was narrowed for. Delete in revoke; backfill pass for pre-existing shares.
- P2 local notif ONLY on advance into `.readyForCeremony` while inactive (monotonic store guard = natural dedup); tap mailbox mirrors PendingInviteLink; shell drains post-unlock.
- P4 chose dirty-flag over CKQuery (prod queryable-index schema risk); consume-then-restore flag semantics.
- P5: publishProfile → `.ifServerRecordUnchanged` + 3-attempt re-merge (ParticipantProfileMerge, ApprovalModels.swift:161); respond() keeps `.allKeys` deliberately (single-writer idempotency).
- P6 design: pin stays at first sight (crypto anchor), NEW marker pending|confirmed|skipped in Keychain beside pin governs USE; legacy pins backfilled confirmed; pending zones withheld from AutoFill cache; skip is terminal (no re-nag).
- ApprovalSpike.swift: only referenced by DEBUG-gated SyncSettingsView.swift:85-105 — safe removal candidate, kept out of plan.
- R8 cross-device status deferred to iPad/Mac plan.
- Related: [[vaultify-approval-share-accept-detection-plan]] (prior stuck-on-Waiting fix this builds on).
