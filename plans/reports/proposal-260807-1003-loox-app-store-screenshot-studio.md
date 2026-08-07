---
type: design-proposal
date: 2026-08-07
status: proposed
product: Loox Password
scope: App Store screenshots for iPhone and iPad
---

# Proposal: Loox App Store Screenshot Studio

## Tóm tắt

Xây một công cụ HTML chạy local để thiết kế, xem trước, kiểm tra và export toàn bộ screenshot App Store của **Loox Password** cho iPhone và iPad. Công cụ dùng ảnh chụp UI thật của app làm nội dung chính, đặt trong một hệ marketing thống nhất, hỗ trợ EN, VI, JA và export một lần thành ZIP đúng cấu trúc App Store Connect.

Hướng đề xuất: **Calm Editorial Utility**. Cảm giác cần đạt là riêng tư, Apple-native, điềm tĩnh, chắc chắn và cao cấp. Mỗi screenshot chỉ truyền tải một lợi ích. UI thật phải lớn, dễ đọc và luôn là nhân vật chính.

Tên public dùng trong toàn bộ artwork là **Loox Password** hoặc **Loox**. Không dùng tên nội bộ Vaultify trong nội dung marketing.

## 1. Mục tiêu

### 1.1 Mục tiêu sản phẩm

- Giúp người xem hiểu trong ba ảnh đầu rằng Loox bảo vệ vault theo cách riêng tư, quản lý password, passkey và mã xác minh, đồng thời giúp đăng nhập nhanh bằng AutoFill.
- Biến các điểm khác biệt kỹ thuật thành lợi ích dễ hiểu, không dùng ngôn ngữ gây sợ hãi.
- Cho thấy app là sản phẩm Apple-native hoàn chỉnh, không phải một màn kho mật khẩu đơn giản.
- Tạo một hệ có thể tái sử dụng cho version mới, localization mới, Product Page Optimization và Custom Product Pages.

### 1.2 Mục tiêu công cụ

- Preview từng frame theo platform, locale và campaign.
- Thay ảnh capture, copy và theme mà không sửa layout thủ công.
- Export ảnh PNG đúng kích thước, không alpha.
- Một nút **Export all production** tạo toàn bộ ảnh và đóng gói ZIP.
- Phát hiện thiếu capture, thiếu bản dịch, tràn chữ, sai kích thước và trùng tên file trước khi export.
- Sinh contact sheet và manifest để QA nhanh trước khi upload.

## 2. Căn cứ thiết kế và App Store

Proposal bám theo:

- `docs/app-feature-map-ui-ux.md`: sơ đồ điều hướng và toàn bộ bề mặt sản phẩm.
- `docs/design-guidelines.md`: token, typography, color, Polaris icons và nguyên tắc Apple-native.
- `docs/design-dna-standard.md`: một protagonist mỗi frame, calm intelligence, progressive disclosure và kiểm tra đa thiết bị.
- `docs/codebase-summary.md`: trạng thái feature thực tế, bao gồm iPad shell, Watchtower, Sharing, AutoFill, Developer Vault và Emergency Kit.
- `Design System/`: nguồn token và visual language của Loox.

Quy cách Apple được xác minh ngày 2026-08-07:

- App Store Connect cho phép từ 1 đến 10 screenshot, định dạng JPEG/JPG/PNG và không có alpha.
- iPhone 6.9 inch chấp nhận kích thước portrait 1320 × 2868 px.
- iPad 13 inch yêu cầu screenshot nếu app chạy trên iPad; landscape 2752 × 2064 px được chấp nhận.
- Nếu không có app preview, một đến ba screenshot đầu có thể xuất hiện trong kết quả tìm kiếm.
- Screenshot phải cho thấy app đang được sử dụng. Text và image overlay được phép, nhưng không được chỉ là title art, login hoặc splash.
- Apple khuyến nghị localize screenshot và cân nhắc ít nhất một ảnh Dark Mode nếu app hỗ trợ.

Nguồn chính thức:

- [Apple Screenshot Specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [Upload App Previews and Screenshots](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots)
- [Creating Your Product Page](https://developer.apple.com/app-store/product-page/)
- [App Review Guidelines, mục 2.3](https://developer.apple.com/app-store/review/guidelines/)

## 3. Định vị marketing

### 3.1 Lời hứa cốt lõi

> Loox giữ mọi thứ bạn dùng để đăng nhập trong một vault riêng tư, dễ dùng và nằm dưới quyền kiểm soát của bạn.

### 3.2 Thứ tự ưu tiên thông điệp

1. Riêng tư theo mặc định và mã hóa trên thiết bị.
2. Password, passkey và mã xác minh trong cùng một nơi.
3. AutoFill nhanh trong app và Safari.
4. Watchtower chỉ ra việc cần xử lý.
5. Sharing cho phép chia sẻ quyền dùng mà vẫn giữ kiểm soát.
6. Search và Spaces giúp tìm mọi thứ nhanh.
7. Emergency Kit giữ quyền khôi phục trong tay người dùng.

### 3.3 Nguyên tắc claim

- Không nói “không bao giờ rời thiết bị”, vì người dùng có thể bật iCloud Sync hoặc dùng Sharing.
- Có thể nói “mã hóa trên thiết bị” và “chỉ đồng bộ khi bạn chọn”.
- Không quảng bá feature dormant, hidden, beta hoặc chưa qua rollout gate.
- Không dùng “an toàn tuyệt đối”, “không thể bị hack”, “tốt nhất” hoặc claim không thể chứng minh.
- Nếu một frame dùng feature thuộc Loox+ hoặc Loox Max sau khi subscription được bật, artwork phải ghi rõ yêu cầu gói trả phí.
- Copy ngắn, điềm tĩnh, cụ thể. Không dùng dấu chấm than, emoji, em dash hoặc interpunct.

## 4. Art direction

### 4.1 Tên hướng

**Calm Editorial Utility**

### 4.2 Đặc điểm

- Nền marketing phẳng hoặc tonal rất nhẹ, không dùng gradient rực, texture hạt, neon hoặc glow.
- UI app thật chiếm khoảng 62–72% diện tích frame iPhone và 56–64% frame iPad.
- Một headline lớn, một supporting line ngắn, một app composition.
- Dùng system font trên macOS để export ra SF Pro. Không đóng gói hoặc phân phối font Apple.
- Tối đa ba weight trong một frame.
- Device bezel trung tính, mỏng, vẽ bằng CSS. Không dùng mockup 3D bóng hoặc hình phần cứng không cần thiết.
- Không đặt logo lớn lặp lại trên mọi frame. Có thể dùng Loox mark nhỏ như dấu kết ở footer hoặc frame đầu.
- Polaris chỉ dùng trong UI hoặc các glyph marketing lấy từ asset chính thức của app. Không dùng SF Symbols làm ngôn ngữ icon marketing.
- Liquid Glass chỉ xuất hiện trong app capture hoặc control layer của studio. Không dùng glass để trang trí screenshot.

### 4.3 Hệ màu marketing

Tạo token riêng cho studio, được ánh xạ từ semantic palette của Loox:

- `--shot-canvas-light`: nền sáng trung tính.
- `--shot-canvas-soft`: nền accent-soft rất nhẹ.
- `--shot-canvas-dark`: nền ink cho Dark Mode.
- `--shot-text-primary`, `--shot-text-secondary`.
- `--shot-accent`, `--shot-on-accent`.
- `--shot-device-bezel`, `--shot-device-edge`.

Không viết raw color trực tiếp trong từng slide. Mỗi campaign chỉ thay token ở cấp theme.

### 4.4 Typography

- Headline iPhone: 104–124 px ở master 1320 px, semibold hoặc bold, tối đa hai dòng.
- Supporting line iPhone: 42–48 px, tối đa hai dòng.
- Headline iPad landscape: 92–116 px, tối đa ba dòng trong cột copy.
- Supporting line iPad: 38–46 px.
- Dùng `-apple-system`, `BlinkMacSystemFont`, `system-ui`.
- Secret, TOTP hoặc code nằm trong app capture, không dựng lại bằng typography marketing.
- VI là locale dùng để stress-test vì thường dài nhất. JA phải được review line break riêng.

### 4.5 Bố cục theo platform

#### iPhone 6.9 inch, portrait 1320 × 2868

- Headline ở vùng trên, canh trái, giữ một baseline thống nhất trong cả bộ.
- Device/UI bắt đầu sau vùng copy và có thể crop nhẹ ở đáy để tăng tỷ lệ hiển thị UI.
- Safe margin tối thiểu 88 px ở hai cạnh.
- Frame đầu và frame Dark Mode có thể dùng composition screen-full; các frame tính năng dùng crop gần để text trong app đọc được.
- Không đặt nội dung bắt buộc ở 7% ngoài cùng của cạnh trên, dưới và hai bên.

#### iPad 13 inch, landscape 2752 × 2064

- Bố cục 38/62 hoặc 42/58: copy bên trái, UI iPad thật bên phải.
- Dùng regular-width screenshot có sidebar hoặc split-view thật. Không kéo giãn giao diện iPhone.
- Sheet cần nằm đúng kiểu iPad, được center và có context phía sau.
- Safe margin tối thiểu 128 px.
- Mỗi frame phải tận dụng chiều ngang để cho thấy cấu trúc sidebar, list và detail.

### 4.6 Nhịp màu cả bộ

Khuyến nghị:

1. Frame 01: dark hoặc deep ink để tạo dấu ấn privacy.
2. Frame 02: light canvas với accent blue.
3. Frame 03: light/soft canvas, UI AutoFill rõ ràng.
4. Frame 04: Dark Mode thật của Watchtower.
5. Frame 05: light canvas với accent soft.
6. Frame 06: light neutral, tập trung vào search.
7. Frame 07: dark hoặc warm neutral cho Emergency Kit.

Nhịp phải đồng nhất. Không để mỗi slide giống một chiến dịch khác nhau.

## 5. Shot list đề xuất

Khuyến nghị launch với **7 screenshot** thay vì dùng đủ 10. Bảy frame đủ kể chuyện, vẫn giữ chất lượng và khoảng thở. Ba slot còn lại dành cho version sau hoặc Product Page Optimization.

### Frame 01: Privacy hero

- **Protagonist:** vault riêng tư thuộc quyền kiểm soát của người dùng.
- **iPhone visual:** Home có dữ liệu demo sạch, profile row, quick actions và TOTP quick-view. Dùng Dark Mode hoặc deep ink stage.
- **iPad visual:** Home regular-width với sidebar và dashboard.
- **Không dùng:** lock screen, splash hoặc logo-only.

| Locale | Headline | Supporting line |
|---|---|---|
| EN | Your vault stays yours | Encrypted on device. Sync only when you choose. |
| VI | Kho của bạn vẫn thuộc về bạn | Mã hóa trên thiết bị. Chỉ đồng bộ khi bạn chọn. |
| JA | あなたの保管庫は、あなただけのもの | デバイス上で暗号化。同期するかは自分で選べます。 |

### Frame 02: Credentials together

- **Protagonist:** một item có thể chứa password, passkey và 2FA.
- **iPhone visual:** Item Detail của một login demo, secret được che, có passkey row và TOTP đang hoạt động.
- **iPad visual:** list và detail cạnh nhau để cho thấy mật độ native trên màn lớn.

| Locale | Headline | Supporting line |
|---|---|---|
| EN | Everything you sign in with | Passwords, passkeys and verification codes, together. |
| VI | Mọi thứ bạn dùng để đăng nhập | Mật khẩu, passkey và mã xác minh trong cùng một nơi. |
| JA | サインインに必要なものをひとつに | パスワード、パスキー、認証コードをまとめて管理。 |

### Frame 03: AutoFill

- **Protagonist:** đăng nhập nhanh mà không mở và tìm thủ công.
- **iPhone visual:** AutoFill Credential Provider đang chọn login hoặc xác nhận passkey bằng Face ID.
- **iPad visual:** AutoFill sheet thật trên iPad, có context app hoặc Safari phù hợp.
- **Lưu ý:** không dựng giao diện extension giả trong HTML.

| Locale | Headline | Supporting line |
|---|---|---|
| EN | Fill in a tap | Use AutoFill across apps and Safari with Face ID. |
| VI | Điền chỉ với một chạm | Dùng AutoFill trong ứng dụng và Safari với Face ID. |
| JA | 1回のタップですぐ入力 | Face IDで、アプリやSafariに自動入力。 |

### Frame 04: Watchtower

- **Protagonist:** thấy rủi ro và bước xử lý tiếp theo.
- **iPhone visual:** score ring 0–1000, band label, strength distribution và một nhóm issue chính.
- **iPad visual:** Watchtower regular-width, ưu tiên score và issue queue.
- **Theme:** Dark Mode để bộ screenshot thể hiện đầy đủ appearance của app.

| Locale | Headline | Supporting line |
|---|---|---|
| EN | See what needs attention | Find weak, reused and exposed passwords. |
| VI | Biết điều gì cần xử lý | Tìm mật khẩu yếu, dùng lại hoặc đã bị lộ. |
| JA | 対応が必要な項目をひと目で | 弱い、使い回し、漏えいしたパスワードを確認。 |

### Frame 05: Approval sharing

- **Protagonist:** chia sẻ quyền dùng nhưng chủ sở hữu vẫn kiểm soát hành động nhạy cảm.
- **iPhone visual:** Approval Request sheet với mã đối chiếu demo và nút approve bằng Face ID.
- **iPad visual:** sharing configuration hoặc approval sheet centered trên Item Detail.
- **Không dùng:** trạng thái hand-over secret nếu không cần, vì làm loãng claim “keep control”.

| Locale | Headline | Supporting line |
|---|---|---|
| EN | Share access, keep control | Approve sensitive requests with Face ID. |
| VI | Chia sẻ quyền dùng, vẫn giữ kiểm soát | Phê duyệt yêu cầu nhạy cảm bằng Face ID. |
| JA | アクセスを共有。管理はそのまま | 機密性の高いリクエストはFace IDで承認。 |

### Frame 06: Search and organization

- **Protagonist:** tìm credential ngay cả khi vault lớn.
- **iPhone visual:** Search với scope chips và kết quả có Space, tag hoặc operator rõ ràng.
- **iPad visual:** sidebar + search results + detail, hoặc Items với Spaces và Categories.

| Locale | Headline | Supporting line |
|---|---|---|
| EN | Find anything fast | Search across Spaces, tags and item types. |
| VI | Tìm mọi thứ thật nhanh | Tìm theo Không gian, thẻ và loại mục. |
| JA | 必要なものをすぐ検索 | スペース、タグ、項目タイプからすばやく探せます。 |

### Frame 07: Recovery ownership

- **Protagonist:** người dùng giữ quyền khôi phục.
- **iPhone visual:** Emergency Kit success state hoặc PDF preview với key và QR đã thay bằng fixture an toàn.
- **iPad visual:** Emergency Kit centered reading column hoặc PDF preview hợp lý trên iPad.
- **Bảo mật:** không dùng recovery key thật, iCloud account thật hoặc QR có payload hoạt động.

| Locale | Headline | Supporting line |
|---|---|---|
| EN | Recovery stays in your hands | Create an Emergency Kit only you control. |
| VI | Quyền khôi phục nằm trong tay bạn | Tạo Bộ khẩn cấp do chính bạn kiểm soát. |
| JA | 復旧手段も自分の手元に | 自分だけが管理する緊急キットを作成。 |

## 6. Hướng mở rộng sau bộ chính

### 6.1 Product Page Optimization

Apple cho phép thử tối đa ba treatment. Đề xuất chỉ chạy sau khi base set có đủ dữ liệu conversion:

- **Control:** privacy-first như shot list trên.
- **Treatment A:** productivity-first, đưa AutoFill lên frame 01 và Credentials lên frame 02.
- **Treatment B:** security-first, đưa Watchtower lên frame 01 và privacy lên frame 02.

Chỉ thay đổi một hypothesis chính trong mỗi treatment. Giữ icon, copy structure và art direction ổn định để kết quả dễ đọc.

### 6.2 Custom Product Pages

- **Developer Vault:** SSH keys, API secrets, signing identities, provisioning profiles và search operators.
- **Sharing:** Approval Mode, recipient controls, Shared with Me và per-item revoke.
- **Migration:** import từ CSV hoặc backup mã hóa, Emergency Kit và optional iCloud Sync.

Developer Vault phù hợp một custom page hơn là chiếm một slot trong main set dành cho đại chúng.

## 7. Kiến trúc HTML Screenshot Studio

### 7.1 Hình thức

Một static single-page app chạy local trên macOS, không cần backend. Có thể dùng HTML, CSS và TypeScript/JavaScript. Nếu dùng React, output cuối vẫn phải là static bundle mở được bằng local server.

Không phụ thuộc CDN khi export. Toàn bộ JS vendor, icon, capture và asset phải nằm local để kết quả deterministic.

### 7.2 Cấu trúc đề xuất

```text
app-store-screenshot-studio/
├── index.html
├── styles/
│   ├── studio.css
│   ├── screenshot-tokens.css
│   └── screenshot-layouts.css
├── scripts/
│   ├── app.js
│   ├── renderer.js
│   ├── exporter.js
│   ├── validator.js
│   └── contact-sheet.js
├── data/
│   ├── campaigns.json
│   ├── screenshots.json
│   └── device-profiles.json
├── assets/
│   ├── brand/
│   ├── icons/
│   └── captures/
│       ├── iphone-69/{en,vi,ja}/
│       └── ipad-13-landscape/{en,vi,ja}/
├── vendor/
│   ├── html-to-image.js
│   ├── jszip.js
│   └── file-saver.js
├── tools/
│   ├── export-all.mjs
│   └── verify-exports.mjs
└── exports/
```

### 7.3 Data model

Mỗi screenshot là data, không phải một HTML page riêng:

```json
{
  "id": "01-privacy",
  "order": 1,
  "campaign": "base",
  "copy": {
    "en": {
      "headline": "Your vault stays yours",
      "supporting": "Encrypted on device. Sync only when you choose."
    },
    "vi": {
      "headline": "Kho của bạn vẫn thuộc về bạn",
      "supporting": "Mã hóa trên thiết bị. Chỉ đồng bộ khi bạn chọn."
    },
    "ja": {
      "headline": "あなたの保管庫は、あなただけのもの",
      "supporting": "デバイス上で暗号化。同期するかは自分で選べます。"
    }
  },
  "layouts": {
    "iphone-69": "phone-hero",
    "ipad-13-landscape": "tablet-split"
  },
  "theme": "dark",
  "captures": {
    "iphone-69": "01-privacy.png",
    "ipad-13-landscape": "01-privacy.png"
  }
}
```

### 7.4 Device profiles

```json
[
  {
    "id": "iphone-69",
    "label": "iPhone 6.9 portrait",
    "width": 1320,
    "height": 2868,
    "orientation": "portrait",
    "required": true
  },
  {
    "id": "ipad-13-landscape",
    "label": "iPad 13 landscape",
    "width": 2752,
    "height": 2064,
    "orientation": "landscape",
    "required": true
  }
]
```

Có thể thêm profile iPad portrait 2064 × 2752 sau, nhưng không đưa vào production export mặc định nếu chưa có art direction riêng.

## 8. Giao diện của studio

### 8.1 Thanh điều khiển

- Campaign: Base, PPO A, PPO B, custom page.
- Platform: iPhone 6.9, iPad 13 landscape.
- Locale: EN, VI, JA.
- Screenshot: 01–07.
- Preview scale: fit, 25%, 50%, 100%.
- Toggle safe zone, baseline grid, crop bounds và overflow markers.

### 8.2 Canvas

- Preview chính giữa, đúng aspect ratio.
- Render ở kích thước thật trong offscreen stage; UI chỉ scale bằng CSS để xem trước.
- Click vào capture để điều chỉnh crop bằng các preset, không cho kéo tự do quá mức.
- Preset crop: `full-device`, `detail-close`, `sheet-context`, `split-view`.

### 8.3 Inspector

- Headline và supporting copy theo locale.
- Chọn capture đúng platform/locale.
- Chọn stage theme.
- Focal point, scale và offset có giới hạn.
- Cảnh báo copy dài, capture thiếu, alpha input, ảnh quá nhỏ hoặc locale UI không khớp.

### 8.4 Actions

- **Export current PNG**.
- **Export current device**.
- **Export all production**.
- **Export contact sheets**.
- **Run validation**.

Nút export all phải hiển thị progress theo `locale/platform/frame`, cho phép cancel và báo chính xác file lỗi.

## 9. Export engine

### 9.1 Luồng một chạm

1. Chạy validation toàn bộ dataset.
2. Chờ `document.fonts.ready`.
3. Decode toàn bộ ảnh cần dùng.
4. Render từng frame tuần tự trong offscreen container đúng pixel size.
5. Flatten nền thành RGB opaque.
6. Export PNG bằng `html-to-image` hoặc renderer tương đương với pixel ratio 1.
7. Kiểm tra width, height và alpha.
8. Thêm PNG vào JSZip.
9. Sinh `manifest.json`, `validation-report.json` và contact sheets.
10. Download một file ZIP.

Export tuần tự để tránh đỉnh bộ nhớ khi xử lý iPad 2752 × 2064. Sau mỗi frame phải revoke object URL và giải phóng canvas.

### 9.2 Tên và cấu trúc output

```text
loox-app-store-base-2026-08-07/
├── en/
│   ├── iphone-69/
│   │   ├── 01-privacy.png
│   │   └── 07-recovery.png
│   └── ipad-13-landscape/
├── vi/
│   ├── iphone-69/
│   └── ipad-13-landscape/
├── ja/
│   ├── iphone-69/
│   └── ipad-13-landscape/
├── contact-sheets/
├── manifest.json
└── validation-report.json
```

Bộ chính gồm 7 frame × 2 device profiles × 3 locales = **42 PNG**.

### 9.3 Release-grade fallback

Button trong browser là workflow chính. Bổ sung `tools/export-all.mjs` dùng Playwright để CI hoặc designer có thể tái tạo cùng output từ command line. Cả browser và Playwright phải đọc cùng data và component, không có hai implementation layout khác nhau.

`verify-exports.mjs` dùng Sharp hoặc thư viện tương đương để kiểm tra:

- đúng kích thước pixel;
- PNG RGB, không alpha;
- file không rỗng;
- không trùng tên;
- đủ 42 file production;
- metadata không chứa đường dẫn local hoặc dữ liệu nhạy cảm.

## 10. Capture pipeline

### 10.1 Nguyên tắc

Studio chỉ dàn trang marketing. **UI app trong screenshot production phải là capture thật** từ app hoặc extension đang chạy. HTML facsimile chỉ được dùng làm placeholder trong quá trình thiết kế.

Lý do:

- App Review yêu cầu screenshot phản ánh đúng core experience.
- Capture thật giữ typography, safe area, navigation chrome và iPad shell chính xác.
- Tránh thiết kế marketing vô tình hứa một UI chưa tồn tại.

### 10.2 Fixture dữ liệu

Tạo một demo vault cố định dành riêng cho App Store capture:

- Không có email, tên, domain, bank, key hoặc QR thật.
- Dùng `example.com`, `alex@example.com` và tên tổ chức hư cấu.
- Recovery key, TOTP và safety code là fixture vô hiệu.
- QR không chứa payload có thể thực thi.
- Không dùng ảnh avatar người thật.
- Giữ cùng một storyline dữ liệu giữa Home, Item Detail, Search và Watchtower.
- Status bar cố định ở 9:41, pin đầy, không có notification cá nhân.

### 10.3 Matrix capture

Mỗi frame cần capture riêng theo:

- iPhone EN, VI, JA.
- iPad EN, VI, JA.
- light hoặc dark đúng shot list.
- dữ liệu fixture và trạng thái app giống nhau.

Không lấy screenshot EN rồi chỉ thay headline VI hoặc JA nếu phần UI bên trong vẫn là tiếng Anh.

### 10.4 Feature gate

Trước khi capture, xác nhận feature xuất hiện trong artwork:

- đang được bật trong production;
- accessible cho App Review;
- không phụ thuộc DEBUG override;
- không bị rollout gate hoặc backend blocker;
- nếu cần subscription, đã có disclosure đúng.

Quick View, Credential Exchange hoặc subscription surface đang dormant không được xuất hiện trong bộ production hiện tại.

## 11. Validation và QA

### 11.1 Automated validation

- Mỗi frame có headline và supporting line cho EN, VI, JA.
- Mỗi platform/locale có capture tương ứng.
- Headline không quá hai dòng trên iPhone và ba dòng trên iPad.
- Supporting line không quá hai dòng.
- Không có text overflow hoặc crop vào safe zone.
- Ảnh output đúng pixel và opaque.
- Contrast marketing copy đạt WCAG AA.
- Không có remote font, remote image hoặc CDN dependency lúc export.
- Không có dấu chấm than, em dash, interpunct hoặc emoji trong marketing copy.

### 11.2 Visual QA

- Xem contact sheet cả bảy frame theo đúng thứ tự.
- Thu nhỏ về kích thước gần App Store Search để kiểm tra frame 01–03 vẫn đọc được.
- Kiểm tra UI trong device đủ lớn, không trở thành ảnh trang trí.
- Render riêng EN, VI, JA; không chỉ xem fallback EN.
- Kiểm tra Dark Mode có đủ contrast và không lệch theme.
- Kiểm tra iPad là regular-width native layout, không phải iPhone phóng to.
- Kiểm tra device bezel, crop và shadow nhất quán cả bộ.

### 11.3 Adversarial review theo Loox Design DNA

Với từng frame, ghi câu trả lời ngắn cho năm câu:

1. Protagonist là gì và first glance có phục vụ nó không?
2. Copy EN, VI, JA có ngắn, thật và vừa khung không?
3. UI app nào chứng minh claim này?
4. Có chi tiết trang trí nào cạnh tranh với UI không?
5. Capture có phải trạng thái production thật, có fixture sạch và không lộ secret không?

## 12. Tiêu chí nghiệm thu

- [ ] Studio mở được local trên macOS và không cần backend.
- [ ] Preview đủ 7 frame, 2 device profiles và 3 locale.
- [ ] Nút Export all tạo đúng 42 PNG trong một ZIP.
- [ ] iPhone output là 1320 × 2868 px.
- [ ] iPad output là 2752 × 2064 px.
- [ ] PNG không có alpha.
- [ ] Có manifest, validation report và contact sheet.
- [ ] Tất cả screenshot dùng UI capture thật ở production mode.
- [ ] Frame 01–03 truyền đạt privacy, credential coverage và AutoFill khi xem độc lập.
- [ ] Có ít nhất một frame Dark Mode.
- [ ] EN, VI, JA đều được kiểm tra trực quan.
- [ ] Không có dữ liệu thật hoặc secret hoạt động.
- [ ] Không quảng bá feature dormant hoặc claim sai.
- [ ] Bộ ảnh vượt qua checklist Design DNA và App Review metadata.

## 13. Phạm vi bàn giao

### Bắt buộc

- HTML Screenshot Studio.
- Hệ token và ba layout preset chính.
- Dataset base campaign 7 frame, EN/VI/JA.
- Export current, export device và export all.
- ZIP, manifest, validation report và contact sheets.
- Browser exporter và Playwright fallback dùng chung renderer.
- Hướng dẫn thay capture và thêm campaign.

### Không thuộc vòng đầu

- Tự điều khiển simulator để đi tới từng screen.
- Upload tự động lên App Store Connect.
- App preview video.
- Mac App Store screenshot.
- Apple Watch hoặc Vision Pro.
- Tự dịch marketing copy bằng AI khi export.

## 14. Lộ trình triển khai

### Phase 1: Foundation

- Tạo folder studio và screenshot tokens.
- Khai báo device profiles, locale và content schema.
- Tạo fixture/capture naming contract.

### Phase 2: Templates

- Dựng `phone-hero`, `phone-detail`, `tablet-split`, `tablet-sheet`.
- Dựng bảy frame base campaign bằng data.
- Hoàn thiện responsive preview của studio.

### Phase 3: Export

- Export PNG client-side.
- Export all theo queue và đóng gói ZIP.
- Thêm manifest, contact sheet, error report.
- Thêm Playwright và output verifier.

### Phase 4: Production capture và QA

- Chụp matrix 42 capture source theo fixture.
- Thay placeholder bằng UI thật.
- Review EN, VI, JA và iPad regular-width.
- Chạy App Review, claim và privacy checklist.

## 15. Brief giao trực tiếp cho Claude Design

```text
Design and implement a local HTML App Store Screenshot Studio for Loox Password.

Read first:
- docs/app-feature-map-ui-ux.md
- docs/design-guidelines.md
- docs/design-dna-standard.md
- docs/codebase-summary.md
- Design System/readme.md

Use this proposal as the source of truth:
- plans/reports/proposal-260807-1003-loox-app-store-screenshot-studio.md

Outcome:
- A static local HTML studio for seven App Store screenshot frames.
- Device profiles: iPhone 6.9 portrait at 1320x2868 and iPad 13 landscape at 2752x2064.
- Locales: English, Vietnamese, Japanese.
- One-click Export all production that downloads a ZIP with 42 opaque PNG files, manifest, validation report and contact sheets.
- Browser export plus a Playwright fallback using the same renderer.

Design direction:
- Calm Editorial Utility.
- Apple-native, private, quiet, precise and premium.
- Flat or very subtle tonal backgrounds.
- System typography, large readable headlines, generous whitespace.
- Real app captures are the protagonist.
- No loud gradients, texture, neon, glow, 3D mockups, emoji or SF Symbols as brand icons.
- No glass on content.
- One benefit and one visual protagonist per frame.
- Vietnamese is the longest-label stress test.

Implementation constraints:
- Data-driven slides, not seven duplicated pages.
- No CDN or remote assets at export time.
- Use local Polaris and Loox brand assets.
- Wait for fonts and images before capture.
- Export sequentially to control memory.
- Flatten every PNG to an opaque background.
- Validate dimensions, alpha, missing locale copy, missing captures and text overflow.
- Never recreate production app UI in HTML for final assets. Compose real captures from the app and extension.
- Use only safe synthetic fixture data.
- Do not show hidden, dormant or unreleased features.

Build the studio shell, screenshot templates, exporter, validation panel and documentation. Do not modify the native SwiftUI app in this task.
```

## 16. Quyết định cần xác nhận trước khi production

- Chốt base campaign dùng frame 01 Dark Mode hay light mode.
- Chốt có public App Store localization JA ngay trong vòng đầu hay chỉ EN + VI.
- Chốt app capture fixture name và visual identity cho avatar demo.
- Chốt frame 05 Sharing có thuộc tier trả phí tại thời điểm release hay không.
- Chốt dùng Emergency Kit hay Developer Vault cho slot 07 của main set. Đề xuất hiện tại là Emergency Kit; Developer Vault chuyển sang Custom Product Page.

## Kết luận

Một HTML Screenshot Studio data-driven phù hợp với Loox hơn các file artwork rời: dễ giữ hệ thiết kế, dễ localize, tái sử dụng được và giảm lỗi khi App Store đổi kích thước hoặc app đổi UI. Bộ base bảy frame tập trung vào privacy, credential coverage, AutoFill, Watchtower, controlled sharing, search và recovery. Đây là câu chuyện đủ rộng cho người dùng phổ thông, đồng thời vẫn giữ Developer Vault làm một chiến dịch riêng có target rõ hơn.
