# Design spec: Email riêng tư và Loox Member

## Mục tiêu

Mọi màn trả lời một câu hỏi, có trạng thái thật và đường đi tiếp. Canvas phẳng, typography SF qua `vaultType`, semantic colors, Space/Radius/Metric/Elevation/Motion hiện có, Polaris. Không thêm hero trang trí, gradient, font hay motion loop. Bản HTML là mô phỏng bố cục và trạng thái, không là pixel contract hay bằng chứng tính năng đã chạy.

## Screen contract

| Màn | Câu hỏi chính | Nội dung đầu tiên | Primary CTA theo state |
|---|---|---|---|
| Email riêng tư | Tôi có địa chỉ nào đang nhận thư? | Readiness nếu cần thao tác, rồi aliases hiện có | Ready: Tạo địa chỉ; chưa inbox: Thêm hộp thư; pending: Xác minh hộp thư |
| Tạo email riêng | Địa chỉ dùng cho đâu và gửi về đâu? | Loại địa chỉ, tên gợi nhớ/website/link Login tùy chọn | Tạo địa chỉ; prerequisite chưa đủ: Xác minh hộp thư |
| Alias detail | Dùng địa chỉ này thế nào? | Full alias + trạng thái + ngữ cảnh dịch vụ | Active: Sao chép địa chỉ; reserved: Kích hoạt; paused: Bật chuyển tiếp nếu capability hợp lệ |
| Dịch vụ liên kết | Địa chỉ này đang được lưu cho mục đăng nhập nào? | Tên dịch vụ/mục, website và alias; scoped persona/alias | Liên kết mục đăng nhập; row mở chi tiết/mục; gỡ là quiet destructive action ở chi tiết |
| Inbox detail | Hộp thư nào đang nhận và đã xác minh chưa? | Full local email + label + verified status + actual routing | Unverified: Gửi email xác minh; pending: Kiểm tra trạng thái; verified/default: không ép CTA |
| Chọn tên miền | Địa chỉ mới có suffix nào? | Hostname chính, selection, lifecycle explanation | Native selection và Xong; chỉ các domain creation-ready |
| Liên kết chia sẻ | Tạo/quản lý link đã gửi | Local link records scoped persona | Tạo liên kết |
| Gửi tới trình duyệt | Gửi mục đang chọn sang browser thế nào? | QR/code instruction, supported viewer, local attempts | Gửi sang trình duyệt |
| Gia đình | Tôi đang chia sẻ gì với ai? | People/share-derived records, pending và active | Chia sẻ với người thân → chọn một mục hoặc Space |

## Email riêng tư: hierarchy

Inline title `Email riêng tư`. Pending/setup/outage là context card đầu màn chỉ khi actionable. Danh sách chia `Địa chỉ theo dịch vụ` và `Địa chỉ dùng nhiều nơi`; không dựng hai card add-only khi rỗng. Một CTA tạo ở thumb zone. Thiết lập hộp thư/domain nằm sau địa chỉ. Notice `Chỉ nhận thư` gọn phía cuối.

Alias row: địa chỉ wrap tự nhiên; subtitle `label → website → Chưa liên kết`; trạng thái text/icon, không chỉ màu. Row mở detail, copy rõ trong detail. Loading giữ dữ liệu đang có; error không biến cả màn thành spinner/alert. Label/value chuyển sang dọc khi hẹp/chữ lớn.

Root có row `Dịch vụ liên kết`/count mở danh sách Facebook/Gmail/GitHub theo các Login đã lưu trong vault. Alias detail mở danh sách lọc địa chỉ đó; mỗi dịch vụ có mở Login và gỡ liên kết rõ scope. Một địa chỉ có thể được lưu cho nhiều Login; projection canonical Private email fields, không tự detect tài khoản bên ngoài. Gỡ chỉ field/pointer liên quan, forwarding/provider account giữ nguyên. Contract, migration/retry và copy: [Linked services addendum](./linked-services-addendum.md).

### Tạo email riêng

- Native sheet, inline title ngắn, Cancel trong toolbar; không thêm Save cạnh một Create khác.
- Chọn `Cho một dịch vụ` hoặc `Dùng nhiều nơi` bằng rows, không hai primary buttons.
- Tên gợi nhớ optional dùng `EmailAlias.label`; website optional dùng normalized `boundDomain`. Tên dịch vụ tự do không lưu như hostname.
- Liên kết Login optional, persona-scoped; `Để sau` là hợp lệ. Khi chưa có Login vẫn có thể tạo alias. `Thêm mục đăng nhập` là đường riêng giữ draft/domain/inbox.
- Tên miền và hộp thư dùng đúng resolver cho mutation; email nhận mặc định mask, có `Hiện email` và route vào đúng inbox detail, verified badge rõ. Chưa verified chuyển CTA sang luồng xác minh rồi resume draft.
- Busy button có geometry ổn định; lỗi inline, giữ reserved/minted checkpoint. Completion chỉ sau activation: alias + `Sao chép địa chỉ`, một quiet `Xong`.
- Detail có `Dịch vụ liên kết` và `Liên kết mục đăng nhập`; tạo Login mới carry alias ID qua sealed draft/restore, lưu canonical field sau save, cancel không bind. Link active alias phải ghi canonical Private email để AutoFill dùng được, giữ username/email thật. Existing primary binding không bị repoint khi liên kết thêm Login; Login có private email khác hướng chọn mục khác. Không auto-allocate trong preview.

### Inbox disclosure và verification

Overview/alias detail mask email nhưng có label và route vào inbox đúng thực tế. Mở dedicated InboxDetail trong vault đã unlock là deliberate disclosure: email đầy đủ mặc định, wrap, selectable/copy; có `Ẩn email`. Đây là justification DNA 9, giúp detail thực hiện đúng vai trò nhận biết địa chỉ. Khi inactive/lock/exit conceal ngay; foreground không tự reveal lại. Không thêm Face ID ceremony riêng nếu vault policy hiện tại không yêu cầu.

Pending: một CTA `Kiểm tra trạng thái`, resend quiet có cooldown. Automatic check chỉ indicator nhỏ ở status, silent; manual result có inline feedback phù hợp. Kết quả verified đổi badge và re-enable creation trong cùng observed transaction. Không coi mở email/browser/deep link là proof verified.

Inbox đổi email phải về unverified; actual routing cũ được phân biệt với desired inbox đang chờ. Điều chỉnh đích nhận phải nói đúng scope (alias hay toàn persona), phản ánh tiến độ/partial failure, không hứa đổi mọi alias nếu backend chưa xong.

### Domain

Danh sách hostname là nội dung chính, không display-name tiếng Anh dài. Selection 44pt+, label wrap. Footer: chỉ áp dụng địa chỉ mới. Một domain vẫn là row có giá trị, không chevron giả. Selected domain bị disable giữa form: yêu cầu chọn lại, không silent swap suffix.

Đề xuất sau ops gate: loox.pw primary cho địa chỉ mới, legacy vẫn chọn được. Freeze hostname/domain ID/localPart từ mint checkpoint; routing retry giữ nguyên địa chỉ đã mint, createDisabled không ép reselect. Chỉ alias chưa mint mới chọn domain khác khi eligibility đổi. Không biến unavailable/unknown domain thành `@relay.looxpassword.com` rồi copy nhầm địa chỉ. Snapshot đi cùng signed mapping proof; historical proof chỉ resolve địa chỉ, không mở creation policy. Snapshot synced không có proof/verified mapping phải unresolved, kể cả device mới offline.

## Shared component anatomy

- Neutral notice: semantic content surface phân biệt grouped canvas ở cả Day/Night/custom theme; `Radius.sm`, `Space.s4` interior, icon gap `Space.s3`, title `.subhead`, body `.footnote`. Title/body đầy đủ, không opacity làm nội dung thiết yếu khó đọc. Shared `VaultInfoBanner` variant chịu trách nhiệm.
- Actionable banner có cause + next step và tối đa một action, không biến receive-only guidance thành error/warning lớn. Content copy theo feature, không reuse câu về relay cho Browser/Links.
- Form/value row: leading label và value trailing chỉ khi đủ chỗ; adaptive vertical khi long value/AX. Email/domain không `lineLimit(1)` ép `…`.
- Mỗi state tối đa một filled primary `controlLarge`, một quiet secondary. Actions ít dùng trong menu; destructive đúng một lần, confirmation đúng scope.
- Member grid giữ Loox membership header/seal; two columns chỉ khi đủ, AX → one column. Status/metric wrap. Navigation không reset stack hay bắt vòng qua Notifications.

## Member roots và truthfulness

Share Links: chọn active-persona item → QuickLinkView. History chỉ local metadata, revoke và open original item. Không Copy lại historical full URL vì fragment không persisted. “Còn thời hạn” là thời gian, không xác nhận chưa mở. Orphan record có xử lý riêng, không lộ item persona khác.

Browser: instructions/QR/code entry và recent attempts; reuse SAS, field selection, Face ID. Recent không replay session. Signed exposure/cohort vẫn quyết định entry; operator outage không upsell. Family: refine people/share-derived detail, chọn item/Space đúng khả năng và resume pending; single-item đi thẳng approval sharing qua explicit entry/prerequisites, không vòng qua Quick Link hoặc giả resumeEmail. Không dựng family membership/role/billing UI giả.

## Copy EN / VI / JA đề xuất

| English source | Tiếng Việt | 日本語 |
|---|---|---|
| New private email | Tạo email riêng | プライベートメールを作成 |
| Create address | Tạo địa chỉ | アドレスを作成 |
| For a service | Cho một dịch vụ | サービス用 |
| Service addresses | Địa chỉ theo dịch vụ | サービス別のアドレス |
| Reusable addresses | Địa chỉ dùng nhiều nơi | 再利用できるアドレス |
| Receiving inbox | Hộp thư nhận | 受信先 |
| Show email | Hiện email | メールアドレスを表示 |
| Hide email | Ẩn email | メールアドレスを非表示 |
| Copy email | Sao chép email | メールアドレスをコピー |
| Link a login | Liên kết mục đăng nhập | ログインを関連付ける |
| Not linked yet | Chưa liên kết | 未関連付け |
| Email domain | Tên miền email | メールドメイン |
| Incoming mail only | Chỉ nhận thư | 受信専用 |
| Replies from your inbox may reveal your real email. | Trả lời từ hộp thư nhận có thể làm lộ email thật. | 受信先から返信すると実際のメールアドレスが相手に伝わる場合があります。 |
| Waiting for verification | Chờ xác minh | 確認待ち |
| Check status | Kiểm tra trạng thái | 状態を確認 |
| Verified | Đã xác minh | 確認済み |
| Share with family | Chia sẻ với người thân | 家族と共有 |
| Create link | Tạo liên kết | リンクを作成 |

Đây là glossary đề xuất; integration owner đối chiếu keys hiện có, plurals và runtime `appString`/title `.inAppLocalized`. Không ship thay đổi với VI/JA còn nghĩa “mỗi trang” khi EN đổi sang service.

## Motion / haptics

Press dùng feedback có sẵn. Copy dùng CopyMorphIcon + ClipboardService một success haptic. Reveal dùng Controlled Reveal nếu phù hợp, conceal tức thời. Pending→verified crossfade `Motion.standard` trong cùng vùng status; `.vault(_, reduceMotion:)` instant. CTA loading giữ kích thước. Selection dùng tap một lần từ owner/service. Navigation, scroll, foreground refresh không haptic. Không page-load stagger, parallax, confetti hoặc animation delay auth/network result.

## Acceptance theo từng màn

Ghi câu trả lời adversarial cho protagonist, every text, every control, every shape/space và every state. Kiểm tra 375/430pt, default/XL/AX XXL, EN/VI/JA, Day/Night/custom theme+7 accents, live theme switch, increased contrast, Reduce Motion/Transparency, VoiceOver. Thử email/domain dài; empty/one/many; no Login; pending/verified/revoked; offline/429/error; background/browser return; record bị xóa khi detail mở. Contrast text thiết yếu 4.5:1, glyph lớn 3:1; hit target 44pt. Không coi bản HTML thay cho native snapshots/device QA.
