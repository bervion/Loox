---
title: "Chiến lược Subscription Loox - Proposal sẵn sàng production"
status: production-ready-proposal
updated: 2026-07-15
scope: [product-packaging, storekit, backend-entitlements, paywall, app-review]
source_of_truth: "Tài liệu này là contract subscription cho đợt ra mắt. App Store Connect là nguồn chuẩn cuối cùng cho giá bản địa hóa và điều kiện nhận ưu đãi."
---

# Chiến lược Subscription Loox - Proposal sẵn sàng production

## 0. Quyết định chốt

Loox ra mắt một nhóm auto-renewable subscription, gồm hai gói trả phí và hai
chu kỳ thanh toán:

- **Loox Plus**: bảo mật cá nhân và mức sử dụng vừa phải cho các dịch vụ kết nối.
- **Loox Max**: sản phẩm mục tiêu cho power user, quy trình riêng tư và chia sẻ.
- Mỗi gói có bản tháng và năm. Max Annual là lựa chọn được đề xuất mặc định.
- Chỉ Max Annual có StoreKit introductory offer miễn phí 7 ngày.
- Chưa làm reverse trial, Lifetime, Family SKU hoặc Apple Family Sharing ở V1.

Cấu trúc thương mại chủ động dùng mô hình gói chim mồi kiểu Apple:

- **Mỏ neo:** Max Monthly thiết lập mức giá tháng của sản phẩm đầy đủ.
- **Gói mục tiêu:** Max Annual được chọn mặc định và có giá trị tổng thể tốt nhất.
- **Gói chim mồi:** Plus Monthly vẫn hữu ích, nhưng chi phí Max Annual quy đổi theo
  tháng phải xấp xỉ bằng hoặc thấp hơn Plus Monthly.
- **Lựa chọn tiết kiệm:** Plus Annual luôn hiển thị minh bạch cho người nhạy cảm về giá.

Cơ chế chim mồi nằm trong cấu trúc giá và cách trình bày thông tin. Copy cho người dùng
không nói về cái bẫy, mất mát, gây lo lắng hoặc tước quyền. Loox là sản phẩm bảo mật;
niềm tin là một phần của sản phẩm.

## 1. Phạm vi và trạng thái sản phẩm

### 1.1 Tiền đề ra mắt

- Chủ sản phẩm xác nhận các feature và backend hỗ trợ đã live production.
- Repo xác nhận client đã có các bề mặt Watchtower, Personas, Private Email, Loox Link,
  Quick View, Approval Mode, AutoFill, Safari và iCloud.
- Cấu hình Release trỏ tới endpoint production.
- Source iOS hiện chưa có StoreKit, paywall, restore purchase hoặc paid-entitlement
  enforcement. Proposal này là contract cho phần việc đó.

Bằng chứng trong project: [AppEnvironment](../../Vaultify/App/AppEnvironment.swift),
[RelayConfig](../../VaultifyCore/Relay/RelayConfig.swift),
[LooxLinkConfig](../../Vaultify/Features/Sharing/LooxLink/LooxLinkConfig.swift),
[QuickViewConfig](../../Vaultify/Features/Sharing/QuickView/QuickViewConfig.swift) và
[codebase summary](../../docs/codebase-summary.md).

“Backend đã live” không đồng nghĩa “đã sẵn sàng kiểm soát subscription.” App Attest,
Relay Principal, capability manifest và rate limit hiện chứng minh quan hệ giữa
app với dịch vụ; chúng không chứng minh Apple subscription đang hoạt động. Các API trả
phí phải có thêm biên entitlement từ App Store.

### 1.2 Định vị sản phẩm

Dùng thống nhất thông điệp:

> **Két của bạn luôn local-first và được mã hóa. Các dịch vụ kết nối là tùy chọn và
> chỉ dùng dữ liệu cần thiết để cung cấp dịch vụ.**

Trước khi phát hành subscription, bỏ các tuyên bố tuyệt đối như “zero backend,”
“kết nối mạng duy nhất là kiểm tra rò rỉ,” hoặc “không có subscription.” Vault vẫn
local-first, còn Private Email, Loox Link và Quick View là các dịch vụ opt-in có
trust boundary riêng.

## 2. Nguyên tắc không thương lượng

1. **Không paywall quyền sở hữu vault.** Đọc, copy, AutoFill, backup, import, export
   và recovery luôn dùng được khi không đăng ký.
2. **Không giới hạn số password, passkey, TOTP, note, thẻ hoặc identity đã lưu.**
3. **Không che giấu rủi ro bảo mật nghiêm trọng.** Free thấy được credential nào bị
   ảnh hưởng bởi finding Critical/High. Gói trả phí bán continuous monitoring, quy
   trình sửa đầy đủ, lịch sử và hiệu quả thao tác.
4. **Mỗi gói trả phí phải tự có giá trị.** Plus là sản phẩm bảo mật cá nhân tử tế,
   dù vị trí của nó giúp tăng chuyển đổi Max Annual.
5. **Không dùng “unlimited” cho dịch vụ có quota ẩn.** Feature dùng backend phải công
   bố hạn mức.
6. **Lỗi kiểm tra entitlement không bao giờ được xóa hoặc sửa dữ liệu người dùng.**
7. **Service health và paid entitlement là hai trạng thái độc lập.** Người đã trả phí
   gặp outage phải thấy trạng thái dịch vụ, không thấy một paywall khác.
8. **Giá và điều kiện nhận offer lấy từ StoreKit.** UI không hardcode USD/VND và không
   tự giả định user có trial.

## 3. Contract phân gói V1

### 3.1 Bảng feature

| Capability | Loox Free | Loox Plus | Loox Max |
|---|---:|---:|---:|
| Vault item, passkey, TOTP, note, thẻ, identity | Không giới hạn | Không giới hạn | Không giới hạn |
| AutoFill, Safari extension, mở khóa sinh trắc | Có | Có | Có |
| iCloud sync, import/export, backup mã hóa, Emergency Kit | Có | Có | Có |
| Spaces, tags, favorites, archive, generator | Có | Có | Có |
| Watchtower finding Critical/High | Hiện item bị ảnh hưởng + hướng dẫn thiết yếu | Đầy đủ | Đầy đủ |
| Toàn bộ finding, Fix Queue, history/diff, nhắc định kỳ | Không | Có | Có |
| Bộ accent/theme | Cơ bản | Đầy đủ | Đầy đủ |
| Personas | 1 | 3 | Không đặt product cap |
| Private Email alias được giữ | 1 | 10 | 200 |
| Loox Link tạo thành công trong 30 ngày rolling | 3 | 30 | 300 |
| Quick View approve thành công trong 30 ngày rolling | 3 | 30 | 300 |
| Nhận Approval Mode share | Có | Có | Có |
| Recipient được share ra qua Approval Mode | 0 | 1 | 10 |

### 3.2 Định nghĩa quota

- **Alias được giữ** gồm alias active hoặc paused. Xóa vĩnh viễn sẽ giải phóng quota,
  nhưng địa chỉ đó bị burn forever và không bao giờ cấp cho người khác.
- **Loox Link usage** chỉ tính khi server create thành công. Lần thử thất bại không
  trừ quota. Revoke hoặc hết hạn sớm không hoàn lại lượt đã tạo thành công.
- **Quick View usage** chỉ tính khi upload payload đã approve thành công. Scan, resolve,
  cancel, timeout hoặc upload lỗi không trừ quota.
- **Outgoing recipient** là một người nhận đang active. Chia nhiều item cho cùng một
  recipient không tốn thêm recipient seat.
- Quota áp theo logical Loox subscription identity, không theo thiết bị hoặc lượt cài.
- Abuse budget và kill switch của backend độc lập với quota thương mại. Hệ thống có thể
  chặn hành vi lạm dụng dù user chưa chạm quota.

Đây là hạn mức chốt cho V1, không phải lời hứa bất biến. Nếu giảm trong tương lai,
phải grandfather subscriber hiện hữu hoặc chỉ áp dụng sau thông báo rõ. Có thể tăng quota
mà không cần binary mới nếu backend contract hỗ trợ.

### 3.3 Vì sao cấu trúc này bán được Max

- Free đủ mạnh để tạo lòng tin và cạnh tranh với lựa chọn có sẵn trên hệ thống.
- Plus giải quyết trọn một nhu cầu: duy trì bảo mật cá nhân liên tục.
- Max kết hợp quota dịch vụ cao, multi-persona và sharing. Nó rộng hơn Plus rõ ràng,
  không chỉ là “thêm số lượng.”
- Plus Monthly tạo so sánh chim mồi trực tiếp với Max Annual mà không làm Plus trở
  thành gói tệ.
- Plus Annual giữ nhóm người thực sự cần security workflow nhưng chưa cần connected
  services ở mức cao.

## 4. Contract StoreKit và App Store Connect

### 4.1 Subscription group

Chỉ tạo một group:

- **Reference name:** <code>Loox Membership</code>
- **Group localization:** <code>Loox</code> cho EN và VI
- **Family Sharing:** OFF cho toàn bộ product V1

Một group đảm bảo user chỉ có một Loox subscription tại một thời điểm và để Apple xử lý
upgrade, downgrade, crossgrade đúng chuẩn.

### 4.2 Product catalog

| Level | Reference name | Product ID | Chu kỳ | Base price |
|---:|---|---|---|---:|
| 1 | Loox Max Annual | <code>com.bervion.vaultify.subscription.max.annual</code> | 1 năm | USD 34.99 |
| 1 | Loox Max Monthly | <code>com.bervion.vaultify.subscription.max.monthly</code> | 1 tháng | USD 4.99 |
| 2 | Loox Plus Annual | <code>com.bervion.vaultify.subscription.plus.annual</code> | 1 năm | USD 19.99 |
| 2 | Loox Plus Monthly | <code>com.bervion.vaultify.subscription.plus.monthly</code> | 1 tháng | USD 2.99 |

Hai product Max cùng Level 1; hai product Plus cùng Level 2. Apple dùng thứ hạng này để
xử lý quan hệ upgrade và downgrade trong group.

Product ID là định danh lâu dài. Phải chốt namespace và cách đặt tên trước khi tạo trên
App Store Connect; không tạo ID production tạm.

### 4.3 Giá theo storefront

- Dùng giá USD trong bảng trên làm base price.
- Override ban đầu cho Việt Nam:
  - Plus Monthly: 29.000đ
  - Plus Annual: 199.000đ
  - Max Monthly: 49.000đ
  - Max Annual: 349.000đ
- Kiểm tra comparable prices do Apple đề xuất trước launch. Không dùng tỷ giá đơn thuần
  để thay thế purchasing power, thuế và vị thế cạnh tranh.
- Paywall hiển thị tổng tiền thanh toán đã được StoreKit bản địa hóa làm giá chính.
  Giá quy đổi theo tháng và phần trăm tiết kiệm được tính từ <code>Product</code> đang live
  và hiển thị ở cấp phụ.
- Chỉ hiện câu “Max Annual rẻ hơn Plus Monthly khi tính theo tháng” ở storefront mà
  phép tính từ giá StoreKit thực tế chứng minh đúng. Ở Việt Nam, hai mức hiện tại chỉ
  được mô tả là xấp xỉ bằng nhau.

### 4.4 Giả định về proceeds

Không mặc định mọi subscriber đem về 85% nếu chưa xác nhận Small Business Program.
Finance model phải có các kịch bản:

- standard proceeds trong năm đầu,
- proceeds sau một năm trong cùng subscription group,
- Small Business Program khi đã xác nhận enrollment,
- thuế, refund và storefront mix,
- hóa đơn thực tế của relay, Link, Quick View và support.

## 5. Đặc tả paywall

### 5.1 Mô hình trình bày

Dùng phần merchandising mang nhận diện Loox ở phía trên và purchase surface native của
StoreKit ở phía dưới. Ưu tiên <code>SubscriptionStoreView</code> để lấy product bản địa
hóa, xử lý purchase, restore và policy link theo chuẩn Apple.

First viewport chỉ có một protagonist: **Max Annual**.

1. Title ngắn, nói đúng offer.
2. Ba lợi ích cụ thể của Max: Private Email, secure sharing, security maintenance đầy đủ.
3. Chọn Plus hoặc Max.
4. Segmented control “Năm” và “Tháng,” mặc định “Năm.”
5. Một primary action dạng filled.
6. Renewal disclosure ngay dưới action.
7. Restore Purchases, Manage Subscription, Terms of Use và Privacy Policy.

Không tạo bốn pricing card cùng nổi. Plus luôn nhìn thấy nhưng ở visual rank thấp hơn;
Max được chọn mặc định và chu kỳ năm được chọn mặc định. Khi quan hệ giá chim mồi đúng,
hiện một dòng so sánh factual bên dưới Max Annual.

### 5.2 Thông tin bắt buộc trước khi mua

Paywall phải hiện:

- tên subscription,
- chu kỳ thanh toán,
- tổng tiền bản địa hóa sẽ bị charge,
- thời lượng trial chính xác khi đủ điều kiện,
- số tiền và chu kỳ sẽ charge sau trial,
- thông tin auto-renew,
- cách manage hoặc cancel,
- Restore Purchases,
- Terms of Use và Privacy Policy.

Tổng giá năm phải nổi hơn giá quy đổi theo tháng. Không làm con số “mỗi tháng” trông như
số tiền Apple sẽ charge ngay.

### 5.3 Paywall theo ngữ cảnh

Chỉ hiện paywall sau khi intent đã rõ:

- Watchtower: sau khi đã hiện finding Critical/High và item bị ảnh hưởng, offer full
  Fix Queue, history và monitoring.
- Private Email: khi tạo vượt retained-alias quota.
- Loox Link hoặc Quick View: khi chạm rolling quota.
- Approval Mode: khi thêm outgoing recipient vượt gói.
- Personas: khi tạo vượt gói.
- Settings/Profile: có entry “Gói Loox” để user chủ động khám phá và quản lý.

Không hiện purchase prompt:

- ngay lần mở app đầu tiên khi user chưa thấy giá trị,
- trong outage hoặc maintenance,
- cho subscriber đang có entitlement,
- đè lên destructive/recovery flow,
- như một interruption ngay sau security warning.

### 5.4 Chuẩn hình ảnh và copy Loox

- Theo Design System hiện tại và giọng “calm intelligence.”
- Mỗi state chỉ có một filled primary action, không tạo button wall.
- Dùng Polaris icon, semantic color, Dynamic Type, hit target 44pt, EN+VI, VoiceOver,
  Reduce Motion, Reduce Transparency và Increased Contrast.
- Không countdown, fake scarcity, consent chọn sẵn, nút đóng bị che hoặc nhãn
  “Phổ biến nhất” khi chưa có dữ liệu.
- Chỉ dùng “Đáng giá nhất” cho Max Annual khi live price math chứng minh được.
- Khi StoreKit lỗi, giữ nguyên context của user và cho retry; không ám chỉ vault đang
  gặp nguy hiểm.

## 6. Trial, offer và retention

### 6.1 Trial khi launch

- Chỉ cấu hình **7-day free introductory offer cho Max Annual**.
- Product tháng và product Plus không có introductory offer khi launch.
- Eligibility lấy từ StoreKit. Mỗi người chỉ được một introductory offer trong group.
- Action thay đổi theo trạng thái:
  - Đủ điều kiện: “Dùng thử Max miễn phí 7 ngày”
  - Không đủ điều kiện: “Đăng ký Max”
- Disclosure ghi đúng giá năm bản địa hóa sẽ charge sau ngày thứ 7.

Không launch reverse trial 14 ngày do app tự quản. Cách này tạo entitlement system thứ hai,
có thể reset, làm rối quota ownership trên backend và khó giải thích eligibility của Apple.
Nếu thử nghiệm trải nghiệm không cần thẻ sau này, gọi là **Max Preview**, không auto-renew
và dùng quota thấp riêng.

### 6.2 Win-back và promotional offer

- Không có discount always-on khi launch.
- Sau ít nhất 90 ngày có production data, cấu hình win-back offer riêng cho từng product
  đã lapse, ưu tiên product năm.
- Không hiện win-back cho subscriber đang active.
- Không dạy user “cancel để được giảm giá.” Eligibility phải có lapse window và
  wait-between-offers.
- Dùng Apple offer code cho support recovery hoặc campaign được kiểm soát.
- Không thêm external checkout link ở V1; dùng IAP nhất quán giữa các storefront.

### 6.3 Billing Grace Period

Bật Apple Billing Grace Period:

- **16 ngày**
- **Only Paid to Paid Renewals**
- **Production and Sandbox**

Subscriber đang trong Apple grace vẫn có toàn bộ paid access. Đây là billing state của
Apple, khác với service safety window sau khi hết hạn ở mục 8.

## 7. Kiến trúc entitlement

### 7.1 Nguồn quyết định

| Quyết định | Nguồn chuẩn |
|---|---|
| Mở feature Plus/Max on-device | StoreKit 2 transaction/status đã verify |
| Mở backend service | Loox Entitlement Service sau khi verify Apple |
| Quota Private Email/Link/Quick View | Counter trên backend |
| Service hiện có khả dụng hay không | Capability manifest/health state hiện hữu |
| Quyền sở hữu và dữ liệu vault | Vault repository, không bao giờ là subscription state |

CloudKit flag, UserDefaults, local trial date, UI state hoặc product ID do client tự gửi
không được làm nguồn chuẩn cho paid backend access.

### 7.2 Luồng end-to-end

~~~mermaid
flowchart LR
    A["App Store"] --> B["StoreKit 2 trong Loox"]
    B --> C["Local entitlement đã verify"]
    C --> D["On-device feature gates"]
    C --> E["App Group entitlement snapshot"]
    E --> F["AutoFill và Safari targets"]
    B --> G["Apple-signed transaction JWS"]
    G --> H["Loox Entitlement API"]
    H --> I["App Store Server API"]
    A --> J["Server Notifications V2"]
    J --> H
    H --> K["Entitlement và quota record"]
    K --> L["Private Email"]
    K --> M["Loox Link"]
    K --> N["Quick View"]
~~~

### 7.3 Billing identity giả danh

Tạo một UUID ngẫu nhiên <code>subscriptionAccountID</code>, độc lập với email, persona,
alias, vault item hoặc thiết bị. Dùng UUID này làm StoreKit
<code>appAccountToken</code>.

- Lưu an toàn và làm cho nó khả dụng trên các thiết bị Loox của cùng user.
- Không derive từ Relay Principal public key hoặc dữ liệu cá nhân.
- Backend bind nó với <code>originalTransactionId</code> đã verify.
- Restore trên thiết bị khác phải hội tụ về cùng Apple entitlement trước cả khi user
  mở connected service.

### 7.4 Contract verify trên backend

Entitlement API nhận Apple-signed transaction data qua request được App Attest bảo vệ
và kiểm tra:

- chữ ký JWS và certificate chain của Apple,
- tách biệt production với sandbox,
- bundle ID <code>com.bervion.vaultify</code>,
- product ID allowlist,
- transaction ID và original transaction ID,
- <code>appAccountToken</code>,
- expiration, revocation và subscription status,
- ownership type và Family Sharing state,
- xử lý monotonic và idempotent.

Backend chỉ lưu billing projection tối thiểu để authorize dịch vụ: subscription identity,
original transaction ID, product/tier hiện tại, status, effective/expiration date,
Apple signed date cuối cùng và quota counter.

Dùng App Store Server Notifications V2 cho purchase, renewal, renewal failure, grace,
expiration, upgrade, downgrade, refund và revocation. Xử lý notification idempotent,
sau đó reconcile trạng thái mơ hồ bằng Get All Subscription Statuses. Không dùng endpoint
<code>verifyReceipt</code> đã deprecated.

### 7.5 Lifecycle phía client

- Load product từ StoreKit; lỗi load product là store state có thể retry.
- Lắng nghe transaction update trong toàn bộ vòng đời process.
- Verify mọi transaction trước khi cấp entitlement.
- Chỉ finish transaction sau khi đã cấp local entitlement và backend handoff được đưa
  bền vững vào queue.
- Tự restore từ current entitlements và có action Restore Purchases do user chủ động.
- Ghi App Group snapshot tối thiểu cho extension. Purchase UI chỉ nằm trong main app.
- Không downgrade chỉ vì request mạng lỗi. Dựa vào signed date và expiration đã verify,
  sau đó reconcile khi có mạng.

## 8. Upgrade, downgrade, refund và dữ liệu

### 8.1 Contract trạng thái subscription

| Apple/business state | Hành vi Loox |
|---|---|
| Active | Mở đầy đủ theo tier hiện tại |
| Tắt auto-renew nhưng chưa hết kỳ | Giữ đầy đủ tới expiration; hiện renewal date, không nhắc lặp |
| Upgrade Plus lên Max | Mở Max sau transaction đã verify; backend update quota idempotent |
| Đang chờ downgrade Max xuống Plus | Giữ Max tới effective date do Apple quyết định |
| Billing Grace Period | Giữ toàn bộ paid access |
| Billing retry ngoài grace hoặc grace đã hết | Chặn premium action mới; bắt đầu safety wind-down |
| Expired | Về Free on-device; áp dụng service safety wind-down |
| Refunded hoặc revoked | Chặn premium action mới ngay; giữ service state hiện hữu tối đa 72 giờ để bảo vệ user, trừ fraud, abuse, legal hoặc security response cần tắt ngay |
| Tạm thời chưa xác định entitlement | Giữ vault và quyền chưa hết hạn đã verify gần nhất; retry/reconcile, không xóa |

Không hứa ngày proration chính xác trong app. Apple quyết định thời điểm hiệu lực của
upgrade, downgrade và crossgrade.

### 8.2 Phân loại dữ liệu

- **Vault data:** password, passkey, TOTP, note, thẻ, identity, alias record gắn với
  login, persona, space, tag và audit report. Luôn được giữ và export.
- **Service state:** forwarding đang active, outgoing share, Loox Link đang sống và
  Quick View session. Chịu sự điều chỉnh của entitlement và service lifecycle.
- **Billing projection:** trạng thái Apple giả danh. Không trộn vào sealed vault content
  và không được dùng để đọc nội dung vault.

### 8.3 Hết hạn bình thường hoặc downgrade có hiệu lực

- Vault, AutoFill, copy, read, import, export và backup vẫn dùng đầy đủ.
- Resource vượt quota của tier mới được giữ; chỉ chặn tạo mới tới khi usage về trong quota.
- Với alias vượt quota, user tự chọn địa chỉ giữ active. Phần còn lại tiếp tục forward
  **30 ngày**, sau đó pause. Alias record luôn hiện và địa chỉ không bao giờ recycle.
- Loox Link đã tạo hết hạn tự nhiên; không tạo link mới khi vượt quota.
- Quick View session ngắn hạn kết thúc tự nhiên; không approve mới khi vượt quota.
- Outgoing Approval Mode recipient vượt quota có **30 ngày** chuyển tiếp trước khi revoke.
  Nhận share luôn free.
- Watchtower history trả phí vẫn được lưu. Free vẫn thấy item bị finding Critical/High;
  UI history/remediation nâng cao không còn mở.
- Paid visual preference được giữ và khôi phục khi resubscribe, dù app tạm render
  appearance của Free.

### 8.4 Cửa sổ khôi phục

- Resubscribe trong 90 ngày khôi phục service mapping đã pause mà không cần cấu hình lại
  nếu security state còn hợp lệ.
- Sau 90 ngày, local record vẫn còn nhưng destination hoặc share có thể phải verify lại.
- Alias address không bao giờ cấp cho user khác dù đã qua bao lâu.

## 9. Family và sharing

- Giữ Apple Family Sharing OFF cho toàn bộ SKU V1. Apple quy định khi đã bật Family
  Sharing cho một IAP thì không thể tắt lại.
- Approval Mode là feature của Loox, không phải Apple Family Sharing.
- Owner trả phí được share trong outgoing-recipient quota của tier. Recipient dùng Free
  vẫn có thể nhận và sử dụng quyền đã được cấp.
- Chưa bán Family SKU cho tới khi membership, seat ownership, leave/remove,
  purchase-owner transfer và cryptographic group revocation đều hoàn thiện production.
- Không gọi Approval Mode hiện tại là “family subscription.”

## 10. Privacy, security và trust

### 10.1 Privacy disclosure

Trước khi submit:

- Cập nhật Privacy Policy cho connected services tùy chọn và billing linkage giả danh.
- Cập nhật App Privacy theo log và analytics thực tế trên server.
- Nói rõ Private Email xử lý và giữ gì; không ám chỉ email không đi qua hạ tầng Loox.
- Không đưa message body, subject, attachment, vault item name, domain hoặc security
  finding vào subscription analytics.
- Cho phép xóa relay/service data độc lập với xóa local vault.

### 10.2 Security boundary

- App Attest chứng minh app instance hợp lệ; không chứng minh paid entitlement.
- Relay Principal chứng minh logical command ownership; không chứng minh paid entitlement.
- Apple JWS chứng minh purchase state; không thay thế abuse control.
- Entitlement, capability health và abuse policy là ba gate độc lập.
- Backend check quota ở mọi mutation tạo tài nguyên. Counter trên client chỉ để hiển thị/cache.
- Refund, revocation, replay notification, lẫn environment và event tới sai thứ tự là
  test case bắt buộc.

## 11. Đo lường và review thương mại

Dùng App Store Connect subscription analytics làm nguồn thương mại chính. Telemetry bổ
sung của Loox phải thô, tối thiểu và tôn trọng riêng tư.

### 11.1 Metric chính

- tỷ lệ paywall view sang purchase start theo context,
- phân bố purchase completed, pending, cancel và failure,
- tỷ trọng Max Annual trong subscription mới,
- trial start và trial-to-paid,
- Plus-to-Max upgrade,
- annual renewal, voluntary churn, billing recovery và refund,
- win-back conversion sau launch,
- entitlement mismatch và notification processing latency,
- tỷ lệ chạm quota theo tier,
- Private Email deliverability và service availability.

Không thu thập credential nào yếu, bị lộ, đã share, đã mở hoặc gắn với alias nào.

### 11.2 Gate quyết định sau launch

- Review giá và package mix sau 8-12 tuần; không phản ứng theo vài ngày dữ liệu.
- Nếu Plus áp đảo trong khi usage Max khỏe, tăng khác biệt giá trị của Max trước khi
  nghĩ tới việc làm Plus tệ đi.
- Nếu Free-to-paid thấp, tối ưu contextual discovery và trial activation trước khi
  giảm safety baseline của Free.
- Nếu refund hoặc support complaint nhắc tới surprise billing, coi paywall disclosure
  là production defect.
- Nếu quota cao đe dọa deliverability hoặc abuse posture, siết abuse policy trước;
  chỉ đổi quota thương mại đã công bố sau thông báo và grandfather.

## 12. Production launch gates

### App Store Connect

- [ ] Agreements, tax, banking và quyền paid app đã active.
- [ ] Một subscription group và bốn product đã tạo, đủ metadata EN+VI.
- [ ] Max Level 1, Plus Level 2; Family Sharing off.
- [ ] Đã review price và storefront override.
- [ ] Max Annual có intro offer 7 ngày.
- [ ] Billing Grace Period 16 ngày, paid-to-paid, production+sandbox.
- [ ] Terms of Use và Privacy Policy URL hoạt động.
- [ ] Subscription đầu tiên được submit cùng app version và review screenshot.

### App và paywall

- [ ] Load product từ StoreKit; hiện đúng localized price, period và trial.
- [ ] Max Annual mặc định, Plus luôn thấy, lựa chọn tháng truy cập được.
- [ ] Xử lý purchase success, pending, user-cancelled, failure, interrupted, Ask to Buy
  và restricted payment.
- [ ] Restore Purchases và Manage Subscription hoạt động.
- [ ] Subscriber hiện hữu không thấy acquisition paywall.
- [ ] Pass EN+VI, Dynamic Type, VoiceOver, Reduce Motion/Transparency, light/dark và
  nhãn tiếng Việt dài nhất.
- [ ] Free xác định được credential bị finding Critical/High.
- [ ] Outage state không bao giờ bị hiển thị như entitlement/paywall state.

### Backend entitlement

- [ ] Verify Apple-signed transaction; không dùng <code>verifyReceipt</code>.
- [ ] Lưu mapping <code>appAccountToken</code>/<code>subscriptionAccountID</code> và
  original transaction ID.
- [ ] Cấu hình App Store Server Notifications V2 cho production và sandbox.
- [ ] Notification idempotent và an toàn khi tới sai thứ tự.
- [ ] Reconcile qua App Store Server API thành công.
- [ ] Service API enforce tier và server quota; client claim không bypass được.
- [ ] Test end-to-end refund, revoke, expiration, grace, upgrade, downgrade và restore.
- [ ] Dữ liệu production và sandbox được tách biệt vật lý hoặc logic.

### Operations và App Review

- [ ] StoreKit Configuration test pass local.
- [ ] Sandbox matrix pass với nhiều test account.
- [ ] Purchase flow trên TestFlight pass; purchase vẫn thuộc sandbox.
- [ ] App Review notes có đường đi deterministic tới mọi paid feature.
- [ ] Mọi backend feature trả phí truy cập và hoạt động được trong lúc review.
- [ ] Privacy Policy, App Privacy, About copy, README/marketing và support response cùng
  dùng claim local-first + optional services.
- [ ] Đã diễn tập wind-down job, alert, support runbook và kill switch.
- [ ] Finance model dùng Apple proceeds eligibility và service bill thực tế.

Không bật production paywall cho tới khi toàn bộ launch gate trên đều xanh.

## 13. Ngoài phạm vi V1

- Lifetime purchase.
- Reverse trial hoặc Max Preview do app tự quản.
- Apple Family Sharing.
- Family subscription SKU hoặc full-group seat.
- Emergency access/inheritance như một paid promise.
- “Mọi feature tương lai mãi mãi.”
- Service “unlimited” nhưng có quota ẩn.
- External checkout hoặc chiến lược payment link riêng theo vùng.
- Acquisition claim dựa trên giá đối thủ đã cũ.

## 14. Tài liệu Apple

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Human Interface Guidelines: In-app purchase](https://developer.apple.com/design/human-interface-guidelines/in-app-purchase)
- [Offer auto-renewable subscriptions](https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions)
- [In-App Purchase and subscription pricing](https://developer.apple.com/help/app-store-connect/reference/pricing-and-availability/in-app-purchase-and-subscriptions-pricing-and-availability)
- [Set up introductory offers](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions/)
- [Enable Billing Grace Period](https://developer.apple.com/help/app-store-connect/manage-subscriptions/enable-billing-grace-period-for-auto-renewable-subscriptions)
- [Turn on Family Sharing for IAP](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/turn-on-family-sharing-for-in-app-purchases)
- [Set up win-back offers](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-win-back-offers)
- [Transaction.currentEntitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements)
- [App Store Server Notifications](https://developer.apple.com/documentation/AppStoreServerNotifications)
- [Get All Subscription Statuses](https://developer.apple.com/documentation/AppStoreServerAPI/Get-All-Subscription-Statuses)
- [Validating receipts with the App Store](https://developer.apple.com/documentation/storekit/validating-receipts-with-the-app-store)
