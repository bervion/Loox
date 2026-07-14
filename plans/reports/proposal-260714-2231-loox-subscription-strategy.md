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
- Email alias: **1** (nếm masking tích hợp — đấu Apple/DDG ở mức "cho thấy", xem §10.1)
- 2 theme (Day/Night) + accent mặc định

### 🟡 Loox+ (Plus) — DECOY: lớp bảo mật-cá-nhân + nếm thử hạ tầng
Mọi thứ ở Free, cộng:
- **Watchtower đầy đủ** ← giá trị lõi của Plus + động cơ chuyển đổi:
  - Chỉ rõ mục nào yếu/trùng/cũ, đối chiếu lộ HIBP, Fix Queue hướng dẫn sửa, lịch sử audit + diff
- Nhắc xoay mật khẩu (cadence 15/30/90 + thông báo OS)
- Toàn bộ 7 accent + auto-night + cỡ chữ (+ theme/wallpaper tương lai khi bật lại)
- TOTP không giới hạn (nếu Free cap), Spaces không giới hạn
- **Nếm thử hạ tầng (cố ý "lưng chừng"):**
  - Email alias: **5 cái** (nếm masking — power-user 20 login sẽ thèm thêm)
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

## 10. Đấu đối thủ — mỗi gói nhắm hạ MỘT đối thủ cụ thể

Trả lời thẳng câu "Free hay Plus có đủ đánh Apple / 1Password / app ẩn mail không": **có** —
và mỗi gói được thiết kế để hạ đúng một đối thủ, không dàn hàng ngang.

| Gói | Nhắm hạ | Thắng bằng |
|-----|---------|------------|
| **Free** | **Apple Passwords** (mặc định ai cũng có sẵn) | Watchtower (điểm + đếm), Spaces/tags/personas, item phong phú (identity/thẻ/note), TOTP tích hợp, cá nhân hoá, "là sản phẩm được chăm" — Apple chỉ là feature hệ thống tối giản |
| **Plus** | **1Password** ($2.99, KHÔNG có bản free) | Watchtower đầy đủ ngang 1Password, nhưng **có bản free để bắt đầu** + native iOS + rẻ hơn thực tế ($1.67/mo trả năm) |
| **Max** | **Proton Pass / all-in-one có ẩn mail** | Không đấu giá alias lẻ — thắng bằng **tích hợp** (alias sinh ngay lúc đăng ký, tự gắn login, tự autofill) gói chung share + personas + Watchtower + mở-trên-trình-duyệt, tất cả native |

### 10.1 Ẩn mail: thị trường đã commodity hoá — ĐỪNG đấu bằng số lượng
Sự thật phũ: masking giờ rẻ/free khắp nơi — DuckDuckGo Email (free **không giới hạn**),
Firefox Relay (5 free rồi $0.99), Apple Hide My Email (kèm iCloud+), Proton Pass (không
giới hạn $1.99). **Loox không thể bán alias như hàng xa xỉ, và Free KHÔNG cố thắng DDG ở
mảng "free unlimited masking"** (đó là loss-leader DDG nuôi bằng tiền quảng cáo).

→ Lợi thế Loox = **workflow tích hợp** mà app ẩn-mail đứng-riêng không có: alias sinh ra
ngay khi điền form đăng ký, tự lưu kèm login, tự autofill lần sau, quản lý chung credential.
Đó là giá trị, không phải con số.

→ Phân bổ (cân bằng chi phí backend ↔ sức cạnh tranh):
- **Free: 1 alias** — chỉ để *trình diễn* phép màu tích hợp (không thua trắng, nhưng vũ khí
  thật của Free so với Apple là **Watchtower + tổ chức**, không phải masking).
- **Plus: 5 alias** — dùng thực tế cho người thường (ngang mức free của Firefox).
- **Max: không giới hạn (fair-use)** — người "đói" masking chính là chân dung khách Max.

Người cần masking nhiều = đúng người convert lên Max. Free chỉ cần cho họ *nếm*.

---

## 11. HÀNG RÀO downgrade/huỷ gói — "data đi về đâu" (thiết kế để SCALE)

Phần sống-còn khi scale. Làm sai = **chết lòng tin** (user tưởng bị giữ data làm con tin —
tử huyệt của password manager), hoặc **chết biên lời** (alias forward mail miễn phí mãi
mãi), hoặc vướng **App Review / GDPR**.

### 11.1 Chia data làm HAI loại — nguyên tắc gốc
- **🔒 KÉT CỦA BẠN (Vault data):** mật khẩu, passkey, note, thẻ, identity, TOTP, cấu trúc
  Space/tag, **và địa chỉ alias ↔ login nó gắn vào**. Đây là dữ liệu của USER. **Vĩnh viễn
  đọc/copy/autofill/export được — không bao giờ xoá, không bao giờ khoá, bất kể gói.**
  (On-device + iCloud của user → chi phí 0 → không có lý do đụng vào.)
- **📡 DỊCH VỤ ĐANG THUÊ (Service state):** forwarding email đang chạy, share-ra đang
  active, link đang sống. Đây là **hạ tầng thuê theo sub**. Hạ gói → cuốn chiếu (wind-down),
  nhưng **BẢN GHI vẫn hiện** → tái sub là bật lại nguyên trạng.

### 11.2 Bốn luật của hàng rào
1. **Giới hạn chặn TẠO MỚI, không xoá cái đang có.** "Free = 3 Spaces" = không tạo Space
   thứ 4, KHÔNG phải xoá 5 Space đang có. Data cũ đóng băng ở trạng thái đọc/dùng-được.
2. **Feature tốn-phí → wind-down có ÂN HẠN + cho user CHỌN cái giữ lại.** 30 ngày ân hạn
   còn chạy, cảnh báo to trước, user tự chọn giữ alias/share nào trong hạn mức mới (đừng
   tự tay giết alias ngân hàng của họ).
3. **Export mọi lúc, mọi gói** (kể cả Free). Không nhốt data. Alias xuất được cả danh sách
   địa chỉ đã dùng ở đâu.
4. **Tái đăng ký = khôi phục nguyên trạng** trong cửa sổ giữ (đề xuất 90 ngày) → win-back
   không ma sát.

**⚠️ Luật bảo mật cứng:** một địa chỉ alias, một khi đã tạo, **KHÔNG BAO GIỜ tái cấp cho
user khác** kể cả sau khi xoá — vì mail vẫn có thể gửi tới đó, tái dùng = rò mail sang
người lạ. Alias là **"burn forever"** (chi phí lưu bản ghi tí xíu, nhưng là yêu cầu an ninh
bắt buộc — precedent: Apple/Firefox/SimpleLogin đều không recycle).

### 11.3 Bảng: mỗi feature, data đi về đâu khi hạ gói / hết hạn

| Feature | Khi hạ gói / hết hạn (phần vượt hạn mức) | Loại |
|---------|------------------------------------------|------|
| Mật khẩu/passkey/note/thẻ/identity/TOTP | **Giữ 100%** — đọc/copy/autofill/export bình thường | 🔒 Két |
| Spaces / tags / favorites / archive | Giữ hết; chỉ **chặn tạo mới** khi đang vượt | 🔒 Két |
| Watchtower đầy đủ | Về "chỉ con số"; **item không suy suyển** | Feature off |
| Themes / accents | Về mặc định; không xoá gì | Feature off |
| **Personas** | **Đóng băng, KHÔNG merge:** giữ + đọc/dùng mọi persona đang có; chặn tạo mới. (Merge = rò rỉ strictAnonymous → CẤM) | 🔒 Két (freeze) |
| **Email alias** | Phần vượt hạn mức: **ngừng forward sau 30d ân hạn**; địa chỉ + login-nó-gắn **vẫn hiện**; user **chọn cái giữ active**; tái sub → forward lại; địa chỉ **không bao giờ tái cấp** | 📡 Dịch vụ |
| Loox Link / Quick View đang active | Để **hết hạn tự nhiên** (vốn 1h–30d); chỉ chặn tạo mới | 📡 (ephemeral) |
| **Chia sẻ RA** (Approval Mode) | Wind-down 30d → thu hồi; cảnh báo người nhận sắp mất quyền; tái sub → khôi phục | 📡 Dịch vụ |
| **Nhận share** (Shared-with-Me) | **KHÔNG ảnh hưởng** — nhận luôn miễn phí (vòng lan truyền) | Luôn free |

### 11.4 Biến rủi ro downgrade thành đòn WIN-BACK (dùng lại cỗ máy §2.6)
Khi alias/share bị đóng băng, Watchtower nêu công khai + trung thực: *"3 login đang dùng
alias đã ngừng forward — bạn sẽ không nhận được email đặt lại mật khẩu. Cập nhật email
thật, hoặc bật lại Max."* Vừa đúng đạo đức (rủi ro thật, nói thẳng), vừa là đòn kéo-lại
mạnh nhất. **Đừng bao giờ để login của user âm thầm hỏng.**

### 11.5 Toán scale — vì sao hàng rào này đúng
- Chi phí biến đổi gần như chỉ từ alias-forward + Workers; vault/sync/Watchtower ≈ 0.
- Khách Max churn có 50 alias: hàng rào **co về đúng hạn mức Free (1)** sau ân hạn → **chặn
  chi phí chạy hoang**. Không hàng rào = 50 alias forward miễn phí mãi mãi = chết biên lời
  khi lên triệu user.
- Vault không bao giờ khoá → **lòng tin không sứt mẻ khi scale** (không bão review 1 sao
  kiểu "chúng nó giữ mật khẩu của tôi làm con tin").
- Alias burn-forever → **không sự cố rò mail khi scale**.

### 11.6 Trial 7 ngày — cùng luật, cảnh báo gắt hơn
User trial Max tạo 20 alias + 5 persona rồi không convert → về Free: áp đúng wind-down.
Chính "sắp mất 20 alias" là áp lực convert (loss aversion §2.5) — nhưng phải **tử tế**: ân
hạn + cho chọn giữ + export. Đừng dụ user phụ thuộc 20 alias rồi bắt làm con tin. Cân nhắc
nhắc nhẹ ngay trong trial: "alias tạo khi dùng thử sẽ co về hạn mức Free khi hết hạn".

---

## 12. Đào sâu: Unit economics của "Max unlimited" (dựa trên hạ tầng Cloudflare THẬT)

> Nguồn: `VaultifyCore/Relay/RelayConfig.swift` + `plans/260706-1238-…/proposal-v3-locked-decisions.md`.
> Đây là phần lật ngược một giả định của §6/§9 — nên đọc kỹ.

### 12.1 Sự thật hạ tầng (từ repo, không đoán)
- Relay = **Cloudflare**. V1 **receive-only** (D14), forward tới destination đã verify.
  Alias domain `relay.looxpassword.com` (client), registry có thể phục vụ thêm `@vexla.app`.
- **Path A** (`forward()` → verified destination): chạy **Free tier $0**, NHƯNG **trần ~200
  verified destinations** → chỉ đủ beta, **KHÔNG scale** tới triệu user.
- **Path B (production)**: Cloudflare Email Sending Beta = **Workers Paid $5/mo + 3.000
  email included + $0.35/1k** sau đó (số ghi trong doc bạn), hoặc contingency SES/Postmark
  (~$0.10/1k). → **chi phí mỗi email forward ≈ $0.0001–0.00035.**
- Alias DB = **D1 Free** (5GB, 5M row-reads/ngày) — đủ cho beta lâu dài.
- **Đã thiết kế sẵn chống-abuse:** rate-limit **5 chiều** (IP/principal/device/alias/sender)
  + hard caps + kill switch (global/principal/alias/sender) + retention tối thiểu (KHÔNG lưu
  body/subject/attachment; chỉ message_id, alias_id, received_at, forward_status, size, error).

### 12.2 Kết luận tài chính (phản trực giác — nhưng đây mới là điểm mấu chốt)
**Chi phí KHÔNG phải ràng buộc scale của bạn.** Con số:
- 1 khách Max $34.99/năm → **~$29.7 net** (sau Apple 15% Small Business Program).
- Chi phí đó bù được **~85.000–290.000 lượt forward/năm**. Một user *nặng đô* (50 alias ×
  20 mail/tháng) chỉ ~12.000 lượt/năm ≈ **$1.2–4.2/năm**. User thường: vài xu/năm.
- → **Biên lời relay > 95%** kể cả user nặng. Fixed cost $5/mo Workers Paid: chỉ cần **~2
  khách Max/tháng** là hoà. Vault thì on-device + iCloud của user = **$0**.
- → Một khách Max nuôi được **hàng nghìn** user Free. Mô hình **scale cực đẹp** về tiền.

> ⚠️ Vậy nên: **ĐỪNG định giá Max để "bù chi phí relay"** (§6/§9 hàm ý điều này — sai).
> Chi phí ~0. Mọi đồng thu từ Max gần như thuần lời → dồn lực vào **CHUYỂN ĐỔI**, không phải
> cắt chi phí. Giá Max neo vào **giá trị + đối thủ** (Proton $1.99 alias unlimited), không neo chi phí.

### 12.3 Ràng buộc scale THẬT (trục dịch từ "tiền" sang "rủi ro hệ thống")
1. **🔴 Deliverability / Reputation — RỦI RO SỐNG-CÒN.** Alias bị lạm dụng gửi/nhận spam →
   `relay.looxpassword.com` vào blocklist → **mail của TẤT CẢ user chết cùng lúc.** Một sự
   cố = hỏng feature cho toàn bộ base. **Đây mới là thứ phải "rào kĩ", không phải ví tiền.**
2. **Abuse / DoS** — tạo 100k alias, mail-bomb. Chặn bằng rate-limit + hard cap + kill switch
   (đã có thiết kế), **KHÔNG bằng giá gói.**
3. **Trần 200 destination của Free path** — bắt buộc lên Workers Paid + Email Sending trước
   khi scale thật (plan đã defer đúng tới P4C).

### 12.4 Điều này ĐỔI gì trong chiến lược gói & fence
- **Fence downgrade KHÔNG còn chủ yếu vì tiền** (forward gần free) — mà vì **(i) không cho
  không giá trị premium, (ii) giảm bề mặt abuse + reputation.** → Bạn có thể **hào phóng hơn**
  với forwarding của user churn (chi phí không đáng kể); siết là để bảo vệ value-prop + danh
  tiếng domain, không phải cứu ví.
- **"Unlimited" của Max = fair-use ~200–500 alias** (trần **chống-abuse**, không phải trần
  chi phí) + rate-limit tạo alias. Con số này thoải mái với 99.9% user thật.
- **Free 1 / Plus 5 alias** giờ là quyết định **value-positioning + abuse-surface**, KHÔNG
  phải cost. (Chi phí cho phép hào phóng hơn — nhưng đừng, sẽ ăn mòn Max + nở abuse.)

### 12.5 ⚠️ Căng thẳng thương hiệu phải rào trước (quan trọng, dễ bỏ sót)
Repo đã tự chốt: **"ngừng marketing câu tuyệt đối no-backend khi relay ship."** Nghĩa là
**feature flagship của gói trả tiền (relay) lại là thứ đục thủng lợi thế khác biệt LÕI của
app (zero-backend, offline).** Cách rào:
- Tách bạch tuyệt đối trong mọi copy: **Vault vẫn 100% E2E / on-device / zero-backend.**
  Private Email là **capability opt-in, metadata tối thiểu, trust boundary riêng, disclose
  minh bạch** (Privacy Policy + App Privacy label — đã nằm trong plan relay).
- Biến thành **lợi thế bán**: khác Proton (server-side toàn bộ), Loox là **"local-first
  vault + optional relay"** — story privacy MẠNH HƠN nếu kể đúng. "Két của bạn không bao giờ
  rời máy; chỉ email đi qua relay khi bạn tự bật."
- Đừng để relay làm loãng claim Vault trên App Store / landing.

### 12.6 Số cần bạn tự chốt để khoá mô hình
- **Provider production cuối:** Cloudflare Email Sending Beta hay SES/Postmark? (đổi $/1k +
  deliverability Gmail/Outlook/Yahoo + abuse tooling — benchmark P4C của bạn chưa chạy).
- **Rủi ro phụ thuộc Beta:** bán feature trả tiền dựa trên một dịch vụ còn Beta (chưa GA) —
  cần plan B (SES) sẵn sàng trước khi lên paywall Max.
- **Trần fair-use** alias/Max (đề xuất 200–500) + rate tạo alias/ngày.

---

## 13. Đào sâu: Trial & Win-back (tận dụng chi phí ~0)

> Vì Free user tốn ~$0 (§12), Loox được phép chơi trial & win-back HÀO PHÓNG hơn hẳn app có
> chi phí biên cao. Đây là **lợi thế cấu trúc** — dùng nó. Và fence §11 chính là thứ khiến
> mọi thứ ở đây an toàn + tử tế.

### 13.1 Chọn kiểu trial: Reverse Trial là vũ khí mạnh nhất

| Kiểu | Cách chạy | Hợp cho |
|------|-----------|---------|
| **⭐ Reverse trial (KHÔNG cần thẻ)** | User mới **bắt đầu bằng Max đầy đủ** 14 ngày, không thẻ; hết hạn **tự rơi về Free** (fence §11 lo hạ cánh mềm) | Onboarding chính — tin-trước, loss aversion tối đa |
| Standard trial (cần thẻ, tự charge) | StoreKit intro offer 7 ngày, thẻ on-file, tự tính tiền | Paywall theo ngữ cảnh, high-intent |
| Just-in-time trial | Chạm tường Max (persona 2, alias 6, share) → "Dùng thử Max 7 ngày" | Điểm painpoint, intent cao nhất |

**Vì sao reverse trial thắng:** user không "thử rồi mua" — họ **dùng bản đầy đủ rồi MẤT**.
Sau 14 ngày họ đã nhập cả vault, tạo personas, mask email, thấy full Watchtower, share với
gia đình → rơi về Free = **mất thứ đang có** (loss aversion §2.5), mạnh hơn nhiều "mua thứ
chưa từng có". **Fence §11 khiến reverse trial AN TOÀN + tử tế** (vault giữ 100%, chỉ premium
cuốn chiếu) — hai mảnh khớp nhau.

**Cơ chế:** reverse-trial-không-thẻ = **entitlement app tự quản** (cờ "trial tới ngày X",
lưu App Group/iCloud), KHÔNG đụng StoreKit tới khi user chủ động mua. Reinstall reset được →
**chấp nhận** (cost ~0). Standard/JIT trial = StoreKit intro offer (Apple lo, không reset,
convert cao hơn).

**Khuyến nghị:** reverse trial **không thẻ, 14 ngày** làm onboarding chính (tin-trước, hợp
brand bảo mật; cost cho phép) + standard trial **có thẻ** ở paywall ngữ cảnh cho high-intent.
14 ngày vì password manager cần thời gian tích item + gặp breach + muốn share mới thấy giá trị.

### 13.2 Engineer "khoảnh khắc aha" trong trial (trial rỗng = convert kém)
Trial chỉ convert nếu user CHẠM giá trị lõi trong lúc thử. Onboarding phải lùa tới:
1. **Import password sẵn có** (iCloud Keychain / manager khác / CSV) **NGAY** — đòn kích hoạt
   số 1. Vault rỗng → Watchtower vô nghĩa, không gì để endowed. Import = lấp vault + cho
   Watchtower dữ liệu để audit.
2. **Watchtower reveal sớm** (session đầu): "Điểm 620 · 12 yếu · 3 đã lộ — mục nào & cách sửa."
3. **1 lần AutoFill** — móc thói quen hằng ngày.
4. **1 alias tại form đăng ký thật** — khoảnh khắc "phép màu".
→ Thiết kế first-run lùa đúng 4 việc này, đừng để user tự mò.

### 13.3 Vòng đời đầy đủ: Reverse trial → Free → Win-back
1. **Ngày 0:** Max đầy đủ, không thẻ; onboarding lùa import + Watchtower.
2. **Ngày 1–13:** lấp vault, endowed dần; nhắc giá trị tích cực ("đã sửa 8 vấn đề / mask 4 email").
3. **Ngày 11–13:** nhắc trước hết hạn, khung **loss aversion**: "Trial còn 3 ngày. Giữ tất cả
   với $34.99/năm. Bạn GIỮ mọi mật khẩu, nhưng sẽ MẤT: full Watchtower, 5/6 alias, chia sẻ, personas."
4. **Ngày 14:** rơi về Free **mềm** qua fence §11 (vault 100% nguyên; premium cuốn chiếu). KHÔNG tường cứng.
5. **Free về sau:** vẫn hạnh phúc (hơn Apple Passwords); nhắc "show problem sell fix" khi nợ bảo mật tích lại.
6. **Win-back:** khi cảm nhận MẤT cụ thể (alias ngừng forward, breach mới) → offer win-back.

### 13.4 Win-back: công cụ Apple + trigger hành vi
**Công cụ StoreKit (iOS 18+):**
- **Win-back offers** — Apple cho cấu hình ưu đãi riêng cho sub đã rời, hiện cả App Store lẫn
  in-app. Dùng làm xương sống.
- **Promotional offers / offer codes** — giảm giá cho sub đã lapse, hiện in-app.

**Trigger (cost ~0 → hào phóng được):**
1. **Fence chính là máy win-back** (§11.4): alias ngừng forward → Watchtower cảnh báo thật →
   "3 login sắp mất email reset — bật lại Max." Thời điểm intent CAO NHẤT (mất cụ thể).
2. **Nợ bảo mật tích lũy:** điểm Watchtower của Free user tụt dần (breach mới HIBP, mật khẩu
   già). Nhắc thật định kỳ: "4 breach mới từ khi bạn hạ gói — xem & sửa với Plus."
3. **Trong 30d ân hạn:** "Giữ tất cả — bật lại giảm 30% năm đầu." Gần như thuần lời.
4. **Lifecycle 60/90 ngày:** re-engage kèm win-back offer.

**Hào phóng CÓ KỶ LUẬT:** biên lời >95% → một sub cứu lại (giảm 50% ≈ $17) gần như thuần lời
→ **đừng bỏ churned user trên bàn.** NHƯNG đừng dạy user "huỷ để được giảm" (moral hazard):
win-back **nhắm mục tiêu + có hạn giờ**, KHÔNG hiện cho sub đang active, không always-on.

### 13.5 Đo lường (privacy-first, hợp brand)
Trial-start rate · trial→paid · time-to-aha (đã import? đã xem Watchtower?) · kích hoạt D14 ·
win-back rate · lý do churn. Zero-backend → analytics phải **tôn trọng riêng tư** (tổng hợp,
on-device tối đa, hoặc analytics privacy-friendly) — kẻo phá chính claim đang bán.

### 13.6 Phản biện thẳng
- **ĐỪNG bắt nhập thẻ ở lần trial đầu** — app bảo mật, chi phí lòng tin quá cao; cost cho phép không-thẻ.
- **ĐỪNG dựng tường cứng cuối trial** — đúng fence §11: hạ cánh mềm, vault nguyên vẹn.
- **ĐỪNG nhắc quá nhiều** — app bảo mật bán sự an tâm; nagging phá đúng thứ đang bán. Nhắc phải thật + đúng ngữ cảnh + thưa.
- **Trial abuse qua reinstall** (reverse trial không thẻ reset được): chấp nhận (cost ~0),
  hoặc buộc nhẹ vào Apple ID qua 1 cờ iCloud KV để giới hạn thử lặp. Ưu tiên thấp.

---

## 14. Phụ lục — khi nào build IAP (chưa làm bây giờ)
Để tham khảo cho tương lai, không phải việc lúc này:
- **StoreKit 2, hợp với zero-backend:** xác định quyền lợi on-device qua
  `Transaction.currentEntitlements` — không cần server xác thực receipt.
- **1 Subscription Group** chứa Plus + Max → Apple tự xử nâng/hạ cấp, proration.
- **Intro Offer** cho 7 ngày dùng thử.
- **Grandfather** user hiện hữu (đang free) khi ra mắt — thông báo trước, ưu đãi sớm.
- Metered feature (alias/link) cần một **bộ đếm quota** (App Group/CloudKit) tách khỏi
  entitlement — vì đó là giới hạn dùng, không phải cờ bật/tắt.

---

## 15. Quyết định cần bạn chốt (mình để mở, không tự quyết hộ)
1. **Thị trường chính:** VN-first hay toàn cầu-first? (đổi mốc giá + copy + ưu tiên feature)
2. **TOTP ở Free:** không giới hạn (thắng Apple mạnh hơn) hay cap ~10 (đòn chuyển đổi thêm)?
3. **Hạn mức Plus cụ thể:** 3 alias / 10 link-tháng / 2 persona — con số này bạn thấy
   "lưng chừng" đúng liều chưa, hay muốn siết/nới?
4. **Lifetime:** hoãn (khuyến nghị) hay làm ngay như mỏ-neo (phải chốt mô hình chi phí relay)?
5. **Family SKU** (Max cho 5 người, 1 lần trả): làm ở V1 hay để V2?
6. **Đặt tên hạn mức khi hết:** copy paywall theo hướng "nâng cấp để mở khoá" — cần viết
   EN + VI (theo rule localization của app).
7. **Free alias = 1** (khuyến nghị, để có "câu chuyện masking") hay **0** (an toàn chi phí tối đa)?
8. **Ân hạn wind-down 30 ngày** + **cửa sổ khôi-phục-khi-tái-sub 90 ngày** — thời lượng này ok, hay siết/nới?
9. **Nhận-share luôn miễn phí** (khuyến nghị — vòng lan truyền kéo người mới vào Loox) — bạn đồng ý chứ?
10. **Kiểu trial:** reverse trial 14d không-thẻ làm onboarding chính (khuyến nghị) + standard 7d có-thẻ ở paywall — hay chỉ một kiểu?
11. **Win-back:** bật Apple win-back offers + nudge-qua-fence (khuyến nghị) — mức giảm tối đa cho win-back (đề xuất ≤50% năm đầu)?
12. **Analytics privacy-first:** chọn hướng nào (on-device aggregate / SDK privacy-friendly) để đo trial-funnel mà không phá claim riêng tư?
