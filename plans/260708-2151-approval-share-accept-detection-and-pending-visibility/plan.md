# Approval Share — Reliable Accept Detection + Pending Visibility

## Problem

Owner (A) shares a vault item to another account (B). Two verified defects:

1. **B accepts, A still shows "Waiting for them to accept…" forever.** A detects acceptance
   ONLY by polling a custom `participant-profile` record B must publish after accept — which
   needs B's vault unlocked + a resume trigger, and A's poll only lives while the `.waiting`
   sheet is open (~10 min). A never reads `CKShare.participants[].acceptanceStatus`. No push /
   foreground refresh recovers it once the sheet closes.
2. **Blind pending state.** Dismiss/kill loses all in-memory tracking; CKShare persists
   server-side but nothing surfaces the pending share, no notification on accept, resume forces
   re-typing the recipient email.

Passkey is NOT involved (handled only after accept, in `publishGrant`). Verified — see report.

## Root cause (verified)

- `ShareAccessSheet.swift:298-319` — poll bound to `.task(id: .waiting step)`, dies on dismiss.
- `ApprovalShareService.swift:101-124` — owner subscription scoped to `requestRecordType` only,
  deliberately NOT firing on profile publish → no accept push.
- Owner never inspects `CKShare` acceptanceStatus; detection == B's `publishProfile`
  (`ApprovalRecipientService.swift:104`) gated on B unlocked (`VaultShellBehaviors.swift:125`).
- `AppPushDelegate.swift:170-181` — macOS accept omits `pendingShareAcceptanceKey` breadcrumb.

## Approach

Decouple two milestones the code currently conflates: **(a) B accepted the CKShare** (CloudKit
`acceptanceStatus`, immediate, network-only) vs **(b) B published crypto profile** (needed to
seal grant). Give the owner a real multi-state status, refresh it off-sheet on foreground/unlock,
and make pending shares visible + resumable.

## Phases

| # | Phase | Status | File |
|---|-------|--------|------|
| 1 | Reliable owner-side acceptance detection | ✅ done (compiles) | [phase-01](phase-01-reliable-acceptance-detection.md) |
| 2 | Pending-share visibility + resume UX | ✅ done (compiles) | [phase-02](phase-02-pending-share-visibility-and-resume.md) |
| 3 | Tests + on-device QA | ⚙️ unit tests done (9 pass); device QA pending | [phase-03](phase-03-tests-and-device-qa.md) |

## Implemented / deferred (as built)

- **Phase 1** — `ShareLifecycle` enum + persisted `statusRaw` on `ItemShareRecord`
  (back-compat decode), `ApprovalShareService.participantAccepted` (reads CKShare
  acceptanceStatus), `OwnerShareRefresher` (foreground/unlock off-sheet refresh),
  status-driven waiting copy, macOS breadcrumb parity. Builds app + extension.
- **Phase 2** — "Shares you sent" section in `NotificationsScreen` (live status), tap-to-resume
  via `ShareAccessSheet(resumeEmail:)` pre-filling the recipient into config (reuses the zone).
  **Deferred (documented):** local notification on accept — no background execution without a
  CloudKit push subscription, so it could only fire once already foregrounded; the Notifications
  list + live status is the real visibility fix. **Adjusted from plan:** resume pre-fills email
  into config (owner re-picks capabilities) instead of persisting capability selections — avoids
  storing hand-over choices; capability re-confirmation at grant time is acceptable.
- **Phase 3** — `ShareLifecycleStatusTests` (9 tests: derivation, legacy decode, rank,
  monotonic store guard) all green; full suite green. On-device 2-account QA still required.

## Key decisions (ADR)

- **ADR-A**: Owner reads `CKShare.participants[].acceptanceStatus` as the authoritative
  "accepted" signal; profile fetch becomes the *second* milestone ("device setting up"), not the
  only one. No crypto-invariant change — grant sealing still requires the profile.
- **ADR-B**: A persisted coarse status on `ItemShareRecord` (enum) so relaunch shows state
  offline; live refresh upgrades it. Keep `fingerprintConfirmed` as the `.active` terminal.
- **ADR-C**: Owner-side refresh runs on foreground/unlock over unconfirmed records — reuse the
  existing `refreshOwnerRequests` scene hook, add a sibling pass. No new always-on subscription
  required for the fix (subscription is a stretch in Phase 2).
- **ADR-D**: Approval-mode flags untouched — `approvalModeEnabled` stays the gate;
  `iCloudSyncEnabled` never involved (CLAUDE.md ADR-2).

## Dependencies

- Phase 2 depends on Phase 1's status model + refresh service.
- Phase 3 after 1 & 2.

## Non-goals

- Reworking the crypto kernel, grant format, or fingerprint ceremony.
- Passkey sharing changes (exonerated).
- Vault-item CloudKit sync (separate feature).
