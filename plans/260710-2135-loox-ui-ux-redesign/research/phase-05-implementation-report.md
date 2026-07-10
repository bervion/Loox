# Phase 5 — Sharing/Approval pending-persistence: implementation report

Status: DONE_WITH_CONCERNS (1 deviation: swipe-to-cancel not structurally possible outside `List`; Cancel Invite exposed via resume sheet instead — see Deviations).

## Verify trước khi sửa — đã có sẵn (file:line)

- `ItemShareRecord` + `ShareLifecycle` (4 state: inviteSent/accepted/readyForCeremony/active), `SharingStore` (`Vaultify/Features/Sharing/SharingStore.swift:1-123`) — persisted (UserDefaults), monotonic status, đúng data model per-recipient cần cho stepper. KHÔNG sửa file này (chỉ đọc).
- `OwnerShareRefresher` (`Vaultify/Services/Sharing/OwnerShareRefresher.swift`) — background status-only refresh (fire-and-forget), gọi từ `NotificationsScreen.task` sẵn. Dùng làm mẫu cho Check Now trong resume sheet (không sửa file này).
- `NotificationsScreen.outgoingRow` (`NotificationsScreen.swift:149-177`) — "Shares you sent" list đã tồn tại, đã là 1 entry point resume.
- `ShareAccessSheet` resume flow (`ShareAccessSheet.swift:11-17,116-122`) — `resumeEmail` param đã pre-fill recipient + capabilities, không đổi.
- `ItemDetailScreen.sharingSection` (trước sửa: dòng 436-469) — "Shared with" section owner-side ĐÃ tồn tại (list share + tap → `ShareRecipientDetailSheet`), nhưng subtitle chỉ "Active"/"Pending" (2 state), không có progress 4-đoạn/Resume badge.
- `SharedAccessGateView.offline` (trước sửa: dòng 33-35) — offline state ĐÃ tồn tại + auto-recheck (`.task(id: gateKey)` include reachability) — chỉ thiếu title riêng/Try Again/footnote.
- `ApprovalCeremonyService.waitingForFreshWindow(boundaryUnixMs:)` (`ApprovalCeremonyService.swift:25,108-116`) — cơ chế "chờ chu kỳ TOTP mới, không gửi mã cũ" ĐÃ hoạt động thật (không phải mock) — chỉ thiếu UI countdown.
- `CountdownRing` (`TOTPFieldRow.swift:24-57`) — ring TOTP tái dùng được cho 9c, không cần component mới.
- `VaultStatusBadge`/`StatusDot`/`VaultInfoBanner` (Phase 0, uncommitted trong worktree) — dùng trực tiếp, không sửa.
- `NetworkReachabilityMonitor`/`env.reachability` — network monitor thật đã có, auto-recheck 9b không cần code mới, chỉ cần UI.
- `MessageComposeView` — iMessage compose có recipient pre-fill, tái dùng cho Nudge.

## Delivered

### Model mới (1 file)
- `Vaultify/Features/Sharing/ShareStepperModel.swift` — `ShareStepper.steps(for:)` map 4 state `ShareLifecycle` → 4 bước UI (done/current/todo) đúng "9-bước-protocol rút về 4-nhãn" (design insight #1); `ShareStepper.detailSubtitle(for:)` cho Item Detail row; `ShareMiniProgressBar` (4-segment progress + "Step N of 4").

### Resume stepper sheet (12c) — 1 file mới
- `Vaultify/Features/Sharing/ShareResumeStepperSheet.swift` — 4-bước visual (bubble done=success check / current=warning ring+spinner / todo=số mờ), actions: Send Invite via Messages (idempotent `createShare(existingZoneName:)` — không tạo zone/participant mới) | Check Now (cùng CloudKit read status-only mà `OwnerShareRefresher` dùng) | Cancel Invite (cùng `revoke()` pattern 2 nơi khác đã dùng). Khi status = readyForCeremony: CTA đổi thành "Continue to Activate" → mở `ShareAccessSheet(resumeEmail:)` sẵn có để hoàn tất fingerprint/activate (KHÔNG tự re-implement ceremony — giảm rủi ro đụng crypto).
- Là 1 sheet DUY NHẤT dùng chung ở cả 4 entry point: Home pending row, Item Detail "Shared with" pending row, Notifications "Shares you sent" row.

### Invite-sent success (10f) — 1 file mới + sửa ShareAccessSheet
- `Vaultify/Features/Sharing/ShareInviteSentSheet.swift` — hero check icon + "Invite sent to {name}" + copy "No need to wait here…" + status chip preview "Sharing "{item}" · waiting for {name}".
- `ShareAccessSheet.waitingView` (dòng ~592-669): thay nội dung — dùng `ShareInviteSentSheet` ở đầu, "Done" (primary, dismiss thẳng) → "Nudge via Messages"/fallback "Share Invite Link" → "Check Now" (giữ nguyên escape hatch cũ, không regress). Giữ nguyên toàn bộ logic poll/`autoInviteSent`/`pollExhausted` — chỉ đổi presentation.

### Home pending row + item badge (12a) — sửa HomeScreen.swift, VaultItemRow.swift
- `HomeScreen.pendingSharesSection` (trước `approvalAttentionRow`, đúng thứ tự mock: Sharing row rồi Approval row) — dot cam + "Sharing "{item}" · waiting for {name}", tap → `ShareResumeStepperSheet`. Ephemeral tự nhiên: filter `.status != .active` trên `env.sharingStore.shares` (không cache riêng).
- `VaultItemRow.sharingBadge` — "SHARING…" pill cam trên row item có share pending (owned item only, loại trừ `sharedOrigin` khác nhánh).

### Item Detail "Shared with" (12b) — sửa ItemDetailScreen.swift
- `shareRow` mới: pending → subtitle màu cam (`ShareStepper.detailSubtitle`) + `ShareMiniProgressBar` + badge "Resume" (mở `ShareResumeStepperSheet`); active → badge "Active" xanh lá + chevron (mở `ShareRecipientDetailSheet` như cũ, không đổi).

### Approval issuing (9c) — sửa ApprovalRequestSheet.swift
- `issuingView(boundaryUnixMs:)` thay `progress("Preparing a fresh verification code…")` cho case `.waitingForFreshWindow`: `TimelineView` tick 1s tính remaining THẬT từ `boundaryUnixMs` (chính boundary ceremony đang chờ, không phải timer giả lập riêng) → copy cá nhân hoá "so {name} gets a full-life code. The old one is never sent." + `CountdownRing` + "New window in Ns" + footer "This sheet stays open…".

### Shared-gate offline (9b) — sửa SharedAccessGateView.swift
- Case `.offline`: `VaultInfoBanner(.warning, title: "You're offline", text:…, actionLabel: "Try Again")` + footnote "Re-checks automatically…". Auto-recheck logic KHÔNG đổi (đã có qua `gateKey`/reachability).

### Localization
- 37 key mới thêm vào `Vaultify/Localizable.xcstrings` (chỉ `vi` localization, theo convention EN=key có sẵn trong file cho phần lớn entries khác) — script Python qua venv, JSON valid, diff insertion-only (đã kiểm chứng `git diff` chỉ có `+`).
- Tái dùng nguyên văn 7 key đã tồn tại thay vì tạo trùng: "Invite sent", "Waiting for them to accept", "Ready to confirm", "Active", "Check Now", "Done", "Try Again", "Preparing a fresh verification code…", "Still waiting — you can close this screen…", "They've accepted. Their device finishes automatically…", "this item".

## Skip / Deviation (kèm lý do)

1. **Swipe-to-cancel trên Item Detail row (12b)** — SKIP native `.swipeActions`. `ItemDetailScreen` render trong `ScrollView { VStack }`, không phải `List` — `.swipeActions` chỉ hoạt động trong `List` context của SwiftUI. Restructure toàn bộ ItemDetailScreen sang `List` để có 1 swipe action là thay đổi quá lớn/rủi ro cho phase UI-only. Thay thế: Cancel Invite luôn khả dụng qua nút destructive trong `ShareResumeStepperSheet` (mở bằng tap "Resume" trên đúng row đó) — tương đương chức năng, khác cơ chế thao tác.
2. **Invite TTL "6 ngày" (12c countdown expiry line)** — SKIP. Không có TTL constant nào cho CKShare invite trong codebase (`ApprovalConfig` chỉ có `requestTTLMs`/`responseTTLMs` cho approval request, không phải invite). Hiển thị "expires in 6 days" sẽ là fake data không backed bởi state thật → vi phạm "không mock/fake data". Thay bằng "started {ngày giờ thật}" (từ `createdAtUnixMs` có thật).
3. **Bubble "done" fill xanh lá đặc + check trắng (12c mock)** — adapt thành `successSoft` background + check tô success (không fill đặc + white), vì app không có `onSuccess`/`onColor-for-success` token (CLAUDE.md cấm raw white trên themed surface trừ vài case exempt; thêm token mới ngoài scope UI-only phase này).
4. **"Row pending tự biến mất…" caption (12a)** — không render làm copy user-facing (đọc như ghi chú của designer giải thích hành vi, không phải câu copy thật như các block "Copy (EN)" khác trong spec). Hành vi (ephemeral) đã đúng, chỉ không hiển thị caption chữ.
5. **Đợt 4 (4a-4f) safety-code/match-code copy chuẩn hoá** — không đổi, các màn 4a-4e đã hoạt động đúng ngôn ngữ hiện tại (đọc lại thấy khớp mock gần như nguyên văn: "Ready to activate", "Approve with Face ID", "The codes don't match", v.v. đã tồn tại sẵn). Không có delta cần sửa.

## Ràng buộc cứng — verify

- Không gate Approval Mode theo `iCloudSyncEnabled` — không đụng flag này ở đâu trong phase.
- Không đổi CKShare/crypto/escrow protocol — mọi service call dùng lại y nguyên (`createShare` idempotent, `fetchParticipantProfile`, `participantAccepted`, `revoke`) không thêm method mới vào `ApprovalShareService`/`OwnerShareRefresher`/`SharingStore`.
- Không đổi Home header/tab bar.

## Files

Modified: `Vaultify/Features/Home/HomeScreen.swift`, `Vaultify/Features/Vault/VaultItemRow.swift`, `Vaultify/Features/ItemDetail/ItemDetailScreen.swift`, `Vaultify/Features/ItemDetail/SharedAccessGateView.swift`, `Vaultify/Features/Sharing/ShareAccessSheet.swift`, `Vaultify/Features/Sharing/ApprovalRequestSheet.swift`, `Vaultify/Features/Sharing/NotificationsScreen.swift`, `Vaultify/Localizable.xcstrings`.
Created: `Vaultify/Features/Sharing/ShareStepperModel.swift`, `Vaultify/Features/Sharing/ShareResumeStepperSheet.swift`, `Vaultify/Features/Sharing/ShareInviteSentSheet.swift`.

## Compile

`tuist generate --no-open` OK → `xcodebuild … Debug -destination 'generic/platform=iOS Simulator'` → **BUILD SUCCEEDED** (app + embedded `VaultifyAutoFill.appex`), 0 `error:` trong log.

## Unresolved questions

- 3rd-party review nên xác nhận màu/opacity của step-bubble adaptation (mục Deviation #3) khớp design intent đủ mức, hay cần thêm `onSuccess` token vào `AppTheme+Tokens.swift` sau (ngoài scope phase này).
- QA thật trên device cho toàn bộ resume flow (Send via Messages idempotent re-mint, Check Now, Cancel Invite) — chưa test với share thật (chỉ compile-verified), theo đúng risk note của phase file ("Test với share thật (manual QA device)" — nằm ngoài khả năng của agent này).
