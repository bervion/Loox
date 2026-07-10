# Phase 5 — Sharing/Approval flow + pending persistence

**Context:** research/design-spec-sharing-approval-pending.md (4a-4f,12a-12c), secondary (10f invite-sent), core-tabs (9b gate offline, 9c approval issuing). Depends: Phase 0. Rủi ro cao nhất (chạm sharing infra).

## Overview
- Priority: P2
- Status: pending
- Đây là nhóm giá trị cao (fix "owner stuck on Waiting" — memory approval-share-accept-detection) nhưng chạm CKShare/approval → để sau cùng trong nhóm ship-được.
- Background push accept-detection = TÁCH sang Phase 6 (cần infra). Phase 5 chỉ UI + manual Check Now (đã khả thi).

## Key insights
- Đã có: `ShareAccessSheet.swift` (step machine choose→config→…→waiting→fingerprint), `NotificationsScreen.swift` (4 section), `ApprovalRequestSheet.swift` (match code + Face ID), `QuickLinkView.swift`+`QuickLinkResultView`, `RequestCodeView.swift` (recipient askEachTime), `SharedAccessGateView.swift`, `SharedWithMeScreen.swift`.
- Thiếu (design 12): **pending-share persistence** — Home row "Sharing X · waiting for Y" (cam), item-row badge SHARING…, Item Detail "Shared with" progress 4-đoạn + Resume, resume sheet stepper 4 bước (Invite sent/Waiting/Confirm safety/Active).
- Thiếu: 10f invite-sent success ("no need to wait" + Nudge via Messages), 9c approval issuing (chờ chu kỳ TOTP mới), 9b shared-gate offline state + auto-recheck.
- Status color language (cam=chờ họ / xanh lá=chờ mình) = Phase 0 VaultStatusBadge/StatusDot.
- Data model: item có thể vừa recipient Active vừa pending song song → participant list per-state (verify model đã hỗ trợ).

## Requirements
- Home: pending-share row (ephemeral, tự mất khi Active/cancelled) — reuse HomeScreen approval-row pattern; KHÔNG đổi header/tab.
- Item list: badge SHARING… trên row item đang pending.
- Item Detail: "Shared with" section với mini progress 4-đoạn + Resume + swipe Cancel invite.
- Resume stepper sheet (12c): 4 bước visual (done/current/todo) + Send via Messages + Check Now (manual poll) + Cancel Invite.
- Invite-sent success (10f): "no need to wait" copy + Nudge via Messages + chip preview.
- Approval issuing (9c): state chờ chu kỳ TOTP mới + countdown + copy "old one never sent".
- Shared-gate offline (9b): offline state + Try Again + auto-recheck copy (network monitor).
- Safety code (4c) + match code (4d) copy chuẩn hoá.

## Related code files
- Modify: `Vaultify/Features/Home/HomeScreen.swift` (pending row — cùng file Phase 1 → **ownership conflict**: gộp vào Phase 1 hoặc sequence sau Phase 1)
- Modify: `Vaultify/Features/ItemDetail/ItemDetailScreen.swift` (Shared-with progress — cùng file Phase 2 → sequence sau Phase 2)
- Modify: `Vaultify/Features/Sharing/ShareAccessSheet.swift`, `NotificationsScreen.swift`, `ApprovalRequestSheet.swift`, `RequestCodeView.swift`, `SharedWithMeScreen.swift`
- Modify: `Vaultify/Features/ItemDetail/SharedAccessGateView.swift`
- Create: `Vaultify/Features/Sharing/ShareResumeStepperSheet.swift` (12c), `ShareInviteSentSheet.swift` (10f) nếu chưa có
- Read: VaultifyCore sharing/participant model, network monitor
- Modify: `Localizable.xcstrings` (EN+VI, format string cho {name}/{item})

## Implementation steps
1. Verify participant model hỗ trợ per-recipient state (Active + pending song song) + có nguồn "pending shares" query.
2. Resume stepper sheet: map 9-bước-protocol nội bộ → 4 nhãn stepper. Actions: Messages/Check Now/Cancel.
3. Invite-sent success sheet: reuse waiting step → thay bằng "no need to wait" + Nudge.
4. Home pending row + item badge SHARING… (SEQUENCE sau Phase 1 do cùng HomeScreen).
5. Item Detail Shared-with progress + Resume + swipe Cancel (SEQUENCE sau Phase 2).
6. Approval issuing state (9c) trong ApprovalRequestSheet — countdown chu kỳ TOTP.
7. Shared-gate offline (9b) + auto-recheck (network monitor — verify đã có).
8. Localize EN+VI. `make check`.

## Todo
- [ ] Verify participant/pending model
- [ ] Resume stepper sheet (4 bước)
- [ ] Invite-sent success + Nudge via Messages
- [ ] Home pending row + item SHARING badge (after Phase 1)
- [ ] Item Detail Shared-with progress + Resume + Cancel swipe (after Phase 2)
- [ ] Approval issuing countdown (9c)
- [ ] Shared-gate offline + auto-recheck (9b)
- [ ] EN+VI; compile pass

## Success criteria
- Đóng/kill app vẫn thấy pending share ở Home + Item Detail; Resume từ ≥2 entry.
- Check Now manual poll phát hiện accept (không phụ thuộc background push — đó là Phase 6).
- Không gate Approval-Mode theo iCloudSyncEnabled (ràng buộc cứng).
- Status màu nhất quán (cam/xanh lá).

## Risk assessment
- **[Cao]** Chạm CKShare/approval infra — regression sharing. Mitigation: chỉ thêm UI-layer đọc state; không đổi crypto/escrow. Test với share thật (manual QA device).
- **[Cao]** File ownership conflict HomeScreen (Phase 1) + ItemDetailScreen (Phase 2). Mitigation: **sequence** — Phase 5 các sửa 2 file đó chạy SAU khi Phase 1/2 merge; hoặc gộp pending-row vào Phase 1, shared-with vào Phase 2. Lead quyết trước khi parallel.
- **[TB]** Background accept-detection push chưa có → chỉ Check Now. Defer Phase 6.

## Rollback
- Sheet mới = xóa file; Home/ItemDetail diff revert riêng. Không đổi share protocol.

## Next
- Background push accept-detection + auto-nudge → Phase 6 (infra). Cần user cho Q2 nếu đổi score (không liên quan) — N/A.
