# Planning validation: 2026-10-07

## Phạm vi

Đây là validation của tài liệu và HTML concept, không phải native acceptance. Không sửa Swift/BE, deploy domain, tạo mail thật, chạy simulator tests, ký hoặc phát hành TestFlight trong lượt này.

## Kết quả

- `ak plan validate`: valid, errors null.
- `ak plan status`: 5 phase pending, 0 complete, 34 acceptance tasks chưa triển khai, 0%.
- Whole-plan sweep: đọc lại plan.md, P1–P5, design-spec, linked-services-addendum, audit và review log. Đối chiếu 14 accepted findings (8 High, 6 Medium), cách tách dependency Gate D/Gate M, copy InboxDetail và quan hệ một alias tới nhiều Login. Projection, legacy review có chủ đích, protected-field gate, atomic unlink và chống stale writer được phản ánh trong P3/P5. **0 mâu thuẫn nội bộ còn mở**. Các gate vận hành chưa đạt được liệt kê riêng bên dưới.
- Local Markdown links và source citation ranges đã kiểm tra: không missing/out-of-range. Proposed files tương lai dùng inventory text, không giả làm file đã tồn tại.
- `git diff --check`: pass. Diff hiện tại chỉ là plan/research/preview/journal và annotations ở ba plan lịch sử; không có app code/config production changes.
- Production v14/staging v7 registry snapshots đã verify ECDSA signature bằng public key bundled của app; không dùng private key. D1 read-only query trả 7403, vì vậy server lifecycle/mail readiness không được ghi là đã xác nhận.

## Preview receipt

[Receipt JSON](./preview-validation.json), [validation script](./preview-validation.cjs), [overview screenshot](../assets/preview/overview-375.png), [dịch vụ liên kết](../assets/preview/services-375.png), [chi tiết dịch vụ](../assets/preview/service-detail-375.png), [xác nhận gỡ](../assets/preview/service-unlink-confirmation-375.png), [lọc theo alias](../assets/preview/services-filtered-375.png), [sau khi gỡ](../assets/preview/services-after-unlink-375.png), [create](../assets/preview/create-375.png), [Member](../assets/preview/member-375.png), [Family](../assets/preview/family-375.png), [Inbox dark/large](../assets/preview/inbox-dark-large-430.png).

- Artifact: `design-preview.html`, 59,767 bytes.
- SHA256: `f49d4e94ba28251e97ffdff6382b1736ca5fa602401bfba641118ab2dacd6bc9`; root đối chiếu file cuối với receipt sau linked-services refinement.
- Chromium/Playwright có sẵn: 11 màn × 3 states × 2 themes × 2 widths × 2 font sizes = **264 combinations**, 0 failures.
- Không horizontal overflow, không >1 filled primary, phone buttons ≥44px, Polaris icons resolved. 0 JS errors, 0 requests mạng.
- 16 boolean interaction checks pass: global/per-alias lists, persona và trusted-address filter, mở Login, hủy/xác nhận gỡ, count cập nhật 3→2 và reusable 2→1, Login/alias giữ nguyên, composer reveal, giữ draft khi đổi domain, pending→verified mock, conceal, bỏ stale mock callback, reusable không có website field. Reduce Motion transition 0s.
- 19 screenshots lưu trong `assets/preview/`; root xem overview/create/Member/Family, Inbox dark/large và linked-services list/detail/confirmation. Preview chỉ tiếng Việt; EN/VI/JA native glossary trong design-spec/addendum.
- Script phụ thuộc bundled Node/Playwright/Chromium của máy này và mặc định xuất `/tmp/loox-preview-qa`; đây là QA helper cho concept, không là suite CI của app.
- Công cụ browser từ chối thao tác tab người dùng qua `file://`; không refresh tab bằng cách khác. File HTML cập nhật thành công, người dùng có thể refresh tab đang mở.

## Gate triển khai còn lại

1. D1 permissions/live routing và canary bootstrap hẹp; isolated staging logic không thay production-apex mail proof. Chỉ sau receipt thư thật mới mở server + signed registry email-pw.
2. Default `loox.pw` là đề xuất cho địa chỉ mới sau activation; explicit choice và aliases cũ giữ nguyên.
3. SwiftUI token/theme/Dynamic Type/VoiceOver, actual verification trên physical Debug/TF và Family hai tài khoản iCloud cần P5 receipt. Lab refresh timings là target chưa đo.
4. UI-only release có thể đạt native acceptance khi mail gate chưa đủ; email-pw tiếp tục createDisabled. P1 completion chỉ chứng minh Gate D + runbook M, không chứng minh mail đã hoạt động.

Journal local đã lưu trong docs/journals; không publish AgentWiki vì không có yêu cầu external sharing.
