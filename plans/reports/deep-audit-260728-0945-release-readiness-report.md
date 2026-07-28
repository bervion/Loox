# Loox Password — Deep Audit & Self-Test Report (Release Readiness)

- v2 (2026-07-28 10:40) — hiệu chỉnh độ chính xác sau red-team review của owner; v1 có 5 claim sai/quá mạnh, liệt kê ở §6.
- Base: `main` @ `3c5ef6a` (v1.43.0, build 67) · Compile PASS (tuist + xcodebuild, sim, `CODE_SIGN_IDENTITY=-`)
- Phạm vi: 12-dimension multi-agent audit (83 findings, 12 verified) + self-test iPhone 11 + iPad Air + verify 4 bug owner báo.
- Inventory findings đầy đủ (self-contained): `deep-audit-260728-1040-medium-low-findings-appendix.md`
- Plan thực thi (đã re-baseline): `plans/260728-0945-release-hardening-and-tutorial/plan.md`

## TL;DR — verdict: NO-GO production

Blocker kỹ thuật đã xác nhận bằng code (không phụ thuộc nhận định): 2 đường mất dữ liệu, 1 phishing gap có test đang codify, 2 CTA chết trên iPhone, sync không chunk batch, snooze không hết hạn, audit engine chấm điểm trên ciphertext. Ngoài ra 1 **external release gate chưa có bằng chứng** (CloudKit Production schema) và pipeline release chưa có JA. Tutorial Core là business track riêng (feature-flag), không phải technical blocker.

---

## 1. Blockers CONFIRMED (code-cited)

| # | Sev | Finding | Bằng chứng code |
|---|---|---|---|
| 1 | HIGH data-loss | Tắt Extra Password chỉ unseal cache live, rồi xóa L2SK vĩnh viễn → sealed fields trong Archive/Trash không bao giờ mở lại được | `Level2SettingsView.swift:320` duyệt `env.repository.items` (live-only); `VaultSession+Level2.swift:80 removeLevel2Wrap()` |
| 2 | HIGH data-loss | Encrypted export bỏ toàn bộ archived items; payload cũng chỉ mang title/category/fields/tags/folderName — mất favorite/pinned/icon/rotation/timestamps/defaultIdentity, và không mang persona/avatar/alias/inbox | `ExportView.swift:105` (`env.repository.items`); `VaultBackup.swift:6 PortableItem` |
| 3 | HIGH security | OS AutoFill matcher có substring clause `other.contains(host)` → promote credential thật trên host lookalike; **test đang codify hành vi này là chấp nhận được** (`evilgoogle.com` pass) trong khi Safari popup matcher đã chặn đúng | `VaultReader.swift:143`; `WebExtensionHostMatchTests.swift:30 testAutoFillSubstringLooseningIsNotInherited` |
| 4 | HIGH sync | CloudKit push không chunk: batch >limit → op fail, records vẫn dirty → retry nguyên batch → fail lặp vô hạn (failure mode đúng bất kể limit chính xác là bao nhiêu; con số 400 chưa có nguồn — cần test thật) | `CloudSyncService.swift:120` |
| 5 | HIGH watchtower | "Remind me later" không bao giờ hết hạn: `effectiveStatus()` (expiry + resurfacing) 0 caller; 3 surface filter cột status thô | `AuditReportStore` + `AuditFixQueueScreen.swift` |
| 6 | HIGH watchtower | Audit engine đưa L2 ciphertext vào chấm điểm: `usernames` chỉ lọc `!isEmpty`, `password: item.passwordField?.value` raw | `VaultAuditSnapshot.swift:48` |
| 7 | HIGH ux | iPhone: "Fix important issues" + "View full report" chết — `NavigationLink(value:)` trong UIKit shell push không có `navigationDestination` (self-test tái hiện 3 lần; iPad path SwiftUI không bị) | `VaultAuditFlowScreen.swift:213/229`; `WatchtowerScreen.swift:232` |
| 8 | HIGH parity | App ship iPad nhưng AutoFill extension `destinations: [.iPhone]` → iPad không có AutoFill/passkey/TOTP fill | `Project.swift:182` |
| 9 | MED data | `deleteFolder` không reassign members trashed/archived → dangling folderId, item vô hình sau restore/unarchive | `VaultRepository+Folders.swift` |
| 10 | MED security | Safari extension không có fallback khi biometric off/invalidated → dead-end | `SafariMessageRouter.swift` |

## 2. External release gates (chưa có bằng chứng — không phải confirmed defect)

- **CloudKit Production schema**: plans/ ghi VaultPasskey, OwnerDevice, DeviceRevocation là outstanding. Chưa verify được từ workspace (cần CloudKit Console). Xử lý: Phase 00 inventory TOÀN BỘ record types/fields/indexes Production vs code, không chỉ 3 type nêu trên. Cho tới khi có bằng chứng: coi là gate chặn release, không ghi nhận là bug.
- **Quick View rollout** 1/5 phase, dark ngoài beta; wire payload thiếu category/title; `CapabilityManifestClient.publishSecondaryMirror` 0 call site. Cần owner decision ship-dark vs hoàn thành (Phase 00).

## 3. Bug owner báo — trạng thái xác minh

1. **Theme light hiển thị dark sau khi dùng nhiều thiết bị** — root cause CHƯA chứng minh. Fact đã kiểm: theme lưu local App Group UserDefaults (`ThemeReader.swift:11`), không có cơ chế iCloud sync theme trong code; RootView có apply ở `onAppear` (`RootView.swift:115`); `forceInterfaceStyle` chỉ áp cho windows connected tại thời điểm gọi (`PlatformAppearance.swift:27`) → cửa sổ attach muộn không nhận override là **cơ chế khả dĩ**, chưa phải kết luận. Hành động: mitigation re-apply khi scene active + window mới (an toàn, rẻ) + owner repro trên 2 máy thật để xác nhận trigger thực.
2. **Email identity hiện ciphertext ở Profile** — symptom CHƯA reproduce được trên commit này: `CredentialIdentityService.swift:86` ĐÃ lọc `isExtraProtected` (v1 cite sai), Profile header đi qua accessor lọc. Các reader thô còn thật: `TotpCardView.swift:77`, `SharedItemsProjection.swift:425`, `CredentialExchangeMapping.swift:48`, `VaultBackup.swift:115`. Hành động: reproduce trên đúng build owner gặp trước khi làm migration; product decision "identity email không protect L2" vẫn giữ (owner đã chốt).
3. **Share kẹt sau popup notification** — flow gap xác nhận trong code: `ApprovalPrerequisites.check()` bắn OS prompt giữa state machine, không pre-permission explainer; khi denied blockedView chỉ có "Check again" (không thể thành công — iOS không hỏi lại) và không có nút mở Settings. Case "bấm Allow xong vẫn kẹt" chưa repro được trên sim — cần owner repro máy thật sau khi fix UX.
4. **Vault init**: flow đúng trên cả 2 máy; bug thật tìm thấy: NameStep bị iOS autocorrect ("Kiyo"→"Koyo") — thiếu `.autocorrectionDisabled()`.

## 4. Self-test còn lại (iPhone 11 + iPad Air, fresh install)

PASS: onboarding E2E (password→name→Kit PDF→theme→done, gating lưu Kit đúng), tạo Login + generator + favicon, item detail copy/reveal/protect menu, Watchtower run + preflight, đổi ngôn ngữ live EN↔JA↔VI, auto-lock Ngay-lập-tức + unlock, iPad sidebar (#181/#182) điều hướng đúng. Bugs nhỏ: "Add Website" không chuyển focus; EN plural "Based on 1 items"; band label "Fairly secure" tại 965/1000; onboarding không có bước Face ID trên sim (cần check máy thật). iPad: vault gốc backup trước test và đã restore nguyên vẹn.

## 5. Localization

- Coverage String Catalog **gần 100%** (1603 key; VI 1602, JA 1593 + 10 key DEBUG chủ ý bỏ; entry rỗng "" không tính). Safari `_locales` 46/46 parity en/vi/ja. Placeholder positional đúng trong phạm vi kiểm tra programmatic.
- VI: đạt release; 10 polish (2 chỗ "Mật khẩu thứ hai"→"Mật khẩu cấp 2", "nhé", hoa/thường "Nhóm/Thùng rác", vài chuỗi dịch cứng).
- JA: production-quality; 1 điểm đáng sửa: "identity"=「ID」(~28 chuỗi) gây hiểu nhầm login ID → 「プロフィール」; 3 low (2要素認証 thống nhất, さん, badge Stale dài).
- Lỗi string thật: `LooxPlanLandingScreen.swift:112` "computer approvals" ≠ catalog key "browser approvals".
- Pipeline: **generator scripts + release.sh + metadata/apple thiếu ja; InfoPlist (Face ID/camera) EN-only cả 3 target.** Fastfile KHÔNG hardcode — tự enumerate thư mục locale (v1 claim sai), nên chỉ cần thêm `metadata/apple/ja/` là fastlane nhận.

## 6. Hiệu chỉnh so với v1 (đối chiếu red-team review 260728-1040)

1. CloudKit Production: v1 ghi như confirmed defect → v2 chuyển thành external gate chưa có bằng chứng (§2).
2. Theme: v1 khẳng định root cause → v2 hạ xuống cơ chế khả dĩ + mitigation, cần repro (§3.1).
3. Identity email: v1 cite `CredentialIdentityService:88/171` là reader thô → sai, file này đã lọc; danh sách reader thô đã sửa (§3.2). Migration chỉ làm sau khi reproduce.
4. Fastfile hardcode EN/VI → sai; chỉ generator/release.sh/metadata thiếu ja (§5).
5. `VaultAuditSnapshot` L2: nâng từ plausible → CONFIRMED (`VaultAuditSnapshot.swift:48`).
6. Extension session: v1 ghi "không có trần tuyệt đối" → code có `maxTTL = 15*60` (`ExtensionSessionStore.swift:27`); phần còn lại của finding (session sống qua app termination trong trần 15') hạ xuống design-review, và mọi absolute expiry mới không được dài hơn trần hiện tại.
7. Wording "i18n 100%" / "không cần lo" → "gần 100%" / "không phát hiện lỗi trong phạm vi đã kiểm tra".
8. 65 medium/low: v1 trỏ journal ngoài workspace → v2 xuất appendix self-contained (`deep-audit-260728-1040-medium-low-findings-appendix.md`).

## Unresolved questions

1. Backup contract: "portable encrypted export" hay "full vault backup"? (chặn thiết kế fix #2 — Phase 00)
2. CloudKit Production inventory (owner, cần Console).
3. Quick View: ship dark hay hoàn thành ladder?
4. Repro theme bug + share-kẹt-sau-Allow trên máy thật (case mạng/2 thiết bị owner tự chạy).
5. Onboarding máy thật có bước Face ID không?
6. Địa chỉ support thật cho Emergency Kit PDF.
