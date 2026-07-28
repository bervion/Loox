# Phase 00 — Scope freeze + external gates (CHẶN mọi phase sau)

Mọi phase code chỉ bắt đầu sau khi các quyết định/inventory dưới đây được khóa. Không có code change trong phase này (trừ script inventory read-only).

## 1. CloudKit Production inventory (owner, cần Console)
- Liệt kê TOÀN BỘ record types code đang dùng: `VaultItem`, `VaultFolder`, `VaultPasskey`, `VaultPersona`, `VaultEmailAlias`, `VaultForwardingInbox`, `AuditReport`, `AuditFindingState` (`CloudSyncService.swift:23-30`) + control-plane/sharing types (`OwnerDevice`, `DeviceRevocation`, capability manifest, share zones — grep `recordType` toàn repo trước khi chốt danh sách).
- Đối chiếu từng type: fields + queryable/sortable indexes Production vs code kỳ vọng. Ghi kết quả (có/không/lệch) vào `reports/phase-00-cloudkit-production-inventory.md`.
- Thiếu → deploy schema + smoke test TestFlight 2 máy thật (passkey sync + revoke) trước khi phase 06/07 đóng.

## 2. Backup contract (chặn phase-01 mục 2)
Chọn 1:
- **A. Portable encrypted export** (hiện trạng + archived): mang title/category/fields/tags/folderName/archived. Documented rõ trong UI export: không gồm persona/avatar/alias/pin/rotation/timestamps.
- **B. Full vault backup**: payload version mới mang đủ favorite/pinned/icon/rotation/timestamps/defaultIdentity/avatar + persona/alias/inbox; import tolerant với version cũ.
Quyết định ghi vào phase-01 trước khi code. (Đề xuất: B nếu backup là câu chuyện "chuyển máy không cần iCloud"; A nếu chỉ là export di động.)

## 3. Quick View decision
- Ship dark (verify 0 đường UI cho user thường + gỡ/gắn chủ đích `publishSecondaryMirror`) HAY hoàn thành ladder 5 phase + fix wire payload category/title. Chốt 1, ghi vào phase-07.

## 4. iPad AutoFill scope
- Có ship AutoFill iPad trong release này không (`Project.swift:182 destinations: [.iPhone]`)? Nếu không: docs + App Store metadata phải nói rõ, và đây là known-gap có chủ đích.

## 5. Scope freeze còn lại
- Support contact thật cho Emergency Kit PDF.
- Tutorial/onboarding-polish track: xác nhận là business gate (chặn release) hay track song song sau RC — mặc định theo review 260728-1040: **track riêng, feature-flag, không chặn RC**.
- SF Symbols exception cho onboarding logo: nếu giữ, cập nhật `docs/design-guidelines.md` (authoritative) TRƯỚC khi code phase onboarding.

Exit criteria: 5 mục trên có kết luận ghi thành văn (reports/ hoặc cập nhật trực tiếp phase files), CloudKit inventory có bằng chứng (screenshot/console export).
