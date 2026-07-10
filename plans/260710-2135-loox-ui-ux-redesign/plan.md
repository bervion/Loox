---
title: "Loox UI/UX Flow Completion (13-đợt design)"
description: "Hoàn thiện + tối ưu flow app iOS Loox theo bộ design 13 đợt, dùng design system hiện có, giữ tab bar + Home header."
status: pending
priority: P2
effort: ~10-14d
branch: main
tags: [ios, swiftui, ui-ux, flow, design-system]
created: 2026-07-10
---

# Loox UI/UX Flow Completion

Đối chiếu 13 đợt design (research/) với ~70 màn hiện có → hoàn thiện FLOW, không làm lại giao diện.
Design = tham khảo flow/IA/copy. Mọi UI mới dùng token/typography/ThemeRole/Polaris hiện có. Localize EN+VI. iOS 17.6.

## Ràng buộc cứng (từ user — không đề xuất ngược)
- GIỮ native `TabView` icon-only + Home header hiện tại. Chỉ lấy IA/flow, KHÔNG custom glass shell.
- Không port pixel CSS. Không đổi tab bar. Không gate Approval-Mode theo `iCloudSyncEnabled`.
- Ưu tiên cải thiện flow/UX hơn giao diện. YAGNI/KISS/DRY.

## Gap analysis (phân loại)
- **(a) Flow polish trên màn có sẵn** — phần lớn: Home/Search/Item Detail/Editor/Trash/Onboarding/Lock/Settings/Sharing. Màn đã tồn tại, chỉ tinh chỉnh copy/state/affordance.
- **(b) Màn/section mới** — About Us storytelling (13); pending-share persistence rows (12a/b/c); Generator Passphrase/PIN (nếu chưa có).
- **(c) Đã tốt/bỏ qua** — Night theme (token system đã có light/dark hue); Large Type; Open on Computer; Recovery; Privacy Shield core.
- **(d) Cần backend/service — hoãn/ADR** — Private Email alias thật (loox.email forwarding); device key-provisioning (Vault Key never syncs); Auto-Dark "below brightness"; HIBP live breach counts; Nudge accept-detection background push.

## Phases (mỗi phase độc lập ship + compile được)

| # | Phase | Value/Risk | Status |
|---|-------|-----------|--------|
| 0 | Shared UI primitives (banner/badge/colorized secret/TOTP-orange) | nền tảng, thấp | done |
| 1 | Home + Search flow quick wins | cao / thấp | done |
| 2 | Item Detail · 2FA · Generator · Trash · field tools | cao / thấp-TB | done |
| 3 | Onboarding · Lock · Personas · Space editor | TB / thấp | done |
| 4 | Settings · Appearance · Import/Export · secondary sheets · About Us | TB / thấp-TB | done |
| 5 | Sharing/Approval flow + pending persistence | cao / TB-cao | done (cần QA device) |
| 6 | Infra-dependent (Private Email UI · key-pairing · auto-dark · alias lifecycle) — ADR-gated | TB / cao | deferred |

Phase 0 tạo component dùng chung (file ownership riêng); Phase 1-5 chỉ consume. Phase 6 chờ ADR.

### Ghi chú thực tế (sau P0+P1)
- App hoàn thiện hơn inventory giả định. Đã có sẵn (verified, KHÔNG làm lại): TotpRingView cam ≤5s; QuickActionCard count badges (`totp(count:)`/`watchtower(count:)`); AttentionCell nút "Change"; Search scope chips + actionable empty (SearchScreen.swift:106-148); CountBadge/IconTileBadge (WatchtowerComponents).
- P0 delivered: VaultInfoBanner, VaultStatusBadge+StatusDot, ColorizedSecretText (DesignSystem/Components/).
- P1 delivered: TOTP code cam ≤5s (TotpCardView), trust copy empty Home (+VI), search title highlight (VaultItemRow/RowLink/SearchScreen).
- **Quy trình các phase sau: verify từng requirement với code trước khi sửa — nhiều mục có thể đã tồn tại.**
- P5 delivered (dev agent + review pass): ShareStepperModel + ShareResumeStepperSheet (12c, 4 bước, resume từ Home/Detail/Notifications) + ShareInviteSentSheet (10f no-wait + Nudge) + Home pending row + VaultItemRow SHARING… badge + Detail Shared-with progress + ApprovalRequestSheet issuing countdown (9c) + SharedAccessGate offline (9b). UI-only, service reuse verified. Deviation: Cancel invite = nút trong resume sheet (ItemDetail là ScrollView, không swipe được).
- Code review (research/from-code-reviewer-phase-0-5-diff-review.md): 0 Critical. ĐÃ FIX: H1 (sheet resume dời lên root HomeScreen — stale re-present), M1 (period TOTP thật thay hardcode 30s — thêm periodSeconds vào CeremonyState.waitingForFreshWindow), M2/M4 (actionButtons theo status: active=Done, accepted=no-nudge, inviteSent=nudge), M3 (Check Now có feedback offline/no-change), L1 (Home row "ready to confirm" + dot xanh khi readyForCeremony). Lows còn lại: raw CKShare URL trong nudge, banner action <44pt, naming — chấp nhận.
- CHƯA LÀM: manual QA share flow trên device thật (bắt buộc trước release), Phase 6 (ADR-gated).
- P4: đã có sẵn (verified): Import preview+count CTA, Export segmented+CSV warning+passkey-never (footer "Argon2id + AES-256-GCM" → Q8 đóng), Passkey delete confirm "destroys the private key", Appearance mini theme preview, Settings danger zone + online-features status (CapabilityStatusText), AutoNight có CẢ brightness mode (đã implement qua Telegram engine — Q10 default "cắt" KHÔNG áp dụng vì feature tồn tại & hoạt động, không xoá). P4 delivered: ChangeMP Vault-Key banner + inline mismatch, Export CSV destructive CTA + confirmation, AboutView viết lại thành editorial storytelling (hero hook + refusal ink block + 3 promises + protection + contact support@looxpassword.com single-source qua EmergencyKitInfo.defaultSupportContact; team/timeline placeholder KHÔNG ship theo Q9; +19 VI strings). Composite value row Theme skip (không có accent display-name API, YAGNI).
- P3: đã có sẵn (verified): onboarding order name→kit khớp design (Q3 đóng), inline mismatch + amber no-reset card (CreateMasterPasswordView:46-60), kit Continue gate theo savedPDF, personas policy caption+description, FolderEditorSheet live preview + Unfiled copy. P3 delivered: Lock subtitle giải thích deliberate-lock (requireSlide), Done recap động theo biometricUnlockEnabled (+3 VI strings). Persona policy color-per-level SKIP (không có role màu purple trong ThemeRole; caption text đủ rõ).
- P2: đã có sẵn (verified): TOTPFieldRow warning ≤5s/≤10s, Generator passphrase/PIN + SecretColoring + Avoid-ambiguous, Trash swipe + trust copy, ProtectField no-reset copy, "Seen N times in breaches" detail. `ColorizedSecretText` (P0) trùng `SecretColoring` có sẵn → ĐÃ XÓA, dùng SecretColoring. P2 delivered: TotpCardView username subtitle, k-anon banner ở category Exposed password (reuse string đã localize). Trash "gone in N days" SKIP — app không có auto-purge, hiển thị countdown sẽ sai sự thật.

## Dependencies
- Phase 1-5 **đều** phụ thuộc Phase 0 (shared primitives). Trong 1-5 độc lập file-ownership, chạy song song được sau P0.
- Phase 5 phụ thuộc hạ tầng sharing hiện có; phần accept-detection background push tách sang Phase 6.
- Phase 6 blocked: cần ADR cho Extra-Protection crypto scope, key-provisioning, alias backend, auto-dark brightness.

## Unresolved questions (default an toàn — không block)
1. **HIBP toggle OFF → nhóm Compromised?** Default: ẩn nhóm Compromised khi OFF (không có data). [OK auto]
2. **Watchtower score 0-1200 công thức trọng số?** Default: giữ score hiện tại của app, chỉ map sang 4 band label + màu. KHÔNG đổi thuật toán. [cần user nếu muốn đổi thang]
3. **Onboarding thứ tự Name vs Emergency Kit?** Default: Name TRƯỚC Kit (kit in owner name). Xác nhận với flow hiện tại. [OK auto — sửa nếu app đang ngược]
4. **"Copy key" có tính là đã-lưu-kit để enable Continue?** Default: chỉ Save PDF/Share mới count. [OK auto]
5. **Export tab Encrypted: passkey có kèm?** Default: KHÔNG export passkey ở mọi format (an toàn). [OK auto]
6. **Erase Vault cần bước xác thực 2?** Default: giữ dialog hiện tại + thêm Face ID nếu biometric bật. [OK auto]
7. **About: 10g compact vs 13 storytelling?** Default: 13 = màn About Us chính; giữ 4-câu-tech (10g) làm section "How encryption works" trong cùng scroll. [cần user xác nhận nội dung/team thật]
8. **Copy cipher wording** ("AES-256-GCM" vs ChaCha20 thực tế): verify code trước ship, dùng đúng thuật toán. [cần verify — Phase 4]
9. **Team names / version / sample data** (13c): KHÔNG ship placeholder — cần user cấp data thật hoặc ẩn section. [cần user]
10. **Auto-Dark "below brightness"**: không có public ambient API → default CẮT option này (giữ Off/System/Scheduled). [OK auto — Phase 6]
11. **Extra Protection crypto scope** (per-field key, sync/share tương tác): cần ADR trước impl → Phase 6. Phase 4 chỉ polish UI setup có sẵn. [cần ADR]

## Cần user quyết trước Phase 5-6
- Q2 (nếu đổi thang score), Q7 (About content + team thật), Q9 (sample data), Q11 (Extra Protection ADR).

Chi tiết: phase-00…phase-06.
