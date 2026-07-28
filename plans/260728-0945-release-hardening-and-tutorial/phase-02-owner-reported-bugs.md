# Phase 02 — Visible broken flows + owner-reported bugs (v2)

Gate: chạy SAU phase-01 (mục 2 chạm Level-2). Plural "Based on %lld items" chuyển sang phase-06 (String Catalog).

## 1. Watchtower CTA chết trên iPhone (HIGH, confirmed self-test)
- Root cause: `NavigationLink(value:)` tại `VaultAuditFlowScreen.swift:213/229` trong màn được push qua UIKit shell (`WatchtowerScreen.swift:232`) không có `navigationDestination(for: WatchtowerCategory.self)`.
- Fix: thay 2 link bằng Button gọi callback `openCategory(...)` truyền từ `WatchtowerScreen` (đi qua đúng paywall gate §5.3). iPad path giữ nguyên.
- Test: manual iPhone — "Fix important issues" mở Fix Queue, "View full report" mở report; iPad regression.

## 2. Share flow — permission UX (confirmed flow gap)
- `ApprovalPrerequisites.swift:33-35` bắn OS prompt giữa state machine; denied → blockedView chỉ "Check again" + không có nút Settings.
- Fix: (a) tách requestAuthorization khỏi `check()` → state `.needsNotificationPermission` hiện pre-permission view trong sheet (mô tả: thông báo dùng để đưa yêu cầu phê duyệt tới owner) rồi mới bắn prompt khi user bấm; (b) sau grant tự re-check + advance; (c) denied → nút "Mở Cài đặt" (`openNotificationSettingsURLString`) + re-check khi scenePhase `.active`; (d) fail-closed ADR-2 giữ nguyên.
- Pre-permission component đặt ở **app layer** (`Vaultify/Features/Components/`), Sharing dùng trước; tutorial/onboarding track tiêu thụ sau.
- Test: sim reset notifications permission, đi lại flow cả 3 nhánh (grant/deny/quay về từ Settings). Case owner "bấm Allow xong vẫn kẹt": sau fix, owner repro máy thật; nếu còn → điều tra tiếp với log.

## 3. Theme light-hiển-thị-dark (mitigation + repro; root cause CHƯA chứng minh)
- Fact: theme local App Group (`ThemeReader.swift:11`), không có iCloud sync theme; `forceInterfaceStyle` chỉ áp windows đang connected (`PlatformAppearance.swift:27`); RootView apply ở `onAppear` (`RootView.swift:115`).
- Mitigation (an toàn, rẻ): re-apply trong `handleScenePhase(.active)` + observe window mới (UIWindow.didBecomeVisibleNotification / scene connect); macOS slice qua platform helper.
- Repro protocol (owner, 2 máy thật): ghi lại điều kiện trigger (cold launch? sau restore/join vault? sau push-launch?) trước/sau mitigation; nếu vẫn tái hiện → mở điều tra mới, KHÔNG coi mitigation là fix.

## 4. Identity email — reproduce trước, migration sau (owner decision giữ nguyên)
- Đã kiểm: `CredentialIdentityService.swift:86` ĐÃ lọc `isExtraProtected`; Profile header lọc qua accessor. Reader thô còn thật: `TotpCardView.swift:77`, `SharedItemsProjection.swift:425`, `CredentialExchangeMapping.swift:48`, `VaultBackup.swift:115`.
- Bước 1 — repro: dựng identity có email `guard2` trên build hiện tại, đi qua Profile/Personal Information/Home identity rows/sidebar để tìm đúng surface owner thấy ciphertext. Ghi kết quả vào reports/.
- Bước 2 — fix theo repro: các reader thô dùng accessor lọc (`VaultReader.username(from:)` mở rộng); chặn Protect L2 cho `kind == .email` của `category == .identity` (UI + guard tầng ghi).
- Bước 3 — migration unseal email identity đang guard2 (one-shot, idempotent, cần L2SK) — CHỈ sau khi bước 1-2 xong và phase-01 mục 1 đã merge (dùng chung transaction pattern).

## 5. Onboarding NameStep autocorrect (MED, confirmed self-test)
- `NameStepView.swift`: `.autocorrectionDisabled()` + `.textInputAutocapitalization(.words)`. Test: gõ "Kiyo" giữ nguyên.

## 6. Editor "Add Website" không chuyển focus (LOW, confirmed self-test)
- `@FocusState` chuyển vào field website mới sau khi thêm row.

## 7. Band label "Fairly secure" tại 965/1000 (LOW)
- Review mapping band→label (800+ nên đọc là mức cao nhất); chốt copy với owner ở PR.

Reports: `plans/260728-0945-release-hardening-and-tutorial/reports/`
