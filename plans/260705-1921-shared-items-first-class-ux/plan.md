---
title: "Sharing V1.2 — shared items first-class, detail reuse, notification inbox"
description: "Recipient shared items become real list items reusing ItemDetailScreen (read-only + Request); Shared-with-Me = Space only; owner detail shows recipients; single header share button; capability switches; notification inbox screen."
status: implemented — awaiting 2-device QA
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
| 1 | phase-01-shared-items-projection-data-layer.md | SharedOrigin + SharedItemsProjection + repository facade merge | ✅ 5560dba |
| 2 | phase-02-list-integration-shared-space.md | Items/Home/Search show shared items; Shared-with-Me space = standard list; remove Home row | ✅ 915520e |
| 3 | phase-03-item-detail-reuse-readonly-shared.md | ItemDetailScreen read-only shared mode + Request + Leave | ✅ 915520e |
| 4 | phase-04-owner-detail-sharing-row-header.md | A: sharing-with section, single header share button | ✅ 915520e |
| 5 | phase-05-capability-switches-polish.md | FieldCapabilityRow → Toggle switches; sheet polish | ✅ a73fe6a |
| 6 | phase-06-notification-inbox-screen.md | InviteInboxCoordinator + NotificationsScreen + Home bell badge | ✅ a73fe6a |
| 7 | phase-07-tests-review-cleanup.md | projection unit tests, code review, delete dead screens, docs/localization sweep | ✅ 8004540 + review fixes ef285ad |

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

## Review 260705 (report: plans/reports/code-review-260705-1931-sharing-v12-first-class-items-report.md)
C1 projection-persist via swipe upsert (UI gates + repository guards), H1 wipe-on-lock, H2 burn-on-success,
M1 always-merge + empty-gate + alert copy, M2 accepting flag + unsuppress re-present, M4 readOnly
DetailFieldRow, L: no totp placeholders / stable website id / trashed share gate / stored deviceId / 9+ badge
— ALL FIXED (ef285ad). M3 (field-kind metadata in display envelope) deferred: needs envelope v2 field map.

## 2-device QA runbook (V1.2)
1. A share item (switch UI!) → auto/link invite → B: notification screen (bell badge) hiện lời mời → Accept.
2. B: item xuất hiện ở Home list + Items→Shared with Me space + Search, badge "Shared"; tap → detail chuẩn
   read-only (không edit/pin/fav/trash; menu chỉ Leave Share); giá trị share reveal/copy được.
3. B: TOTP Request ngay trong detail → A approve (sheet hoặc từ màn Notifications) → code hiện + countdown.
4. A: detail item hiện section "đang chia sẻ với" (email + Active) → tap mở sheet quản lý; header chỉ 1 nút share.
5. A đổi tên item → B thấy tên mới sau refresh. 6. Revoke/Leave → item biến mất khỏi mọi list của B.
7. Khoá app B → mở lại → shared items xuất hiện lại sau unlock (wipe-on-lock hoạt động).

## QA feedback round 1 (fixed 76ce1d7)
- Field labels/kinds now travel as `SharedDisplayEnvelope.FieldMeta` (sealed): username renders
  visible, password masked; unknown meta fails closed to a masked secret. NOTE: shares created
  BEFORE this need re-share (or a rename on A re-publishes the envelope with meta).
- Approved TOTP code uses the app's own TOTP components (TOTPCodeView.format + CountdownRing).
- Home auto-select releases to "All Spaces" when shared items exist (both directions).

## PENDING PHASE 8 — AutoFill for shared items (user-requested, NOT yet implemented)
Design sketch: extension reads VaultStore only → needs a SEALED shared-credentials cache in the
app-group container (values sealed under Vault Key, written by SharedItemsProjection.refresh,
wiped on lock/revoke) + credential identities published for QuickType; TOTP askEachTime inside
AutoFill = request→poll response with a bounded wait UI in the extension (no push in extensions),
reusing RequestCodeModel over CloudKit from the extension process. Sizeable: needs its own review
(security: cache lifetime, revocation lag) — implement as the next work item.
