# Proposal: Chiến lược gói Subscription cho Loox

> Trạng thái: **Đề xuất chiến lược** (chưa tích hợp IAP). Mục tiêu: chốt triết lý phân
> gói + cấu trúc giá + cơ chế tâm lý TRƯỚC, để khi build StoreKit chỉ là việc thực thi.
> Ngày: 2026-07-14. Bám theo feature thật trong `docs/codebase-summary.md`.

---

## 0. TL;DR (đọc cái này là đủ nắm)

1. **Free phải thật sự "đủ dùng"** cho người an phận — không phải bản dùng thử bị bóp.
   Lý do: đây là app bảo mật, **niềm tin = chất nền của chuyển đổi**, và Free là cửa
   ngõ phễu + máy tạo word-of-mouth. Free stingy = đầu độc lòng tin = không ai bắt đầu.
2. **Max là sản phẩm thật** — "unlimited, đa dụng". Mọi thứ tốn-chi-phí-thật và mọi thứ
   mang tính quan hệ (chia sẻ với người khác) nằm ở đây.
3. **Plus là chim mồi (decoy)** — KHÔNG phải bản vá lỗi của Free. Plus cho cá nhân giá trị
   thật (Watchtower đầy đủ) + **một chút nếm thử của MỌI feature hạ tầng** (3 alias, vài
   link, 2 persona) → power-user liên tục chạm trần → Max "unlimited" chỉ nhỉnh hơn vài
   nghìn (trả năm) là lối thoát hiển nhiên.
4. **Cơ chế decoy nằm ở CẤU TRÚC GIÁ, không phải ở việc làm Plus tệ đi:** giá Max-trả-năm
   quy ra mỗi tháng ≈ Plus-trả-tháng. "Trả Plus theo tháng làm gì khi Max theo năm mỗi
   tháng cũng ngần đó mà có tất cả."
5. **Cỗ máy chuyển đổi = "cho thấy vấn đề miễn phí, bán cách sửa":** Watchtower đếm số
   mật khẩu yếu/lộ cho không (tạo lo lắng có thật), khoá danh sách sửa + hướng dẫn sau
   paywall. Đây là đòn mạnh nhất cho một password manager.
6. **Dùng thử 7 ngày trên gói Max** (không phải Plus) → user nếm "tất cả" → khi hết hạn,
   tụt xuống Free cảm giác như MẤT (loss aversion).

---

## 1. Bối cảnh & 3 ràng buộc chiến lược không được quên

**a) Đối thủ đáng sợ nhất là MIỄN PHÍ và có sẵn: Apple Passwords.**
iOS đã có sẵn app quản lý mật khẩu miễn phí, AutoFill, passkey, đồng bộ iCloud. Nên
**gói Free của Loox bắt buộc phải rõ ràng ăn đứt Apple Passwords** — nếu không, không ai
có lý do bắt đầu, và không có Free user thì không có ai để upsell. "Cái nêm" của Loox so
với Apple: Watchtower (điểm bảo mật + phát hiện lộ/yếu/trùng), tổ chức (Spaces/tags/
personas), chia sẻ cho người khác, email alias, mở trên trình duyệt bất kỳ, TOTP tích hợp.

**b) Loox là zero-backend → đòn bẩy "sync = trả phí" KHÔNG áp dụng.**
Đồng bộ chạy trên iCloud của chính user, bạn không tốn server. Vì vậy **đừng bán sync**
(Bitwarden cho sync free và được yêu quý nhất vì thế). Tiền phải đến từ **GIÁ TRỊ FEATURE**,
không phải từ việc chặn hạ tầng. Đây là điểm khác biệt cốt lõi với 1Password/Dashlane.

**c) Hai nhóm chi phí — kim chỉ nam phân gói:**

| Nhóm | Feature | Chi phí cho bạn | Chiến lược |
|------|---------|-----------------|------------|
| On-device | Vault, AutoFill, passkeys, TOTP, iCloud sync, Watchtower (local rules), HIBP*, themes, generator, import/export | ~0 | **Cho hào phóng** (Free/Plus) để thắng Apple + tạo lòng tin |
| Backend | Email alias `@vexla.app`, Loox Link, Quick View, short links | **Tốn tiền thật, lặp lại** | **Bán + đo lường** (Plus nếm thử → Max unlimited) |

\* HIBP Pwned Passwords range API gọi miễn phí → giá trị cảm nhận cao, chi phí thấp = biên lời tuyệt vời.

---

## 2. Phân tích tâm lý sâu (phần "chạm đúng tâm lý thật")

### 2.1. Cái bẫy bạn phải chủ động vô hiệu hoá: "compromise effect"
Mô hình 3 gói kinh điển tồn tại để **bán gói GIỮA** — con người ghét cực đoan, chọn ở
giữa cho "an toàn". Nhưng bạn muốn bán gói TRÊN (Max). Nên thiết kế phải **cố ý đảo ngược**
xu hướng này:
- Plus không được đóng vai "lựa chọn thoả hiệp an toàn", mà đóng vai **decoy dở dang** —
  đủ tốt cho một nhóm nhỏ, nhưng ai tính kỹ đều thấy nên nhảy lên Max.
- Max không được trưng bày như "cực đoan đắt nhất", mà như **mỏ neo "Đáng giá nhất /
  Phổ biến nhất"**, làm chuẩn để mọi so sánh quy về.

Đây chính xác là điều bạn cảm nhận khi nói "Apple luôn có gói chim mồi, cái họ bán thật
là gói không giới hạn".

### 2.2. Decoy Effect / Asymmetric Dominance (thí nghiệm The Economist — Dan Ariely)
Kinh điển: The Economist chào 3 lựa chọn — Web $59, Print $125, **Print+Web $125**. Bản
Print-only $125 là decoy (chẳng ai chọn), nhưng sự hiện diện của nó khiến Print+Web trông
như "được tặng bản Print". Kết quả: 84% chọn combo (so với 68% khi bỏ decoy). Bài học cho
Loox: **decoy không để bán, mà để làm gói mục tiêu (Max) trông ngon bất thường.**

### 2.3. Anchoring — mỏ neo giá trị
Trưng Max trước/nổi bật, gắn nhãn "Đáng giá nhất". Mọi phán đoán về Free/Plus sẽ neo theo
Max. (Tuỳ chọn: thêm mốc **Lifetime** làm siêu-mỏ-neo khiến giá năm trông rẻ — xem §6.)

### 2.4. "Cái bẫy trả năm" — đòn quyết định
Cơ chế mạnh nhất, và tinh tế: đặt giá sao cho **Max-trả-năm quy ra mỗi tháng ≤ Plus-trả-tháng.**
Người mua lý trí lập tức thấy Plus-trả-tháng là vô lý. Đây là hiện thân của decoy Economist
bằng con số.

### 2.5. Loss aversion — dùng thử trên Max, không phải Plus
Cho dùng thử 7 ngày **gói Max** (StoreKit intro offer). User nếm "tất cả" trong 1 tuần:
alias, chia sẻ với gia đình, Watchtower đầy đủ, personas. Hết hạn, tụt về Free cảm giác
như bị TƯỚC ĐOẠT thứ đang có → động lực trả tiền mạnh hơn nhiều so với "mua thứ chưa từng có".
(Kahneman: mất mát đau gấp ~2 lần cái được tương đương.)

### 2.6. "Show the problem free, sell the fix" — cỗ máy chuyển đổi số 1
Password manager có một đòn chuyển đổi độc nhất: **rủi ro bảo mật là CÓ THẬT và đo được.**
- Free: Watchtower hiện **con số** — "Điểm 620/1000 · 12 mật khẩu yếu · 3 mật khẩu đã lộ".
- Paywall: khoá **danh sách cụ thể là mục nào** + Fix Queue hướng dẫn sửa + cảnh báo lộ HIBP.

Trung thực (rủi ro thật, cách sửa thật) nhưng tạo lo lắng đúng lúc → tỉ lệ chuyển đổi cao
nhất trong toàn app. Đây là nơi đặt paywall theo ngữ cảnh, không phải màn onboarding.

### 2.7. Endowment + lock-in — vì sao Max giữ chân
- **Email alias**: một khi user dùng alias `@vexla.app` để đăng ký khắp nơi, đổi đi = phải
  sửa email ở hàng chục dịch vụ = cực kỳ dính. Alias là feature giữ chân mạnh nhất.
- **Chia sẻ (Approval Mode)**: cả gia đình đã share với nhau thì không ai rời.
- **Personas**: đã tách bạch công việc/cá nhân/ẩn danh thì gỡ ra rất phiền.

### 2.8. Free hào phóng = vòng lặp tăng trưởng (không phải từ thiện)
Trong ngành bảo mật, **lòng tin là chất nền chuyển đổi**. Free rộng rãi → user tin → giới
thiệu người khác → nhu cầu của họ lớn dần (nhiều mục hơn, bắt đầu có gia đình, muốn gom
2FA) → chạm trần → nâng cấp. Bitwarden xây cả đế chế bằng chiến lược này. Đúng như bạn nói:
"an phận miễn phí thì đủ dùng" — đó không phải nhân từ, đó là đỉnh phễu + máy tạo lòng tin.

---

## 3. Bản đồ Feature → Gói (bám feature thật)

Nguyên tắc: **không bao giờ chặn sự AN TOÀN** (số mục lưu, export, sync, khoá sinh trắc).
Chỉ chặn **quyền năng & hạ tầng**.

### 🟢 Loox (Free) — "đủ dùng cho người an phận", ăn đứt Apple Passwords
- Mật khẩu / passkey / note / thẻ / identity **không giới hạn** (KHÔNG BAO GIỜ cap số mục)
- AutoFill Credential Provider + đăng ký/xác thực passkey + tự nâng cấp passkey iOS 18
- Tiện ích Safari điền identity/thẻ + trợ lý đăng ký
- **Đồng bộ iCloud** (iCloud của chính user — free vì zero-backend)
- Mở khoá sinh trắc, auto-lock, privacy shield, Emergency Kit, đổi master password
- TOTP tích hợp (đề xuất: xem không giới hạn; hoặc cap mềm ~10 mục — đòn bẩy tuỳ chọn)
- Trình tạo mật khẩu + passphrase (EFF)
- Import/Export CSV + backup mã hoá (KHÔNG BAO GIỜ nhốt dữ liệu — bắt buộc free vì lòng tin + App Review)
- Spaces/tags/favorites/pinned/archive/thùng rác (đề xuất cap mềm: **3 Spaces** ở Free)
- **Watchtower cơ bản**: điểm 0–1000 + ĐẾM số vấn đề (mồi lo lắng), chưa mở danh sách
- 2 theme (Day/Night) + accent mặc định

### 🟡 Loox+ (Plus) — DECOY: lớp bảo mật-cá-nhân + nếm thử hạ tầng
Mọi thứ ở Free, cộng:
- **Watchtower đầy đủ** ← giá trị lõi của Plus + động cơ chuyển đổi:
  - Chỉ rõ mục nào yếu/trùng/cũ, đối chiếu lộ HIBP, Fix Queue hướng dẫn sửa, lịch sử audit + diff
- Nhắc xoay mật khẩu (cadence 15/30/90 + thông báo OS)
- Toàn bộ 7 accent + auto-night + cỡ chữ (+ theme/wallpaper tương lai khi bật lại)
- TOTP không giới hạn (nếu Free cap), Spaces không giới hạn
- **Nếm thử hạ tầng (cố ý "lưng chừng"):**
  - Email alias: **3 cái** (nếm masking — power-user 20 login sẽ thèm thêm)
  - Loox Link / Quick View: **~10 lượt / tháng**
  - Personas: **2** (1 thêm ngoài mặc định)
- ⛔ KHÔNG có (giữ cho Max): alias không giới hạn · chia sẻ với NGƯỜI KHÁC · personas không
  giới hạn · emergency access · hỗ trợ ưu tiên · truy cập sớm

> Plus không hỏng — nó cho cá nhân giá trị thật. Nhưng nó **cố ý chạm trần ở đúng chỗ**
> khiến power-user liên tục va vào giới hạn.

### 🔴 Loox Max — SẢN PHẨM THẬT: unlimited + quan hệ + hạ tầng
Mọi thứ ở Plus, **bỏ mọi giới hạn**, cộng:
- **Email alias `@vexla.app` không giới hạn** (fair-use) — painpoint masking, dính nhất
- **Loox Link + Quick View không giới hạn** + rút gọn link + tuỳ chỉnh hạn (1h–30d)
- **Approval Mode Sharing với người khác** (chia field theo mục, TOTP ask-each-time) +
  Shared-with-Me → *đồng thời là vòng lặp lan truyền*: người nhận phải cài Loox để nhận share
- **Personas không giới hạn** (công việc/cá nhân/ẩn-danh strictAnonymous)
- Emergency access / trao quyền thừa kế
- Hỗ trợ ưu tiên + truy cập sớm (Credential Exchange, feature mới)
- "Tất cả, hiện tại và tương lai"

---

## 4. Tại sao phải có Plus (chứ không chỉ Free/Max)?
Plus làm 3 việc cùng lúc:
1. **Decoy** nâng tỉ lệ chọn Max (hiệu ứng Economist — 3 gói bán nhiều Max hơn 2 gói).
2. **Đường dốc giá rẻ** hứng nhóm nhạy cảm giá — người KHÔNG bao giờ trả cho Max nhưng
   CHỊU trả chút ít; sau này upsell lên Max.
3. **Giảm bỏ cuộc "đắt quá"** — có mốc thấp để neo, Max trông hợp lý hơn.

---

## 5. Cấu trúc giá & cơ chế decoy (song thị trường)

> Giá đã căn theo mốc App Store chuẩn. Đối chiếu đối thủ 2026: Bitwarden Premium $1.65/mo,
> Proton Pass $1.99/mo (alias không giới hạn), NordPass $1.49/mo, 1Password $2.99/mo,
> Dashlane $4.99/mo (đã bỏ free 9/2025), Apple Passwords $0.

### 🌍 Toàn cầu (USD)

| Gói | Tháng | Năm | Năm quy ra /tháng |
|-----|-------|-----|-------------------|
| Free | $0 | — | — |
| Plus | $2.99 | $19.99 | ~$1.67 |
| **Max** | $4.99 | **$34.99** | **~$2.92** |

**Cú chốt decoy:** Max-trả-năm ($2.92/mo) **rẻ hơn** Plus-trả-tháng ($2.99/mo) — mà có tất
cả. Max-tháng $4.99 khiến Max-năm (giảm ~42%) trông hời. Plus-năm $1.67/mo = sàn ngân sách.

### 🇻🇳 Việt Nam (VND)

| Gói | Tháng | Năm | Năm quy ra /tháng |
|-----|-------|-----|-------------------|
| Free | 0đ | — | — |
| Plus | 29.000đ | 199.000đ | ~16.500đ |
| **Max** | 49.000đ | **349.000đ** | **~29.000đ** |

**Cú chốt decoy:** Max-trả-năm (~29k/tháng) ≈ Plus-trả-tháng (29k/tháng). Plus-năm ~16.5k/tháng
= sàn ngân sách. (Các mốc 29k/49k/199k/349k đều là tier chuẩn Apple VN.)

### Dùng thử
7 ngày miễn phí (StoreKit intro offer, tự động gia hạn), **paywall mặc định chọn/nổi bật
gói Max** → phần lớn lượt dùng thử là Max → nếm "tất cả" → loss aversion khi hết hạn.
**Minh bạch tuyệt đối** về "hết 7 ngày sẽ tự tính tiền" (app bảo mật = thương hiệu lòng tin,
đừng chơi trò mập mờ — vừa hại brand vừa rủi ro App Review).

---

## 6. Lifetime — dùng cẩn thận (bẫy unit economics)
Nhóm iOS ghét subscription khá đông → một mốc **Max Lifetime** (vd $99.99 / 1.990.000đ) vừa
hứng nhóm này, vừa làm siêu-mỏ-neo khiến $34.99/năm trông rẻ.

⚠️ **NHƯNG:** Max có feature tốn-chi-phí-vĩnh-viễn (relay email forward mail mãi mãi; link/
Quick View chạy Workers). **Lifetime + alias không giới hạn = chi phí tương lai vô hạn đổi
lấy một lần trả tiền = cực nguy hiểm.** Nếu làm Lifetime:
- **Loại metered-cost khỏi Lifetime** (Lifetime = mọi feature ON-DEVICE của Max mãi mãi;
  alias/link vẫn tính hạn mức hoặc vẫn cần sub), HOẶC
- Đơn giản là **chưa làm Lifetime ở V1** cho đến khi mô hình chi phí relay rõ ràng.
- Khuyến nghị: **hoãn Lifetime**, chỉ dùng nó như mỏ-neo tâm lý nếu số liệu chi phí đã chắc.

---

## 7. Cỗ máy chuyển đổi — paywall đặt ở đâu
Đừng chặn cứng ở onboarding (giết lòng tin). Bật paywall **theo ngữ cảnh, đúng lúc chạm đau**:
- Watchtower phát hiện mục đã lộ → "12 mục đang rủi ro — xem & sửa với Loox+"
- Tạo persona thứ 2 / thứ 3 → "Tách bạch danh tính với Loox Max"
- Tạo email alias vượt hạn → "Alias không giới hạn với Max"
- Bấm "Chia sẻ với gia đình" → Max
- Tạo share link vượt quota → Max
- Home "Needs attention" là điểm neo lo lắng thường trực (đã có sẵn trong app)

Nguyên tắc: **cho thấy giá trị/vấn đề miễn phí → bán hành động giải quyết.**

---

## 8. Phản biện thẳng (chỗ mình chỉnh sắc lại ý bạn)

1. **ĐỪNG cap số mật khẩu ở Free.** Với app bảo mật, giới hạn "chỉ lưu 25 mật khẩu" đẩy
   user đi tái dùng mật khẩu / lưu vào Notes — phản tác dụng đạo đức + hại lòng tin +
   rủi ro App Review. Chặn quyền-năng (Watchtower, alias, share, persona), đừng chặn an toàn.
2. **Decoy ≠ lừa đảo.** Đây là category lòng tin. Plus phải là sản phẩm TỬ TẾ cho cá nhân
   (Watchtower đầy đủ + themes), không phải cái bẫy. Hiệu ứng decoy đến từ **neo-giá-trị +
   giá-trả-năm**, KHÔNG phải từ việc bóp Plus cho tệ.
3. **Alias là hàng commodity.** Proton Pass cho alias KHÔNG giới hạn ở $1.99/mo. Nên đừng
   neo toàn bộ giá trị Max vào alias — neo vào **cả gói** (alias + share + personas +
   Watchtower + mở-trên-trình-duyệt + UX Apple-native mượt) mà Proton không sánh được.
4. **Downgrade không bao giờ nhốt vault.** Khi user hạ gói/hết hạn: **giữ nguyên quyền đọc +
   export MỌI mục đang có**; chỉ mất khả năng THÊM/HÀNH ĐỘNG premium mới (tạo alias mới,
   chia sẻ mới). Đây là nguyên tắc cứng bảo vệ thương hiệu.
5. **Relay email có chi phí thật + rủi ro lạm dụng.** "Không giới hạn" trên Max phải là
   "fair use" (chống spam/abuse), và cần mô hình chi phí trước khi hứa vô hạn.
6. **Đừng bật Apple Family Sharing cho IAP** nếu muốn bán giá trị "chia sẻ gia đình" — nếu
   không Apple sẽ cho cả nhà xài chung 1 sub và bạn mất doanh thu. Xây family-sharing
   IN-APP (Approval Mode) làm giá trị Max.

---

## 9. Ghi chú Unit Economics (vì sao Max phải đủ bù)
- **Chi phí biến đổi** của Loox gần như chỉ đến từ: relay mail (alias), Workers (Link/
  Quick View/short link). Watchtower/HIBP/sync/vault ≈ 0.
- Nên **Max phải gánh chi phí biến đổi**; Plus/Free gần như thuần biên-lời-cao vì chỉ mở
  feature on-device.
- Meter alias & link ngay cả ở Max (fair-use ceiling ẩn) để một user không thể tạo 10.000
  alias làm cháy chi phí.

---

## 10. Phụ lục — khi nào build IAP (chưa làm bây giờ)
Để tham khảo cho tương lai, không phải việc lúc này:
- **StoreKit 2, hợp với zero-backend:** xác định quyền lợi on-device qua
  `Transaction.currentEntitlements` — không cần server xác thực receipt.
- **1 Subscription Group** chứa Plus + Max → Apple tự xử nâng/hạ cấp, proration.
- **Intro Offer** cho 7 ngày dùng thử.
- **Grandfather** user hiện hữu (đang free) khi ra mắt — thông báo trước, ưu đãi sớm.
- Metered feature (alias/link) cần một **bộ đếm quota** (App Group/CloudKit) tách khỏi
  entitlement — vì đó là giới hạn dùng, không phải cờ bật/tắt.

---

## 11. Quyết định cần bạn chốt (mình để mở, không tự quyết hộ)
1. **Thị trường chính:** VN-first hay toàn cầu-first? (đổi mốc giá + copy + ưu tiên feature)
2. **TOTP ở Free:** không giới hạn (thắng Apple mạnh hơn) hay cap ~10 (đòn chuyển đổi thêm)?
3. **Hạn mức Plus cụ thể:** 3 alias / 10 link-tháng / 2 persona — con số này bạn thấy
   "lưng chừng" đúng liều chưa, hay muốn siết/nới?
4. **Lifetime:** hoãn (khuyến nghị) hay làm ngay như mỏ-neo (phải chốt mô hình chi phí relay)?
5. **Family SKU** (Max cho 5 người, 1 lần trả): làm ở V1 hay để V2?
6. **Đặt tên hạn mức khi hết:** copy paywall theo hướng "nâng cấp để mở khoá" — cần viết
   EN + VI (theo rule localization của app).
