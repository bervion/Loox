# Phase 02 — Pending-Share Visibility + Resume UX

## Context Links
- Overview: [plan.md](plan.md)
- Depends on: [phase-01](phase-01-reliable-acceptance-detection.md) (status model + refresher)

## Overview
- **Priority**: P1 (fixes "blind after dismiss/kill")
- **Status**: pending
- **Description**: Surface outgoing pending shares in a persistent, resumable place; notify the
  owner when B accepts; let the owner resume the fingerprint ceremony without re-typing email.

## Key Insights
- The persisted `ItemShareRecord` already exists — it just isn't shown anywhere durable. The fix
  is surfacing + navigation, not new persistence (Phase 1 adds the status those views need).
- `NotificationsScreen.swift` already aggregates owner/recipient pending items — the natural home
  for outgoing pending shares (one more section).
- Resume today forces re-typing email (`ShareAccessSheet.swift:225-231`). With the persisted
  record + zone, the sheet can jump straight to `.waiting`/`.fingerprint` for a known share.

## Requirements
Functional:
- A section in `NotificationsScreen` listing outgoing shares not yet `active`, with live status
  (from Phase 1) and recipient label; tap → resume that share's flow.
- Local notification (or in-app badge) when the owner-share refresh detects a transition to
  `accepted`/`readyForCeremony` while the app was backgrounded/closed.
- `ShareAccessSheet` can be opened targeting an existing pending record → enters at the right
  step (`.waiting` if not ready, `.fingerprint` if profile already fetched) WITHOUT the config
  form or email entry.
- Dismissing the waiting sheet leaves a clear "still pending, resume from Notifications" trail.

Non-functional:
- Reuse existing screens/components (KISS) — no brand-new management surface unless needed.
- All copy localized EN + VI. Polaris icons only. Token-driven styling.

## Architecture
- **NotificationsScreen**: add `outgoingPendingShares` derived from `env.sharingStore.shares`
  filtered `status != .active`, joined with item title. Row shows status label + chevron.
- **Resume entry**: `ShareAccessSheet` gains an optional `resumeZoneName: String?` init param;
  when set, `onAppear` loads the record, restores `recipientEmail`, and routes to `.waiting`
  (re-arming `pollForProfile` via `pollingZoneName`) or `.fingerprint` (fetch profile first).
- **Notification**: extend the Phase-1 `OwnerShareRefresher` — on a status upgrade for a record,
  post a local `UNUserNotificationCenter` notification ("<recipient> accepted — tap to finish").
  Reuse existing notification-permission gating (`ApprovalPrerequisites`).
- Deep-link: tapping the notification routes to the item's `ShareAccessSheet` with
  `resumeZoneName` (via existing deep-link buffer pattern in `AppPushDelegate`/env).

## Related Code Files
Modify:
- `Vaultify/Features/Sharing/NotificationsScreen.swift` — outgoing-pending section + nav.
- `Vaultify/Features/Sharing/ShareAccessSheet.swift` — `resumeZoneName` entry + step routing.
- `Vaultify/Services/Sharing/OwnerShareRefresher.swift` — emit local notification on upgrade.
- `Vaultify/App/AppEnvironment.swift` / deep-link plumbing — route resume target (if needed).
Create:
- (Only if NotificationsScreen row grows too large) `Vaultify/Features/Sharing/
  OutgoingShareRow.swift` — extracted row component.

## Implementation Steps
1. Derive + render outgoing-pending section in `NotificationsScreen`; localized status labels.
2. Add `resumeZoneName` param to `ShareAccessSheet`; `onAppear` restores state and routes to the
   correct step (skip `.choose`/`.config`).
3. Wire NotificationsScreen row tap → present `ShareAccessSheet(resumeZoneName:)` for that item.
4. In `OwnerShareRefresher`, detect status upgrades vs prior persisted value → schedule a local
   notification (respect permission; no secrets in payload).
5. Notification tap → buffer resume target → present the sheet at the right step.
6. Waiting-view dismiss copy: point the user to Notifications to resume.
7. Localize EN + VI; `tuist generate` if new file; `make check`.

## Todo List
- [ ] Outgoing-pending section in NotificationsScreen
- [ ] `resumeZoneName` entry + step routing in ShareAccessSheet
- [ ] Row-tap navigation
- [ ] Local notification on status upgrade (gated)
- [ ] Notification-tap deep link to resume
- [ ] Dismiss copy → "resume from Notifications"
- [ ] Localize EN + VI
- [ ] `tuist generate` + `make check`

## Success Criteria
- Owner kills app mid-wait, reopens → sees the pending share in Notifications with current status.
- When B accepts while A is closed, A gets a local notification; tapping resumes the ceremony
  with no email re-entry.
- Resume routes to `.fingerprint` directly if the profile is already available.

## Risk Assessment
- **Notification spam** on repeated refreshes → only notify on an actual status *transition*
  (compare against previously persisted status), once per milestone.
- **Deep-link races on cold launch** → reuse the existing buffer pattern (`PendingInviteLink`).
- **NotificationsScreen growth** → extract row if the file nears the 200-loc guideline.

## Security Considerations
- Notification payload carries only recipient label (already device-local) — no item value/secret.
- No new server subscription; refresh stays client-pull (a zone subscription is a later stretch).

## Next Steps
- Phase 3: tests for status transitions + resume routing; on-device 2-account QA.
