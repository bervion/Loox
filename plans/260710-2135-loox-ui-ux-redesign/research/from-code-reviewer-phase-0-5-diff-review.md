# Code Review — Uncommitted diff phase 0–5 (Loox UI/UX redesign)

Reviewer: code-reviewer · 260710-2238
Scope: 19 file sửa + 5 file mới (VaultInfoBanner, VaultStatusBadge, ShareStepperModel, ShareResumeStepperSheet, ShareInviteSentSheet). Bỏ qua xcstrings ordering churn + docs/app-feature-map (theo yêu cầu).
Compile: `tuist generate` + xcodebuild (app + AutoFill extension) → **BUILD SUCCEEDED**.

## Tổng quan

Chất lượng cao. Phase 5 đúng cam kết "UI-layer only": mọi action reuse service sẵn có, không phát minh protocol mới, không đổi crypto. Localization đầy đủ (đã grep ~70 string mới trong `Localizable.xcstrings` — tất cả có key + VI). Không SF Symbols, màu đi qua ThemeRole/token (AboutInk + QuickActionCard fills là ngoại lệ chủ đích đã khai báo). Không API vượt iOS 17.6 (TimelineView/ShareLink/AttributedString đều ≤16). 0 Critical, 1 High.

## Critical

Không có.

## High

### H1. Home: `.sheet(item:)` gắn vào view có điều kiện → sheet stale tự bật lại
`HomeScreen.swift` — `pendingSharesSection` (chỉ render khi `!pendingOutgoingShares.isEmpty`) mang luôn `.sheet(item: $homeResumeShare)` (dòng ~235).

Failure scenario: user có đúng 1 pending share → mở resume sheet → bấm **Cancel Invite**. `cancelInvite()` gọi `sharingStore.remove()` **trước** `dismiss()` → `pendingOutgoingShares` rỗng → section (kèm sheet modifier) bị gỡ khỏi hierarchy giữa chừng → SwiftUI không nil-out `homeResumeShare` (@State sống ở HomeScreen). Lần sau tạo pending share mới → section xuất hiện lại → sheet **tự present** với record đã bị huỷ (stale): `liveShare` fallback về snapshot chết, Check Now no-op, Cancel Invite lần 2 revoke zone đã revoke → error hiển thị vô nghĩa.

Fix: chuyển `.sheet(item: $homeResumeShare)` lên cấp root của HomeScreen (cạnh các sheet dòng 150–153), hoặc nil `homeResumeShare` trước khi remove. Lưu ý: `approvalAttentionRow` (dòng ~274) có cùng pattern (pre-existing, `onFinished` → `clearPending` cũng gỡ điều kiện) — nên sửa cùng lượt.

## Medium

### M1. ApprovalRequestSheet countdown hardcode chu kỳ 30s
`ApprovalRequestSheet.swift` issuingView: `CountdownRing(remaining: min(remainingSeconds, 30), period: 30)` + copy "next **30-second** window". `ApprovalCeremonyService.period(forStoredValue:)` (dòng 266) parse period thực từ otpauth URI (60s hợp lệ). Với TOTP period ≠ 30: ring sai tỷ lệ (cap 30), copy sai ("New window in 47s" cạnh "30-second window"). `boundaryUnixMs` thì đúng (lấy từ state ceremony — tốt). Fix: thêm `period` vào `case waitingForFreshWindow` hoặc bỏ con số cụ thể khỏi copy + truyền period vào ring. (Đa số TOTP là 30s → impact hẹp, nhưng đây là màn hình "độ chính xác là point".)

### M2. Resume sheet: CTA "Send Invite via Messages" sai ngữ nghĩa cho `.accepted`
`ShareResumeStepperSheet.swift:146-159` — mọi status ≠ `.readyForCeremony` đều rơi vào nudge, kể cả `.accepted` (đã accept, đang chờ device họ publish profile). Message body: "Open this link on your iPhone **to accept**" — misleading, họ đã accept rồi. Nudge chỉ hợp lý cho `.inviteSent`; với `.accepted` nên là copy chờ + Check Now.

### M3. `checkNow()` và `sendNudge()` nuốt lỗi im lặng
`ShareResumeStepperSheet.swift:204-213` — `try?` nuốt lỗi CloudKit: offline → tap Check Now → không phản hồi gì (không error, không "đã kiểm tra, chưa có gì mới"). `sendNudge` dòng 189: `guard setup.shareURL != nil else { return }` — nil URL → silent no-op. User không phân biệt được "chưa accept" với "check thất bại".

### M4. Sau khi activate qua nested sheet, stepper sheet hiển thị state vô nghĩa
`ShareResumeStepperSheet` mở nested `ShareAccessSheet` (Continue to Activate). Ceremony xong → share thành `.active` → quay lại stepper: 4 step done nhưng primary CTA lại là "Send Invite via Messages" (branch else của `readyForCeremony`). Nên auto-dismiss khi `liveShare.status == .active` (hoặc đổi CTA thành Done).

## Low

- **L1.** Home pending row luôn "waiting for {recipient}" kể cả `.readyForCeremony` — lúc đó action thuộc **owner** ("ready to confirm"), copy làm user tưởng vẫn chờ phía kia (`HomeScreen.pendingShareRowLabel`).
- **L2.** `ShareStepper.steps` cho `.accepted`: step 3 là `.todo` → stepper card không có step `.current` nào (không spinner/indicator); mini bar vẫn nói "Step 3 of 4" nhưng segment 3 màu xám. Visual dead-state giữa accepted↔readyForCeremony.
- **L3.** `sendNudge` gửi **raw CKShare URL** thay vì pretty link `invite.looxpassword.com` như flow gốc (`ShareAccessSheet.createShare` mint qua `inviteLinks.createInviteLink`) — recipient nhận link dạng khác, mở qua iCloud web thay vì deep-link app.
- **L4.** `VaultInfoBanner` action button là plain footnote text → hit target < 44pt (design guideline).
- **L5.** `VaultItemRow.hasPendingShare` đọc `sharingStore.shares` trong body → mọi row của mọi list re-render khi store đổi; O(S) mỗi row. S nhỏ + store ít đổi → chấp nhận được, không phải N+1 thật (không I/O per row). Ghi nhận, không cần sửa.
- **L6.** `ShareInviteSentSheet` không phải sheet — là card nhúng trong `ShareAccessSheet.waitingView`. Naming gây nhầm.
- **L7.** `ShareLifecycle` không có state declined/failed (by design): recipient **từ chối** invite → share kẹt `.inviteSent` vĩnh viễn trên Home tới khi owner tự Cancel. Chấp nhận được vì Cancel Invite luôn hiện; ghi nhận cho design 12 follow-up.

## Verified OK (các trọng tâm được giao)

1. **Stepper mapping**: 4 case `ShareLifecycle` (SharingStore.swift:9) map đủ; không có state lỗi để map (xem L7). `updateStatus` **monotonic** (rank guard + fingerprintConfirmed guard, dòng 99–105) → `checkNow` không thể downgrade khi profile fetch miss transient — đúng lo ngại đã kiểm.
2. **Service reuse đúng**: `createShare(recipientEmail:existingZoneName:)` (ApprovalShareService:73), `participantAccepted` (:137), `fetchParticipantProfile` (:153), `revoke(zoneName:inviteRecordName:)` (:385), `inviteLinks.deleteInvite` (:95) — đều sẵn có. `checkNow` là bản mirror chính xác của `OwnerShareRefresher.resolveStatus` (profile trước, accepted sau). ZoneID `CKRecordZone.ID(zoneName:)` default owner đúng — đây là private DB của owner, không phải sharedDB.
3. **Cancel path** mirror đúng revoke flow sẵn có: revoke → GC dropRecord → store.remove; lỗi → giữ record + hiện error (fail-closed).
4. **Ràng buộc cứng**: không chỗ nào gate theo `iCloudSyncEnabled`; không đổi crypto; PolarisIcon toàn bộ; màu qua ThemeRole/derived tokens (`successSoft`/`warningSoft` có trong AppTheme+Tokens.swift:42-43); AboutInk là fixed-surface có chủ đích + comment rõ.
5. **Countdown boundary**: `boundaryUnixMs` lấy thẳng từ `ApprovalCeremonyService.state` (không timer riêng) — đồng bộ với ceremony loop; chỉ label/ring 30s là vấn đề (M1).
6. **Performance HomeScreen**: `PasswordAudit.analyze` vẫn cache trong `@State watchtowerIssueCount`, recompute onAppear + `onChange(items.count)` — không chạy per-render. (Ghi chú pre-existing ngoài scope: edit không đổi count sẽ không refresh badge tới lần appear sau.)
7. **Search highlight**: loop `range(of:)` diacritic/case-insensitive advance bằng `r.upperBound` — không infinite loop, không index crash (range luôn non-empty); AttributedString bridge an toàn.
8. **Localization**: script check 70 string mới → 0 missing key, 0 thiếu VI. `LocalizedStringResource` titles đi qua `VaultSheetScaffold.titleText` → `.inAppLocalized` (:86-89); `ShareStepper` render qua `.inAppLocalized`; plain `Text` literals nhận locale từ `.environment(\.locale)` (VaultifyApp.swift:37).
9. **iOS 17.6**: không API mới cần guard trong diff.
10. **Regression VaultItemRow**: param `highlight` default nil, `hasPendingShare` chỉ hiện khi không phải shared projection (`sharedOrigin == nil` branch) — các list khác không đổi hành vi.

## Recommended actions (ưu tiên)

1. H1 — dời `.sheet(item: $homeResumeShare)` lên root HomeScreen (sửa luôn `approvalAttentionRow` cùng class).
2. M2+M4 — phân nhánh actionButtons theo đủ 4 status (inviteSent: nudge / accepted: chờ + Check Now / readyForCeremony: Continue / active: auto-dismiss).
3. M1 — mang `period` theo `waitingForFreshWindow` hoặc bỏ "30-second" khỏi copy.
4. M3 — surface lỗi/kết quả cho Check Now.
5. Low items: tuỳ lead, không blocking.

## Unresolved questions

- Design 12a có chốt copy riêng cho row `.readyForCeremony` trên Home không (L1)? Nếu có, nên sửa cùng M2.
- `ShareLifecycle` có kế hoạch thêm state declined ở phase sau không (L7)?
