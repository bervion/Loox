# Audit và quyết định cho Loox Member / Email riêng tư

Ngày 2026-10-07. Baseline: `main`, `1101e24b4ad680e9c4df0b5567aa76d02442d40a`, TestFlight 1.56.6 (95). Hai screenshot do người dùng cung cấp là bằng chứng layout thực tế. Audit chỉ đọc; chưa sửa native code hay bật domain.

## Bằng chứng xác nhận

| Vấn đề | Source / dữ liệu | Kết luận và việc triển khai |
|---|---|---|
| Không có loox.pw | Live [production registry](https://config.looxpassword.com/v1/domain-registry): v14, `email-pw=createDisabled`; [staging registry](https://config-staging.looxpassword.com/v1/domain-registry): v7, cùng lifecycle | Không phải thiếu picker. `AuxiliaryDomainRegistry.swift:115` chỉ offer creation-active. Kiểm chứng mail rồi activation hai gate. |
| Môi trường Debug khác TF | `RelayConfig.swift:9-15` API production cả hai; `DomainRegistryClient.swift:14-20` Debug registry staging | Registry cho tài nguyên relay phải theo môi trường API thực tế. Không chuyển backend của các sealed records đang có. |
| Banner không có vùng bọc rõ | `VaultInfoBanner.swift:194-197`; `BuiltinThemes.swift:39` Day secondary và grouped cùng F2F2F6 | Surface info subtle hòa canvas. Sửa semantic treatment ở shared component; không thêm background tùy tiện trong feature. |
| Không biết email nhận đầy đủ | `ForwardingInboxDetailScreen.swift:53`; `ForwardingInboxScreen.swift:143` | Hard-mask cả detail. Dedicated detail dùng local full value khi người dùng chủ động mở; không thêm endpoint plaintext. |
| Xác minh không cập nhật | `ForwardingInboxScreen.swift:75-102` là loop duy nhất; task key không gồm pending identity | Một coordinator được observation cùng source of truth. Foreground, begin-success, visible consumer và manual refresh dùng chung. |
| Badge verified có thể sai sau đổi email | `VaultRepository+ForwardingInboxes.swift:91`; `RelayService.swift:253-257` | Reset verification khi đổi email; persist response phải CAS email/destination identity. Không gán kết quả cũ cho email mới. |
| Preview đích nhận khác mutation | `AliasEditorSheet.swift:46` dùng `destinationEmail`; creation dùng `newAliasDestination`/`resolvedDestination` | Một resolver trả actual và desired routing, không đoán theo persona. |
| Tiêu đề quá dài, Save chết | `AliasEditorSheet.swift:30,54,58,66` | Inline title ngắn, optional Login, busy/error/result state; bỏ `try?` rồi dismiss im lặng. |
| Alias trước Login được hỗ trợ | `EmailAlias.swift:30,116`; `VaultRepository+AliasManagement.swift:31,100`; `RelayService.swift:78,89` | Có label/website/binding optional và mint checkpoint. Không cần schema mới. |
| Link later chưa có từ detail | `AliasSuggestion.swift:27-29`; `ItemEditorScreen.swift:767,793,932` | Unbound+nil website không được suggest. Thêm UI binding, alias-ID handoff rõ và bind chỉ sau save. |
| Member mở sai màn | `LooxHubScreen.swift:243,251`; `NotificationsScreen.swift:18-80` | Share Links và Browser cần dashboard riêng. Notifications giữ vai trò invites/approvals. |
| Family lời mời gây hiểu nhầm | `FamilyScreen.swift:13-19,58`; `ShareSpaceSheet.swift:64-69,179-224` | Đã có root/detail nhưng people là projection shares. CTA chia sẻ phải chọn item/Space và có empty-state actionable. |
| Grid/status bị cắt khi chữ lớn | `LooxHubScreen.swift:365`; `LooxFeatureTile.swift:90` | Adaptive 2→1 columns, status/value wrap, không chữa bằng giảm font. |

Các source trên nằm dưới `/Users/bervion/Developer/Projects/mobile/ios/Vaultify/`; inventory tuyệt đối trong từng phase.

## Domain live: điều đã biết và chưa biết

- Production registry v14 có ba namespace: `relay-main` email active/primary; `email-pw` email createDisabled; `short-pw` short links active/primary. Loox.pw hoạt động cho short links không chứng minh email nhận thư hoạt động.
- Payload production `key_id=cap-2026-02`, `env=production`, `issued_at=1788230553802`, `expires_at=1803782553802`. Document không hết hạn vào ngày audit. Đã verify structure và ECDSA signature của cả production/staging bằng script BE hiện có với **public key bundled của app**; đều OK. Native accept/cache/high-water behavior trên device vẫn là QA P1.
- Registry staging v7 có email-pw createDisabled; staging short-link host khác production. Không đưa staging document vào production trust store.
- BE historical contract: `plans/260831-1004-cloudflare-account-consolidation/phase-03-mail-and-loox-pw.md:159-165` yêu cầu một thư thật tới inbox trước khi mở email-pw. Alias creation cần D1 lifecycle active; ingress còn phục vụ alias có sẵn khi createDisabled. Client và server là hai gate độc lập.
- Đã thử read-only SELECT đúng public routing columns vào DB hiện gắn với production Worker. API trả 7403 (“account not valid or not authorized”); không suy luận D1 lifecycle hôm nay từ file seed cũ. Không truy vấn customer alias/email.
- P1 cần chọn cách bootstrap canary có kiểm soát mà không mở creation chung trước proof: test fixture/operator tool đúng schema/ownership hoặc canary principal hẹp sau đầy đủ auth. Script V1 cũ không phải production-v2/App Attest procedure. Đánh giá và kiểm chứng trước thao tác thật.
- Giữ relay-main nhận thư xuyên suốt. Tăng registry_version từ high-water live, ký đúng key/env, kiểm tra signature/anti-rollback trên app, không replay fixture tháng 7. Staging apex email không tự được bật vì catch-all phục vụ production.

## Contract dữ liệu và privacy

- ForwardingInbox/email, alias label/website/binding đã sealed trong vault. Full email chỉ render/copy cục bộ; không vào diagnostics, analytics, source preview thật hoặc BE payload mới.
- Dedicated inbox detail mở có chủ đích là điểm reveal được giải thích theo DNA 9. Alias overview vẫn mask. Re-hide ngay khi inactive/locked; native privacy shield chặn app-switcher snapshot. Không tự reveal sau foreground.
- Coordinator remote-status có predicate riêng. `CapabilityOperation.read` là local-read, không là phép polling mạng. Tôn trọng user opt-out, lock, scene, connectivity, cooldown và server 429/Retry-After; budget chung vì BE GET có IP limit 60/phút.
- Result chỉ persist nếu inboxID + email/destination identity/revision còn khớp. Email đổi reset verification; actual old routing vẫn phải được hiển thị cho đến khi update backend thành công.
- Begin/resend và GET giữ ordering chung, delayed pending không downgrade verified cùng identity. Unchanged GET là persistence no-op, checking/cooldown ephemeral. Remote pending GET được phép active/degraded/maintenance/disabled, chặn retired/user-off/signed remote-read-disable/offline/locked; GET 200 chỉ noteServiceResponded, không noteSuccess làm mode active. Cancellation release breaker admission, không outage giả.
- Strict-anonymous profile không lộ inbox/alias persona khác. Canonical `items(for:)` loại non-nil missing-folder items; `personaID(forItem:)` hiện fallback default khi folder lookup thất bại nên không đủ chứng minh owner. boundItemId giữ primary/legacy hint; user refinement cho N canonical Login associations, không silently repoint primary khi link thêm.
- Activation giữ reserve→mint checkpoint→destination. Chỉ báo nhận thư được khi activation hoàn tất. Retry không mint trùng; render/preview không network provision.
- Domain/localPart freeze từ mint confirmed, trước activation. Snapshot mới mang signed mapping proof trong sealed alias; historical signature chỉ chứng minh hostname/domainID/env cho address đã mint, không dùng expiry/lifecycle cũ để mở create. Synced snapshot không proof/verified mapping phải unresolved.
- Relay completion patch checkpoint/status trên live alias thay vì whole snapshot trước await, để giữ label/binding vừa đổi và không resurrect deleted records. Lifecycle mutations serialize per alias; identity/revision kiểm lại ở persistence.

## Giới hạn từng Member feature

| Feature | Có thể làm với code hiện hữu | Không được hứa trong UI |
|---|---|---|
| Share Links | Create từ item → `QuickLinkView`; list local record; revoke; mở item gốc | Copy lại full URL từ history (fragment không persisted); server-proof đã mở/chưa mở; full expired history (record bị drop) |
| Browser | Entry chooser QR/code → approval/SAS/fields/Face ID; local attempts/history | Reconnect/replay session hoặc preview plaintext từ history; GA entry khi signed exposure không cho phép |
| Family | People theo outgoing shares; member detail; item/Space sharing; pending resume/revoke | Family roster trước share, group roles, billing seats hoặc remove-member semantics chưa có model |
| Membership | Reuse StoreKit/tier/quota và launch/exposure flags | Bật production purchases, recipient-seat enforcement mới hoặc upsell cho operator outage |

Link records thiếu personaID; root phải scope theo item/persona ownership và xử lý orphan trước khi hiện list/count. Family hiện cũng group xuyên persona theo recipientLabel; plan phải nêu scope rõ, không reuse zone của persona khác.

## Plan cũ và phạm vi kế thừa

- `260710-2135-loox-ui-ux-redesign`: UI phases đa số đã done; phần Private Email/Member được nhận vào plan mới. Native tab/header không nằm trong scope.
- `260707-2046-auxiliary-domains-app-phases`: domain registry/model/picker/authz đã có; A6 nhắc vexla và registry tháng 7 là lịch sử, không dùng làm acceptance hôm nay.
- `260706-2025-private-email-gap-roadmap`: inbox, multi-alias, labels, writeback đã có. Không dựng lại model/service.
- `260727-1308-sharing-family-ux-refactor`: phần “People model done” không chứng minh có independent roster; current source là authority.
- `260716-1546-loox-membership-v1`: commerce launch/seat/theme requirements còn riêng; UI overhaul giữ gates.

## Nguồn thiết kế chính thống

Button label phải nói rõ hành động và phản hồi tiến trình phải nằm gần thao tác. [Apple Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons). Bình thường dùng trạng thái theo ngữ cảnh, tránh alert cho mỗi lần kiểm tra không đổi. [Apple Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts). Motion diễn giải thay đổi và giữ khả năng tiếp cận. [Apple Motion](https://developer.apple.com/design/human-interface-guidelines/motion).

Contract sản phẩm ưu tiên: `AGENTS.md`, `docs/design-guidelines.md`, `docs/design-dna-standard.md`, `Design System/`. Apple HIG hỗ trợ nguyên tắc; token và vocabulary của Loox quyết định implementation.

## Điểm cần chốt khi triển khai

1. Đọc lại D1/Email Routing live và chọn canary bootstrap được kiểm chứng; không bỏ gate vì chưa đủ quyền đọc.
2. Ưu tiên domain mới: đề xuất loox.pw sau activation; câu hỏi người dùng đang mở, không thay aliases đã có.
3. Link/Family persona ownership và orphan policy khóa trong P1; storage hiện tại chưa có roster độc lập.
4. Dữ liệu cũ có alias thiếu immutable hostname snapshot: thiết kế resolver không hiển thị nhầm suffix khi registry thiếu descriptor, rồi test migration.

## User refinement: Linked services

Màn global/per-alias và gỡ khỏi Login theo [addendum](../linked-services-addendum.md). Existing `boundItemId` không đủ N relations. Canonical Private email fields là authoritative; create/reuse hiện có thể dùng `fillEmail` ghi ordinary Email/username tại ItemEditorScreen.swift:767–789, nên dữ liệu cũ cần explicit review/adopt, không tự sửa credential fields. Protected (`guard2`) field là opaque tại DynamicField.swift:12; blind upsert không an toàn. Link/unlink phải atomic/live-row guarded, all relay writebacks revalidate relation generation; no provider account changes/pause API.

## Ghi chú tooling

`ak plan create` và `ak plan add-phase` đã tạo đủ năm phase. CLI cài hiện tại không thêm phase 2–5 vào bảng index Markdown; index giữ bảng do CLI tạo và liệt kê đủ phase bổ sung ngay bên dưới. Không đổi trạng thái triển khai thành complete qua việc viết tài liệu.
