---
title: "Sharing V1.2 — shared items first-class, detail reuse, notification inbox"
description: "Recipient shared items become real list items reusing ItemDetailScreen (read-only + Request); Shared-with-Me = Space only; owner detail shows recipients; single header share button; capability switches; notification inbox screen."
status: pending
priority: P2
branch: feat/sharing-v12-shared-items-ux
tags: [sharing, ux, item-detail, notifications]
created: "2026-07-05T19:21:00+07:00"
---

# Sharing V1.2 — shared items first-class UX

## USER DECISIONS (2026-07-05, do NOT reverse)
| # | Decision |
|---|----------|
| V1 | B: invite accepted → shared item is a REAL item in user's lists; tap opens the STANDARD `ItemDetailScreen` (no custom SharedItemView) |
| V2 | Shared item = read-only "shared" type: no edit; TOTP fields get a Request button inline |
| V3 | "Được chia sẻ với tôi" = a SPACE in Items only — remove the Home row |
| V4 | A: item detail shows a "sharing with…" row (who + status) |
| V5 | A: ONE share button in the detail header = capability sharing (replace current ShareLink; no 2 share buttons) |
| V6 | Options = switches (Toggle); popup ONLY when >2 choices |
| V7 | Notification inbox screen (pending invites + approval requests), alert quick-path stays |

## Architecture (locked)
- **`SharedItemsProjection`** (new, recipient): @Observable store building `VaultItem`-shaped
  models from accepted zones (grant + DisplayEnvelope + sealed shared values). In-memory cache,
  refresh on `recipientChangeCounter` / foreground / push. **NEVER enters `VaultStore`** — no
  sync, backup, Watchtower, AutoFill contamination. Stable id `shared::<owner>::<zone>`.
- `VaultItem.sharedOrigin: SharedOrigin?` (optional, nil for owned; carries zoneID+grantId+ownerName).
  Lists/search/detail merge projection at the UI-facing repository facade only.
- Detail reuse: `ItemDetailScreen` branches on `sharedOrigin` → read-only chrome, Leave Share,
  Request button per askEachTime TOTP capability (reuse `RequestCodeModel`), safety-code row.
- `InviteInboxCoordinator` (promote queue out of `InviteInboxBehaviors`) feeds BOTH the accept
  alert and the notification screen.
- Delete `SharedItemView` + `SharedWithMeScreen` zone-list once parity reached.

## Phases
| # | File | Scope | Status |
|---|------|-------|--------|
| 1 | phase-01-shared-items-projection-data-layer.md | SharedOrigin + SharedItemsProjection + repository facade merge | pending |
| 2 | phase-02-list-integration-shared-space.md | Items/Home/Search show shared items; Shared-with-Me space = standard list; remove Home row | pending |
| 3 | phase-03-item-detail-reuse-readonly-shared.md | ItemDetailScreen read-only shared mode + Request + Leave | pending |
| 4 | phase-04-owner-detail-sharing-row-header.md | A: sharing-with section, single header share button | pending |
| 5 | phase-05-capability-switches-polish.md | FieldCapabilityRow → Toggle switches; sheet polish | pending |
| 6 | phase-06-notification-inbox-screen.md | InviteInboxCoordinator + NotificationsScreen + Home bell badge | pending |
| 7 | phase-07-tests-review-cleanup.md | projection unit tests, code review, delete dead screens, docs/localization sweep | pending |

## Key dependencies / risks
- Projection id must never collide with real item ids (prefix + zone owner).
- Watchtower/AutoFill/export/backup must keep reading `repository.items` (owned only) — add tests.
- RequestCodeModel holds in-memory ephemeral keys — detail must keep model identity across
  push-driven refreshes of the SAME grant (pattern already solved in SharedItemView; port it).
- Home-row removal changes onboarding path for first-time recipients: notification screen +
  space cover it; invite accept alert already routes attention.

## Out of scope
Editing shared items, re-share by recipient, multi-device inbox flap (M4 — multiplatform plan),
Production schema deploy + TestFlight QA (release gate, unchanged from V1.1).
