# Phase 06 — Notification inbox screen (V7)

## Overview
Priority P2 · Status: pending · Depends: phase 01 (accept → projection refresh). One screen
listing everything awaiting the user's decision; push alerts stay as the quick path.

## Architecture
- Promote the invite queue OUT of `InviteInboxBehaviors` into a new
  `Vaultify/Services/Sharing/InviteInboxCoordinator.swift` (@MainActor @Observable):
  `pendingInvites: [InviteEnvelope]`, `accept(_:)`, `dismiss(_:)` (markSeen + remove),
  reconcile triggers move here; `InviteInboxBehaviors` shrinks to alert presentation over
  coordinator state (same U6 single-path guarantee).
- Screen content = two sections, both already observable:
  1. **Share invitations** (recipient): coordinator.pendingInvites → Accept / Not Now buttons
     per row (generic label — envelopes carry no sender name by design; show received-at time).
  2. **Approval requests** (owner): `approvalCoordinator.pendingOwnerRequests` → tap opens the
     existing `ApprovalRequestSheet` (reuse `presentedApproval` plumbing via notification or
     direct sheet on this screen).
- Entry point: bell icon in `HomeHeaderBar` with badge = pendingInvites.count +
  pendingOwnerRequests.count; hidden badge when 0. Route registered in
  `vaultNavigationDestinations` (`NotificationsRoute`).

## Related code
- Create: `Vaultify/Features/Sharing/NotificationsScreen.swift`
- Create: `Vaultify/Services/Sharing/InviteInboxCoordinator.swift`
- Modify: `InviteInboxBehaviors.swift` (thin), `Components/HomeHeaderBar.swift` (bell + badge),
  `VaultRoutes.swift`, `AppEnvironment.swift`

## Implementation steps
1. Coordinator extraction (no behavior change — alert path identical, tests unaffected).
2. NotificationsScreen (grouped list, Polaris rows, empty state "Không có thông báo nào").
3. Bell + badge in Home header (44pt hit target, accessibility label).
4. Approval-request row → present ApprovalRequestSheet with existing onFinished/clearPending.
5. Localization EN+VI (bell label, section headers, empty state, row copy).

## Success criteria
- Invite arrives while user ignores the alert → bell badge shows; screen lists it; Accept from
  the screen runs the identical accept path (U7 cross-check included).
- Owner approval request visible + actionable from the screen; TTL-expired requests vanish on
  refresh (existing verify-before-show applies).
- Badge counts match visible rows; zero-state clean.
