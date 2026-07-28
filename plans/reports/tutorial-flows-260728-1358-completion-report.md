# Tutorial flows hoàn thiện + bật flag — Completion Report

- Date: 2026-07-28 · Branch `feat/release-hardening-260728` (23 commits tổng, 2 commit đợt này)
- Verify: iOS compile PASS · macOS compile PASS · **947/947 unit tests PASS** · self-test tay cả 3 flow trên iPhone 11

## Đã làm

### 1. Component guide dạng sheet (nhúng view thật + mũi tên) — đúng ý tưởng ban đầu của owner
`TutorialGuideSheet` (DS layer): step đánh số, mỗi step **nhúng được view thật** và vẽ **mũi tên khuỷu** từ câu hướng dẫn vào đúng view đó. Dùng `TutorialGuideStep(text) { preview }` — preview render non-interactive.

### 2. AutoFill setup guide
- Row "Set up password AutoFill" giờ mở guide TRƯỚC, kết thúc bằng đúng deep link cũ (`ASSettingsHelper`).
- 3 step nhúng **bản dựng lại** của row iOS Settings (AutoFill & Passwords → toggle → Loox trong danh sách provider). Dựng bằng view chứ không phải screenshot: theo theme + ngôn ngữ người dùng, không bao giờ lỗi thời khi đổi dark mode hay thêm ngôn ngữ.
- Bug tự phát hiện khi test: dùng `BrandLogoMark` ra wordmark ngang to đùng → đổi sang `BrandSymbol` vuông cho đúng ngữ cảnh "icon app trong danh sách provider".

### 3. Watchtower tour
2 step: score ring (spotlight tròn) → nút Run Vault Audit (spotlight capsule). Trigger sửa 1 lần sau khi test: ban đầu chỉ chạy trong `.task` nên khi vault còn rỗng thì bỏ lỡ; giờ **arm khi có điểm thật** (`onChange(of: latestPayload?.score)` + guard `!emptyVault`) — chĩa vào vòng "Not checked yet" thì không giải thích được gì.

### 4. Sharing tour
2 step nói thẳng phần quan trọng: giá trị đã trao đi thì không lấy lại được, và yêu cầu phê duyệt đến qua notification.
**Kiến trúc**: sheet vẽ đè overlay của root → thêm `flowIDs` scope cho host. Root host mọi flow trừ `sheetHostedFlowIDs`; share sheet tự host flow "sharing". Đúng một host vẽ tại một thời điểm (có test giữ 2 danh sách không lệch nhau).

### 5. Flag bật + user cũ cũng xem được
- `TutorialFeature.enabled = true`.
- User cũ: store không có bản ghi → tour chạy ở lần mở màn hình kế tiếp, không cần làm gì thêm.
- Settings → **"Show tutorials again"** reset toàn bộ flow (cho người đã skip, hoặc nhận lại vault do người khác lập). `replayAll()` suspend tour đang chạy trước khi xoá — nếu không, tour đó kết thúc rồi ghi đè lại đúng state vừa xoá (có test).

### 6. Localization
19 chuỗi mới, đủ EN + VI + JA.

## Test
`TutorialFlowStateTests` từ 7 → **11 case**: complete/skip không hỏi lại, suspend vẫn eligible, không chồng flow, anchor hợp lệ cho MỌI flow, flow id unique, sheet-hosted id không stale, replayAll, replay-khi-đang-hiện.

## Self-test tay (screenshot từng bước)
- first-run tour: 3 step, spotlight ôm đúng tile, card không che hole.
- watchtower: spotlight tròn ôm ring 964 → capsule ôm nút audit → "Done" không kèm Skip.
- AutoFill guide: 3 step + mũi tên + row dựng lại, "Open Settings" mở đúng iOS Settings.
- sharing: 2 step render TRONG sheet (không bị sheet che).
- Guard `!emptyVault` xác nhận: vault rỗng thì tour Watchtower không chạy.

## Trạng thái macOS (theo yêu cầu: giữ chỗ)
Target `VaultifyAutoFillMac` compile + embed đúng, **không đào sâu thêm**. Runtime (App Group, Touch ID, fill thật) vẫn là gate chưa verify — release iOS/iPad trước như bạn định.

## Unresolved questions

1. Ship Safari extension cho macOS không, hay giữ iOS-only cùng đợt này?
2. Signed RC + QA máy thật (Face ID, AutoFill trong app thứ ba, sharing 2 thiết bị) — gate cuối chưa chạy.
3. Có muốn thêm tour cho Quick View / Private Email không, hay 3 flow này là đủ cho release đầu?
