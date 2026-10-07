---
title: "Loox Member and Private Email UX Overhaul"
description: "Đại tu Email riêng tư và các điểm vào Loox Member bằng luồng đúng, trạng thái tin cậy và Design DNA hiện có."
status: in-progress
priority: P1
effort: "8,5–11 ngày công; gồm Linked services refinement, chưa gồm chờ quyền/canary/QA accounts/Apple"
branch: main
tags: [ios, swiftui, ui-ux, private-email, member, bugfix]
blockedBy: []
blocks: [260710-2135-loox-ui-ux-redesign]
created: 2026-10-07
---

# Loox Member and Private Email UX Overhaul

## Overview

Plan dựa trên source `main` sau TestFlight **1.56.6 (95)**, hai ảnh người dùng và kiểm tra registry live ngày 2026-10-07. Phạm vi: Email riêng tư, hộp thư nhận/xác minh, tạo/quản lý địa chỉ, Loox Member và các màn Liên kết chia sẻ, Gửi tới trình duyệt, Gia đình. Giữ nền tảng SwiftUI, token, typography, Polaris và native navigation của app.

Người dùng đã yêu cầu triển khai. Native source của năm phase đã được tích hợp và đang kiểm thử/review; production domain/backend chưa đổi. Checkbox là acceptance có bằng chứng, không đồng nghĩa source chưa viết. [Implementation progress](./reports/implementation-progress.md) tách source, native fixtures và các gate physical/mail/TestFlight còn thiếu.

## Baseline trước triển khai

- `loox.pw` có trong registry production v14 nhưng `email-pw=createDisabled`; app đang lọc đúng. Cần chứng minh nhận thư rồi mở domain ở cả server và registry. Không sửa suffix hardcoded để lách gate.
- Email nhận bị mask cả trong detail; polling xác minh chỉ có ở một màn và bỏ sót pending mới. Preview còn có thể khác inbox được dùng thật.
- Banner có title/body nhưng neutral fill trùng canvas ở Day. Tiêu đề tạo địa chỉ dài và form buộc có Login dù model hỗ trợ alias chưa liên kết.
- Share Links và Send to Browser mở `NotificationsScreen`. Family đã có màn riêng nhưng lời mời thực chất là chia sẻ Space, chưa có family roster độc lập.
- Debug gọi relay production nhưng domain registry vẫn chọn staging theo `#if DEBUG`; phải đồng bộ môi trường trước QA domain.

Chi tiết bằng chứng và giới hạn: [Báo cáo phân tích](./research/audit-and-decisions.md). Hợp đồng màn hình, copy, privacy và motion: [Design spec](./design-spec.md). Bản mô phỏng để xem bố cục: [Design preview](./design-preview.html).

## Goals

| # | Goal | Priority |
|---|------|----------|
| 1 | Xác minh và routing có source of truth đúng; biết chính xác inbox đang nhận | P1 |
| 2 | Domain mới được bật có kiểm chứng, giữ nguyên mọi địa chỉ đã phát hành | P1 |
| 3 | Mỗi Member feature mở màn đặc trưng và thao tác đúng khả năng hiện có | P1 |
| 4 | Copy ngắn, một CTA chính, surface rõ, motion có nghĩa và UI không cắt VI | P1 |

## Phases

| # | Phase | Status |
|---|-------|--------|
| 1 | [Phase 1: Start](./phase-01-start.md) | In progress, Gate D source integrated; Gate M pending |
| 2 | [Phase 2: Recipient State and Verification](./phase-02-recipient-state-and-verification.md) | In progress, coordinator/CAS integrated; acceptance pending |
| 3 | [Phase 3: Private Email Experience](./phase-03-private-email-experience.md) | In progress, UI/linked services integrated; acceptance pending |
| 4 | [Phase 4: Member Feature Destinations](./phase-04-member-feature-destinations.md) | In progress, feature roots integrated; acceptance pending |
| 5 | [Phase 5: Acceptance and Rollout](./phase-05-acceptance-and-rollout.md) | In progress, tests/review/docs; external gates pending |

Phase 1 dự kiến 1–2 ngày công. Tổng effort 8,5–11 ngày công sau yêu cầu Dịch vụ liên kết; P3/P4 có thể song song khi đủ người và đã khóa ownership. Thời gian chờ vận hành/thiết bị không tính vào estimate này.

## Dependencies và thứ tự

`P1 → P2 → P3 → P5`; `P1 → P4 → P5`. P3/P4 có thể song song theo ownership; shared components và `Localizable.xcstrings` có một integration owner. Mỗi thay đổi UI phải có EN/VI/JA ngay khi tích hợp. Kích hoạt `loox.pw` là gate riêng: UI polish có thể ship trước nếu proof mail chưa đạt.

Dependency P1 của native là Gate D; Infra Gate M chạy song song theo runbook P1 và nghiệm thu receipt ở P5. P1 hoàn tất không đồng nghĩa loox.pw đã được bật.

Plan này nhận phần Email riêng tư/Member còn lại của [whole-app plan tháng 7](../260710-2135-loox-ui-ux-redesign/plan.md). Các plan domain, inbox, membership và Family cũ là lịch sử/nguồn reuse, không phải bằng chứng trạng thái live. Không mở lại native tab shell hay thay membership launch flags.

## Success Criteria

Checked native behavior has final source/synthetic executable evidence in the [QA receipt](./reports/tester-261007-2124-native-verification.md). Physical/device/mail and full accessibility/theme matrix acceptance stays unchecked.

- [ ] Quay lại app sau xác minh trên web cập nhật mọi màn liên quan từ kết quả server, không cần thoát app.
- [ ] Email detail đọc/copy được email thật từ vault-local; preview và đích routing thực tế khớp nhau.
- [x] Tạo địa chỉ khi chưa có Login không bị dead end; lỗi không dismiss và retry không mint trùng.
- [ ] `loox.pw` chỉ chọn được sau canary nhận thư thành công; aliases cũ giữ đúng suffix, kể cả khi registry tạm không tải được.
- [x] Member tiles có destination riêng, dữ liệu đúng persona, availability/capability và commerce gates được giữ.
- [ ] Mỗi màn đạt ma trận 375/430pt, Dynamic Type, EN/VI/JA, light/dark, contrast, Reduce Motion/Transparency và VoiceOver.
- [ ] CI/privacy qua; device Debug và TestFlight đạt flow thật; Family qua QA hai tài khoản iCloud.

## Quyết định và điểm cần chốt

- Đề xuất mặc định **loox.pw** cho địa chỉ mới sau kích hoạt, vẫn cho chọn domain cũ. Câu hỏi ưu tiên domain đã gửi; nếu chưa trả lời, đây là đề xuất của plan, chưa phải thay đổi production.
- Địa chỉ theo dịch vụ cho phép label, website và liên kết Login tùy chọn. [Dịch vụ liên kết](./linked-services-addendum.md) có global/per-alias list và gỡ khỏi từng Login; một alias có thể được lưu cho nhiều Login qua canonical Private email fields, boundItemId chỉ là primary/legacy hint. Forwarding và tài khoản provider không đổi khi gỡ.
- Detail hộp thư hiển thị email đầy đủ sau thao tác mở có chủ đích trong vault đã mở khóa; overview và alias detail vẫn mask, có reveal rõ. Conceal khi background/lock/thoát màn.
- Chưa xác minh được D1 live: read-only query trả Cloudflare 7403. P1 phải kiểm chứng quyền/account, lifecycle server và canary bootstrap trước mọi thao tác vận hành.
- Family rollout này dùng quan hệ chia sẻ hiện có; roster độc lập, family billing/role/seat enforcement là scope khác.

## Review

Đã review theo ba lens privacy/security, failure modes và scope/assumptions. 11 findings ban đầu và 3 Linked services follow-up có bằng chứng source đã được đưa vào plan: ownership, immutable domain/proof, polling, race/cancellation, draft/AutoFill, Family entry, atomic unlink và protected/legacy fields. [Chi tiết review](./research/red-team-review.md).

Triển khai đã được người dùng yêu cầu; chưa thực hiện release/version bump mới. Quyền D1/canary mail, physical Debug/TestFlight và Family hai-account vẫn cần receipt riêng trước khi nghiệm thu các gate đó.

## Validation Log

- CLI local plan `Vaultify/261007-1125` và cả năm phase đã cập nhật `in-progress`; Markdown mirror giữ acceptance chưa chứng minh ở trạng thái unchecked. CLI check/uncheck chỉ thao tác cả phase, nên granular evidence được đồng bộ riêng.
- Native source đã thay đổi theo implementation report; backend/domain production chưa đổi trong lượt triển khai UI này. Registry captures ở bước planning đã verify signature bằng bundled public key.
- Preview HTML đã kiểm bố cục/interactions; kết quả chỉ áp dụng mock HTML. SwiftUI/VoiceOver/thiết bị thật vẫn cần P5.
- Whole-plan sweep và source-link verification được chạy sau toàn bộ review edits; receipt cuối trong [validation report](./research/planning-validation.md).

<!-- slug: loox-member-and-private-email-ux-overhaul -->
