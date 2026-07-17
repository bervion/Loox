# Loox — Tài liệu Handoff cho Team Web

**Ngày:** 17/07/2026 · **Nguồn:** trích xuất trực tiếp từ source code app iOS (Loox Password)
**Người nhận:** Team Web + Team Design

---

## 0. Phạm vi tài liệu

- Tài liệu này **chỉ cung cấp thông tin**, không gợi ý cách thiết kế. Team web/design toàn quyền thiết kế UI/UX riêng cho website.
- **Ngoại lệ bắt buộc giống app** (để giữ nhận diện thương hiệu): logo, animation logo (welcome loop + launch), Loox Swirl, badge **MAX**, palette màu brand. Các phần này có spec số liệu chính xác bên dưới, code lại 1:1.
- Assets sẽ được gửi kèm riêng: file logo (BrandSymbol, BrandLogo wordmark), video memoji (3 nhân vật), ảnh gradient `SwirlGradient`, file `loox-max-badge.svg`.

---

## 1. Brand cơ bản

### 1.1 Tên gọi
- Sản phẩm: **Loox Password** (gọi tắt: Loox).
- Tên gói (không dịch, giữ nguyên mọi ngôn ngữ): **Loox** (Free) · **Loox+** (Plus) · **Loox Max**.

### 1.2 Logo
Logo Loox = **"đám mây" 6 hình tròn gradient chồng lên nhau** + **ngôi sao 4 cánh trắng (spark)** ở giữa. Có thêm wordmark "Loox" dạng chữ (asset riêng, có bản light/dark).

### 1.3 Palette brand (gradient logo)

| Tên | Hex | Vai trò |
|---|---|---|
| Loox Pale | `#E6F3FF` | Điểm sáng nhất của cloud |
| Loox Sky | `#7DD3FC` | Tông trung sáng |
| Loox Blue | `#00B2FF` | **Màu brand chính** |
| Loox Royal | `#2979FF` | Tông trung đậm |
| Loox Deep | `#0D47FF` | Tông đậm nhất |

Duotone cho icon/avatar brand: dots `#94D5FF` (nhạt) + glyph `#009BFF` (đậm).

### 1.4 Tính cách chuyển động (motion character)
Toàn bộ brand motion của Loox dùng chung một "ngôn ngữ": chuyển động **mềm, có đà, hơi nảy (overshoot ~1.35)**, mọi thứ được tính **theo thời gian tuyệt đối (elapsed time)** chứ không theo frame delta — mỗi frame là một hàm thuần của `t`. Web nên implement bằng `requestAnimationFrame` + các hàm easing ở mục 8.

---

## 2. Animation logo màn Welcome — LANDING LOOP (vòng lặp 12.5s)

Đây là animation chạy lặp vô hạn ở màn welcome trước khi user bấm gì.

### 2.1 Canvas & hệ toạ độ
- Không gian gốc (SVG space): **357 × 337** (đơn vị pt, scale tỉ lệ khi render).
- Tâm canvas: **(178.5, 168.05)**.
- Render scale: `scale = min(viewW/357, viewH/337)`, căn giữa.
- Trên app: bề rộng logo = `min(screenWidth × 0.56, 252)`, tỉ lệ khung 1 : 0.82.

### 2.2 Cấu trúc phần tử
1. **6 hình tròn logo** — đường kính 201, tâm cố định:
   - [0] (139.5, 235.6) · [1] (100.5, 168.05) · [2] (217.5, 235.6) · [3] (139.5, 100.5) · [4] (217.5, 100.5) · [5] (256.5, 168.05)
   - Opacity từng circle: `[1.0, 0.85, 0.85, 0.85, 0.85, 0.85]`
   - 6 linear gradient (theo index):
     - [0] `#E6F3FF → #00B2FF`, start (0.25, 0.933) → end (0.75, 0.067)
     - [1] `#7DD3FC → #00B2FF`, trái → phải
     - [2] `#7DD3FC → #2979FF`, start (0.75, 0.933) → end (0.25, 0.067)
     - [3] `#00B2FF → #2979FF`, start (0.25, 0.067) → end (0.75, 0.933)
     - [4] `#2979FF → #0D47FF`, start (0.75, 0.067) → end (0.25, 0.933)
     - [5] `#00B2FF → #0D47FF`, phải → trái
2. **Đĩa trung tâm (identity disc)** — đường kính 170, hiển thị video memoji (clip tròn), tint pastel theo theme.
3. **Ngôi sao 4 cánh trắng** — đường kính 215, chỉ hiện ở trạng thái logo.
4. **Glow** — highlight radial trắng, tâm (195.5, 186.05), đường kính 237, opacity 0.45 → 0.
5. **6 bubble icon** — khi cloud "nở" ra, mỗi circle biến thành 1 bubble icon (key, wifi, Face ID…).

### 2.3 Tần số sóng (dùng cho breathing/bobbing)
- `waveSlow = 2π/12.5 ≈ 0.503 rad/s` · `waveMid = 4π/12.5 ≈ 1.005` · `waveFast = 6π/12.5 ≈ 1.508`

### 2.4 Timeline 12.5s

| Phase | Thời gian | Nội dung |
|---|---|---|
| 1. Logo | 0 – 1.6s | Cloud đứng yên, "thở" nhẹ |
| 2. Burst | 1.6 – 2.5s | Cloud nổ ra thành cụm bubble theme 0 |
| 3. Cluster 0 | 2.5 – 4.7s | Bubbles bay quanh memoji (theme Vault) |
| 4. Swap 0→1 | 4.7 – 5.4s | Đổi sang theme 1 với hiệu ứng nảy lò xo |
| 5. Cluster 1 | 5.4 – 7.6s | Theme Sign-In |
| 6. Swap 1→2 | 7.6 – 8.3s | Đổi sang theme 2 |
| 7. Cluster 2 | 8.3 – 10.3s | Theme Identity |
| 8. Converge | 10.3 – 11.2s | Bubbles gom về lại thành logo, sao hiện lại |
| (đệm) | 11.2 – 12.5s | Trạng thái logo, nối liền vòng lặp |

**Phase 1 — Logo (0–1.6s):**
- Mỗi circle dao động: `offsetX = sin(t·waveSlow + i·1.3) × 1.6`, `offsetY = cos(t·waveMid + i·1.3) × 1.6`.
- Sao pulse nhẹ: đường kính × `(1 + 0.015·sin(t·waveMid))`.
- Đĩa memoji ẩn (opacity 0). Glow 0.45.

**Phase 2 — Burst (1.6–2.5s):**
- Tiến độ `p = (t−1.6)/0.9`; mỗi circle trễ 50ms theo index: `pi = clamp01((p − i·0.05)/0.75)`.
- Easing vị trí + kích thước: `outBack(pi)` (overshoot 1.35). Circle bay từ vị trí logo → vị trí orbital của theme 0, đường kính 201 → 60–96 tuỳ slot.
- Từ t=1.6 toàn cụm bắt đầu **trôi quay quanh tâm 6°/giây** (liên tục đến hết converge).
- Bobbing khi bay: `float(i,t) = (sin(t·waveMid + i·1.9)·3.2, sin(t·waveFast + i·1.9·2.1)·4.0)`, nhân với `pi`.
- Crossfade: gradient logo mờ dần `×(1 − smoothstep(0.25, 0.7, pi))`; bubble hiện `smoothstep(0.15, 0.55, pi)`; bóng đổ hiện muộn `smoothstep(0.5, 0.9, pi)`.
- Đĩa memoji: đường kính từ 170×0.7 → 170 qua `outBack(clamp01(p/0.85))`; tint hiện `smoothstep(0.25, 0.7, p)`. Video memoji restart tại t=1.6.
- Sao: đường kính 215 → 94 qua `inOut(p)`, opacity `1 − smoothstep(0.45, 0.8, p)`. Glow tắt `×(1 − smoothstep(0, 0.5, p))`.

**Phase 3/5/7 — Cluster (giữ ~2.2s):**
- Vị trí bubble = `orbitPoint(theme, slot, t) + float(i, t)`; orbit tiếp tục trôi 6°/s.
- Đĩa memoji bob nhẹ: đường kính `170 + sin(t·waveMid)×2`. Sao + glow ẩn.

**Phase 4/6 — Swap theme (0.7s):**
- Vị trí: `lerp(orbit_cũ, orbit_mới, inOut(p))`.
- **Hiệu ứng nảy:** mỗi slot trễ `i·0.05`: `u = clamp01((p − i·0.05)/0.78)`; `pop = exp(−3.5u)·sin(2πu)` (sin tắt dần — vượt ~10%, hụt ~6%).
- Đường kính bubble: `lerp(d_cũ, d_mới, inOut(p)) × (1 + 0.25·pop)`. Đĩa memoji: `170 × (1 + 0.12·pop)`.
- Màu bubble + tint + memoji crossfade `smoothstep(0.15, 0.85, p)`.

**Phase 8 — Converge (0.9s):**
- "Tấm màn" gradient logo phủ lên bubble: `smoothstep(0, 0.25, p)`.
- Di chuyển về vị trí logo bắt đầu trễ: `inOut(clamp01((p−0.2)/0.75))`; phóng to về 201: `inOut(clamp01((p−0.05)/0.9))`; bobbing tắt dần `×(1−p)`.
- Bubble mờ `1 − smoothstep(0.05, 0.4, p)`; bóng đổ tắt ngay `1 − smoothstep(0, 0.25, p)`; tint memoji tắt `1 − smoothstep(0.1, 0.45, p)`.
- Sao pop trở lại cuối phase: opacity `smoothstep(0.82, 1, p)`, đường kính `215 × (0.75 + 0.25·outBack(clamp01((p−0.82)/0.18)))`. Glow hiện lại `0.45 × smoothstep(0.8, 1, p)`.

### 2.5 Ba theme cluster (góc tính từ tâm canvas, khoảng cách & đường kính pt)

**Theme 0 — Vault** (tint đĩa `#E3D6FF`, memoji "wink"):

| Slot | Icon | Góc | Khoảng cách | Đường kính |
|---|---|---|---|---|
| 0 | Key | 138° | 108 | 82 |
| 1 | Wifi | 188° | 116 | 60 |
| 2 | Face ID | 76° | 110 | 74 |
| 3 | Card | −136° | 114 | 68 |
| 4 | Lock | −76° | 122 | 60 |
| 5 | Menu | −4° | 118 | 96 |

**Theme 1 — Sign-In** (tint `#CDEFDB`, memoji "gray"): Globe 130°/112/76 · Document 182°/112/64 · Touch ID 82°/114/66 · Keypad −142°/110/74 · Alert −70°/118/64 · Envelope 2°/120/90.

**Theme 2 — Identity** (tint `#FFE4C4`, memoji "blond"): QR 142°/106/70 · Note 192°/114/62 · Shield-check 74°/112/78 · Wallet −132°/112/64 · At-sign −80°/120/62 · Badge-key −8°/116/92.

Màu bubble theme 0 (tham khảo, các theme khác tương tự phong cách iOS): Key `#FFC531→#FF9F0A` · Wifi glyph `#0A84FF` trên nền trắng · Face ID `#34C759→#248A3D` · Card `#0A84FF→#0060DF` · Lock glyph `#5E5CE6` trên trắng · Menu `#2979FF→#0D47FF`.

### 2.6 Bóng đổ
- Bubble: `rgba(0,0,0, 0.16×shadowOpacity)`, blur `d×0.10`, offsetY `d×0.05` (d = đường kính bubble).
- Đĩa memoji: `rgba(0,0,0, 0.12×tintOpacity)`, blur `d×0.08`, offsetY `d×0.04`.

### 2.7 Thứ tự vẽ (z-order)
Ghost blur (khi launch) → bubbles 0–4 → đĩa memoji (clip tròn) → bubble 5 (đè lên trước) → glow → sao → bloom disc (khi launch).

---

## 3. Animation LAUNCH (1.85s, khi bấm "Get started")

Vòng lặp bị **đóng băng tại thời điểm bấm** (dù đang ở giữa phase nào), rồi chạy chuỗi sau:

| Phase | Thời gian | Nội dung |
|---|---|---|
| 0. Revert | 0 – 0.35s | Trạng thái đóng băng → blend về hình logo, easing `inOut(t/0.35)` (mọi thuộc tính lerp theo blend) |
| 1. Squash & stretch | 0.35 – 0.50s | Cả canvas scale keyframe: (1,1) → t=0.4: (1.06, 0.88) → t=0.75: (0.97, 1.04) → (1,1); nội suy `inOut` giữa từng cặp keyframe |
| 2. Shatter | 0.50 – 0.72s | Các đĩa văng xoáy: spin `0.157·p²` rad; bán kính `×(1 + 0.38·p²)`; thứ tự vòng: [2,3,1,4,5,0] |
| 3. Spiral vortex | 0.72 – 1.30s | Xoáy ốc đuổi nhau (chi tiết dưới) |
| 4. Slam | 1.30 – 1.38s | 80ms lao vào tâm thành 1 chấm đặc 121pt |
| 5. Freeze | 1.38 – 1.42s | 40ms đứng yên tuyệt đối |
| 6. Bloom | 1.42 – 1.70s | Chấm nổ bung thành đĩa full-screen |
| 7. Overlay fade | 1.70 – 1.85s | Toàn bộ animation trong suốt dần, lộ màn tiếp theo |

**Phase 3 — Spiral chi tiết:**
- `q_raw = (e−0.72)/0.58`; lag từng đĩa theo thứ tự vòng: `[0, 0.02, 0.07, 0.11, 0.18, 0.27]`; `q = clamp01((q_raw − lag)/(1 − lag))`.
- Góc xoáy: `0.05π + 10.68·q^2.1` (≈1.7 vòng, tăng tốc phi tuyến). Bán kính: `×(1.38 + 2.1·q^1.9)`.
- Đường kính: `201 × (1 + 0.65·inOut(q)) × lerp(1, depthScale, smoothstep(0, 0.35, q))`; depthScale theo vòng `[1.15, 1.05, 0.95, 0.88, 0.80, 0.74]` (đĩa dẫn đầu to hơn — cảm giác chiều sâu).
- Opacity theo vòng: `[1.0, 0.96, 0.90, 0.84, 0.76, 0.70]`, blend vào bằng `smoothstep(0, 0.3, q)`.
- **Motion blur:** 2 đĩa dẫn đầu (index 5 và 2) có 2 ghost, lấy mẫu trạng thái 24ms và 48ms trước đó, opacity `[0.35, 0.16]`, chỉ vẽ gradient (không bubble/bóng).
- Sao: co `215 × (1 − 0.55·inOut(q))`, mờ `1 − smoothstep(0.15, 0.5, q)`, **quay ngược chiều** `−(0.04π + 0.9π·q²)`.

**Phase 4 — Slam:** `p = ((e−1.30)/0.08)^1.7`; spin thêm `0.25π·p`; hệ số bán kính `lerp(3.48, 0.10, p)`; đường kính `lerp(201×1.65×depthScale, 121, p)`; opacity gom về 1.

**Phase 6 — Bloom:** `pb = (e−1.42)/0.28`; easing `1 − (1−pb)^4` (ease-out quartic); một đĩa duy nhất tại tâm, đường kính `lerp(121, 1950, ease)`; gradient `#00B2FF → #0D47FF` mờ dần `1 − smoothstep(0.25, 0.7, pb)` để lộ nền màn sau.

**Nội dung màn welcome fade:** opacity 1→0, ease-out 0.25s, delay 0.35s (bắt đầu khi revert xong).

**Haptics trong launch** (tham khảo — web có thể bỏ hoặc thay bằng âm thanh):
`0.00s soft 0.6 · 0.35s light 0.7 · 0.44s medium 0.9 · 0.90s light 0.5 · 1.08s light 0.65 · 1.22s rigid 0.75 · 1.36s HEAVY 1.0 (slam) · 1.46s rigid 0.9 (bloom) · 1.72s soft 0.5`.

---

## 4. Loox Swirl (brand loading indicator — dùng ở màn restore/pairing)

Kiểu "Apple boot": logo 6 tròn ở giữa, xung quanh là **4 vòng chấm cầu vồng** (ảnh gradient `SwirlGradient` được mask vào các chấm — mỗi chấm mang màu gradient tại vị trí của nó; chấm vẽ màu trắng làm mask).

### 4.1 Hình học (theo tỉ lệ cạnh nhỏ của khung)
- 4 vòng, **24 chấm/vòng**, vòng lẻ lệch nửa bước (`π/24`) để so le.
- Bán kính vòng: vòng 1 = 0.32, bước +0.047 → vòng 4 = 0.461. Bán kính chấm = `0.047 × bán kính vòng hiện tại`.
- Logo giữa cao 0.26 khung. Điểm sinh chấm (spawn): mép logo = 0.13.
- Canvas vẽ tràn 1.8× khung để vòng lan ra không bị cắt.

### 4.2 Ba mode
**`reveal` (một lần):** chấm "nở" từ mép logo ra 4 vòng rồi đứng yên.
- Vòng NGOÀI đi trước, các vòng sau trễ **0.20s**/vòng; hành trình mỗi vòng **1.0s**, easing `easeOutCubic` → tổng 1.6s.
- Trong hành trình, cả pattern xoáy **57°** vào vị trí: `angleOffset = parity·π/24 − 57°·(1−p)`.
- Kích thước chấm nở theo `(0.6 + 0.4p)`; alpha = `p`.

**`loop` (loading vô hạn):** một "nhịp thở"/chu kỳ = reveal 1.6s → dispersal 1.0s → nghỉ 0.2s = **2.8s/chu kỳ**. Cộng thêm **drift quay đều 15°/s** suốt chu kỳ để pattern không bao giờ đứng im.

**`dismiss` (một lần, 1.0s):** vòng đã đứng yên bung ra và tan: `p = easeOutCubic(t/1.0)`; bán kính `×(1 + 0.6p)`; alpha `(1−p)^1.3`; xoáy thêm `0.55·57°·p`.

Dùng trong app: màn pairing/restore hiển thị Swirl mode `loop` khi chờ, chuyển `reveal` khi lỗi/kết thúc. Tâm swirl có thể thay logo bằng icon khác (ví dụ shield bảo mật).

---

## 5. Loox Dots Avatar (avatar mặc định brand)

- Spark (ngôi sao brand, asset `LooxSpark`) ở giữa + **2 vòng chấm tĩnh**: 18 chấm/vòng, vòng ngoài bán kính 0.86 nửa-khung, vòng trong = 0.86×0.79, so le nửa bước.
- Chấm ngoài bán kính 0.082, trong 0.055 (nửa-khung). Mỗi chấm có size/opacity ngẫu-nhiên-tất-định (hash theo index): size ×(0.85+0.3h₁), alpha (0.55+0.45h₂).
- Màu: chấm `#94D5FF`, glyph giữa `#009BFF`. Đĩa lõi nền trắng 0.55 khung phía sau glyph.
- **Reveal khi xuất hiện:** giống swirl thu nhỏ — travel 0.55s, vòng trong trễ 0.15s, xoáy 57° ease-out vào vị trí.
- Biến thể "mời thêm ảnh": glyph spark ↔ camera hoán đổi mỗi 1.5s bằng spring `response 0.45, damping 0.55` (scale + opacity).

---

## 6. Animation Restore / Scan QR

### 6.1 Scanner overlay (phong cách Telegram)
Thành phần: lớp phủ đen có "lỗ" vuông bo góc ở giữa + 4 góc ngoặc chữ L trắng.

- Khung idle: cạnh = `min(W,H) × 0.66`, tối đa 300; bo góc **14**; lệch tâm lên 24. Ngoặc: dài cánh 28, bo 8, nét trắng **4**, đầu nét tròn.
- Màu cố định (không theo theme — nền camera luôn tối): overlay đen alpha **0.55** (idle) / **0.82** (focus); ngoặc trắng.

**Entry (mở màn):** khung scale **0.4 → 1.0** bằng spring; đồng thời fade-in opacity 0→1 trong 0.4s (linear).
- **Spring chuẩn của scanner: stiffness 900, damping 88, mass 5, v₀ = 0** (dùng cho mọi morph khung). CSS tương đương: có thể xấp xỉ bằng `linear()` timing sinh từ spring params này.

**Phát hiện QR (focus):** khung spring-morph từ ô idle → bám khít mã QR (bounds × 1.3, cạnh tối thiểu 90); overlay tối lên 0.55 → 0.82 trong 0.4s easeInOut. Mất dấu QR → trở về idle với cùng tham số.

**Thành công:** rung haptic success **ngay khi nhận diện**; giữ **0.5s** cho animation bám khung chạy xong rồi mới đóng scanner/chuyển bước.

State machine: `Idle → Searching → (thấy QR) Focused → (0.5s) Success → đóng` · `Focused → (mất dấu) Searching`.

### 6.2 Phong cách hiển thị mã QR (phía tạo mã)
- QR của Loox render **module bo tròn**: ô đơn lẻ = chấm tròn; dãy ô liền = "viên thuốc" bo tròn (bán kính = cell×0.5); 3 ô finder = khung bo tròn (bán kính = cell×2.2).
- Luôn **đen trên nền trắng** (không theo theme — để máy quét đọc được), nền trắng padding 16, bo góc 20.
- Bản thân mã QR **không có animation** xuất hiện; màn pairing dùng **Loox Swirl mode `loop`** (mục 4) làm loading bên cạnh.

### 6.3 Màn Emergency/Recovery Kit (chi tiết nhỏ)
- Nút "Save PDF" → "Continue" hoán đổi bằng crossfade 0.2s ease-out sau khi lưu thành công.
- Copy recovery key: icon copy → checkmark xanh (theme success), fade-in 0.15s, giữ 2s, tự trở lại 0.2s easeInOut.

---

## 7. Badge MAX

Badge "MAX" là **phần tử tĩnh, không animation** (quyết định thiết kế có chủ đích — chuyển động dành cho khung card/danh sách quyền lợi xung quanh, không phải badge).

### 7.1 Spec (mọi kích thước scale theo tham số `height`, mặc định 18)

| Thuộc tính | Giá trị |
|---|---|
| Hình dạng | Rounded rectangle, góc continuous (squircle) |
| Bo góc | `height × 0.26` |
| Nền chip | `#101114` (mực tối — **cố định cả light lẫn dark mode**, không theo theme) |
| Chữ | "MAX", trắng `#FFFFFF`, weight 900 (heavy), **italic**, size `height × 0.58`, letter-spacing `height × 0.08` |
| Padding ngang | `height × 0.3` |
| Viền (ring) | Linear gradient chéo (top-left → bottom-right): `#7C3AED` (0%) → `#DB2777` (62%) → `#EC4899` (100%); dày `max(1.5, height × 0.09)` |
| Glow (tuỳ chọn) | `#A78BFA` alpha 35%, blur `height × 0.16`; bật mặc định, tắt trong lockup dày đặc (ví dụ trong nút CTA) |

Cách dùng trong lockup: "Loox ​[MAX]" — badge đặt sau chữ "Loox". Kích thước theo ngữ cảnh trên app: card gói 18 · nút CTA 19 (compact, không glow) · dòng "Your plan" 15.

### 7.2 Màu nhận diện Max (ngoài badge)
- Light UI: gradient `#0B0B0F → #1F1F26 (62%) → #4C1D95`; màu đặc `#111114`.
- Dark UI: gradient `#7C3AED → #DB2777 (62%) → #EC4899`; màu đặc `#E879F9`.
- Chữ trên nền tint: trắng.

### 7.3 Loox+ không có badge
"Loox+" chỉ là chữ thường (kế thừa font/màu xung quanh) — có chủ đích để giữ thứ bậc: chỉ Max có badge.

---

## 8. Thư viện easing & motion token dùng chung

### 8.1 Motion token của app (cho micro-interaction)
- Durations: fast **0.14s** · base **0.20s** · medium **0.26s** · slow **0.32s**.
- Curve chuẩn: `cubic-bezier(0.32, 0.72, 0, 1)`, duration 0.20s.
- Spring chuẩn: response 0.34s, dampingFraction 0.86.
- Press scale: 0.97.

### 8.2 Hàm easing của brand animation (pseudocode)
```
clamp01(x)              = min(max(x, 0), 1)
lerp(a, b, t)           = a + (b − a)·t
smoothstep(e0, e1, x)   : t = clamp01((x−e0)/(e1−e0)); return t²(3 − 2t)
inOut(p)                : t = clamp01(p); return t < 0.5 ? 4t³ : 1 − (−2t+2)³/2
outBack(p, s = 1.35)    : t = clamp01(p) − 1; return 1 + t²((s+1)t + s)
easeOutCubic(x)         = 1 − (1−x)³
```

### 8.3 Nguyên tắc render
- Mọi brand animation là **hàm thuần của thời gian trôi qua** (không tích luỹ trạng thái theo frame) → dùng `requestAnimationFrame`, tính từ timestamp bắt đầu. Chạy mượt cả 60Hz lẫn 120Hz.
- Memoji: video có alpha (trên web dùng WebM VP9 alpha hoặc HEVC alpha cho Safari), clip trong hình tròn, loop.

---

## 9. Reduce Motion (`prefers-reduced-motion`)

App tôn trọng Reduce Motion triệt để, web nên làm tương tự:

| Animation | Khi Reduce Motion bật |
|---|---|
| Landing loop (welcome) | **Không chạy** — chỉ hiện logo tĩnh |
| Launch 1.85s | Thay bằng fade-out 0.25s, chuyển màn sau 0.26s, không haptic |
| Swirl reveal | Hiện luôn 4 vòng đã đứng yên |
| Swirl loop | Đứng yên ở trạng thái settled |
| Swirl dismiss | Hiện trạng thái đã tan (trống) |
| Dots avatar reveal | Hiện pattern đã đứng yên |
| Scanner overlay | Đổi trạng thái tức thì (duration 0) |
| Micro-interaction | Collapse về thay đổi tức thì |

---

## 10. Các gói Subscription

> **Trạng thái hiện tại:** tính năng subscription đang **tắt bằng feature flag** trên bản App Store (TestFlight/App Review được bật sớm). Giá lấy từ cấu hình StoreKit — giá thực tế theo storefront do Apple quyết định, website nên ghi chú "giá có thể khác theo khu vực".

### 10.1 Tên & giá

| Gói | Chu kỳ | USD | VND | Trial |
|---|---|---|---|---|
| **Loox Max** | Năm | $34.99 | 349.000₫ | **7 ngày miễn phí** |
| **Loox Max** | Tháng | $4.99 | 49.000₫ | — |
| **Loox+** | Năm | $19.99 | 199.000₫ | — |
| **Loox+** | Tháng | $2.99 | 29.000₫ | — |

- Chỉ **Max Annual có trial 7 ngày**; sau trial tự gia hạn giá năm đầy đủ. Max Annual là gói chủ đạo (được preselect trong app).
- Điểm bán hàng theo giá: `$34.99/12 ≈ $2.92/tháng` — **Max theo năm rẻ hơn Loox+ theo tháng** (USD); ở VN thì "xấp xỉ bằng nhau" (349.000/12 ≈ 29.083₫ so với 29.000₫).

### 10.2 Định vị copy (EN, từ app)
- **Loox Max:** "Everything Loox can do. For your whole world." — "Full security workflow, sharing and services."
- **Loox+:** "Set it once. Stay protected." — "Personal security, maintained."

### 10.3 Bảng tính năng theo gói

**Miễn phí cho tất cả (kể cả Free):** không giới hạn số item (password, passkey, TOTP, note, thẻ, danh tính) · AutoFill + Safari extension · mở khoá sinh trắc học · iCloud sync, import/export, backup mã hoá · Spaces, tags, favorites, archive · password generator · Watchtower mức Critical/High · nhận chia sẻ Approval Mode.

| Tính năng | Loox (Free) | Loox+ | Loox Max |
|---|---|---|---|
| Watchtower đầy đủ (mọi finding, Fix Queue, lịch sử, nhắc định kỳ) | ✗ | ✓ | ✓ |
| Bộ theme/accent đầy đủ | Bộ cơ bản | ✓ | ✓ |
| Profiles (persona) | 1 | 3 | Không giới hạn sản phẩm |
| Private Email aliases (đang giữ: active + paused) | 1 | 10 | 200 |
| Loox Link (link chia sẻ, cửa sổ trượt 30 ngày) | 3 | 30 | 300 |
| Quick View "Open on Computer" (30 ngày) | 3 | 30 | 300 |
| Ghế chia sẻ Approval Mode (người nhận đang active) | 0 | 1 | 10 |

Quy tắc quota: chỉ thao tác thành công mới tính; revoke không hoàn quota; alias xoá vĩnh viễn giải phóng quota nhưng địa chỉ bị "đốt" vĩnh viễn; chia sẻ nhiều item cho cùng 1 người = 1 ghế.

### 10.4 Câu chữ pháp lý (từ app, EN)
- "First 7 days free, then $34.99 each year. Auto-renews until canceled. Cancel anytime in Settings."
- "Auto-renews at $X each month/year until canceled."

---

## 11. Toàn bộ tính năng app (cho trang marketing)

**Định vị chung:** Loox Password — trình quản lý mật khẩu & passkey **riêng tư, offline-first, zero-backend**. iPhone (iOS 17.3+). Không tài khoản, không tracking, không analytics. Vault mã hoá nằm trên máy; dữ liệu chỉ rời máy khi user bật iCloud sync (E2E encrypted) hoặc chủ động chia sẻ.

### 11.1 Vault & loại item
- **8 loại item:** Login (username, password, nhiều website, TOTP) · Secure Note · Payment Card · Identity (tên, email, SĐT, địa chỉ, ngày sinh, số giấy tờ) · SSH Key · Recovery Codes · Security Questions · Custom (tự định nghĩa field).
- **12 loại field động:** text, username, password, TOTP, website, email, number, phone, note nhiều dòng, monospace, date, attachment (file đính kèm mã hoá, xem bằng Quick Look).
- Field bảo vệ (ẩn mặc định, chạm để lộ) · **Extra Password** (mật khẩu phụ cấp 2 cho field siêu nhạy cảm, không thể khôi phục nếu quên) · favorites/pin · tags.

### 11.2 Bảo mật & mã hoá
- **Argon2id** (OWASP: t=3, m=64MiB, p=4) dẫn xuất khoá từ master password; vault mã hoá **AES-256-GCM** từng item.
- Mở khoá **Face ID/Touch ID** (khoá vault trong Keychain gated Secure Enclave; 3 lần sinh trắc thất bại → fallback master password).
- **Auto-lock** cấu hình được (ngay lập tức/1/5/15/60 phút) · lắc máy để khoá · Privacy Shield che nội dung trong App Switcher.
- **Emergency Kit:** recovery key 32 ký tự + PDF in được kèm QR Setup Code — đường khôi phục duy nhất (không có reset qua email).

### 11.3 Passkeys (WebAuthn)
- Tạo, đăng nhập, quản lý passkey chuẩn WebAuthn (ES256). Hỗ trợ nhiều passkey/site, trạng thái backup (Backed up / eligible / This device only), largeBlob (iOS 18+), tự động nâng cấp password→passkey (iOS 18+).

### 11.4 AutoFill & Safari Extension
- **AutoFill hệ thống:** điền password + passkey trong mọi app/trình duyệt; tạo login mới ngay từ form đăng ký với mật khẩu mạnh tự sinh; không bao giờ điền "im lặng" — luôn cần Face ID/master password.
- **Safari extension (MV3):** điền identity/thẻ thanh toán, menu inline, sinh mật khẩu khi đăng ký, lưu login mới, passkey; điều khiển theo site ("never save", "hide on this site"). Kiến trúc bảo mật: khoá vault không bao giờ qua cầu native↔JS.

### 11.5 Watchtower (kiểm toán bảo mật)
- Chạy hoàn toàn trên máy. **Security Score 0–1000** (6 trụ: độ mạnh mật khẩu, lộ breach, tái sử dụng, phủ 2FA, độ đầy đủ, rotation).
- Phát hiện: mật khẩu **bị lộ** (HIBP với k-anonymity — chỉ 5 ký tự đầu của hash rời máy) · **tái sử dụng** · **yếu** · **thiếu 2FA** (danh mục site hỗ trợ 2FA) · **quá hạn thay** (nhắc xoay vòng 15/30/90 ngày + thông báo cục bộ).
- Fix Queue hướng dẫn sửa từng lỗi + lịch sử audit có diff.

### 11.6 Password Generator
- 3 chế độ: **Password** (8–64 ký tự, tuỳ chọn hoa/thường/số/ký hiệu/tránh ký tự dễ nhầm, thước đo độ mạnh) · **Passphrase** (3–10 từ EFF Diceware, chọn dấu phân cách) · **PIN** (4–12 số).

### 11.7 Tổ chức & tìm kiếm
- **Spaces** (nhóm có icon/màu, tên mã hoá) · tags · **Personas** (nhiều hồ sơ cô lập: Standard/Isolated/Strictly Anonymous — hồ sơ ẩn danh chặn tìm kiếm chéo) · tìm kiếm token AND trên tiêu đề/field/tag/Space với phạm vi Space hiện tại / tất cả / được chia sẻ · Archive & Recently Deleted.

### 11.8 Chia sẻ
- **Approval Mode** (Loox-to-Loox qua iCloud): chia sẻ từng field theo quyền — password (ẩn/luôn xem), TOTP (ẩn/tĩnh/**hỏi mỗi lần** — chủ vault duyệt bằng Face ID từng lượt), passkey. Bí mật không bao giờ rời vault chủ; mã một lần niêm phong bằng HPKE (Curve25519).
- **Loox Link:** chia sẻ field bất kỳ cho người **không cần cài Loox** qua URL mã hoá (AES-256-GCM, khoá nằm trong fragment URL — server không bao giờ thấy); hết hạn 1h/24h/7 ngày/30 ngày; thu hồi được.
- **Quick View "Open on Computer":** đưa field lên trình duyệt máy tính một-lần-duy-nhất — quét QR, xác minh mã SAS, duyệt Face ID, mã hoá E2E tới khoá tạm của trình duyệt, không lưu lại phía nhận.

### 11.9 Private Email
- Sinh **alias email ẩn danh** cho từng site (relay chuyển tiếp về hộp thư thật); tạm dừng/thu hồi từng alias; nhiều domain.

### 11.10 Đồng bộ & di chuyển dữ liệu
- **iCloud sync** (tuỳ chọn, tắt mặc định): chỉ đồng bộ ciphertext — khoá vault không bao giờ rời máy; ghép máy mới bằng quét QR giữa 2 thiết bị.
- **Import:** CSV từ 1Password, Bitwarden, Chrome (tự nhận diện) + backup mã hoá `.vaultify` (kèm passkey).
- **Export:** CSV (có cảnh báo không mã hoá; passkey không bao giờ xuất CSV) + backup mã hoá `.vaultify` bằng mật khẩu riêng.

### 11.11 Giao diện & trải nghiệm
- Theme Day/Night + **Auto-Night** (theo hệ thống/lịch/độ sáng) · 7 accent preset đạt WCAG · Dynamic Type · hỗ trợ đầy đủ Reduce Motion, Reduce Transparency, Increased Contrast, VoiceOver.
- **Song ngữ EN + Tiếng Việt** với toggle trong app.
- Thông báo: nhắc xoay vòng mật khẩu (cục bộ) + push cho yêu cầu/kết quả Approval Mode và trạng thái chia sẻ.

### 11.12 Điểm nhấn quyền riêng tư (App Store privacy)
- Không user ID, không tracking, không SDK bên thứ ba, không analytics. Vault mã hoá dưới master password, không gắn với danh tính.

> **Lưu ý cho web team:** một số tính năng đang staged/feature-flagged (subscription chưa bật public, Quick View đang staging chờ backend, invite link đang trên branch). Trước khi đưa lên site, xác nhận lại với chủ dự án tính năng nào đã live trên bản App Store hiện hành.

---

## 12. Danh sách assets sẽ gửi kèm (từ chủ dự án)

1. Logo: `BrandSymbol` (cloud + star), `BrandLogo` wordmark (bản light + dark), `LooxSpark`.
2. Video memoji × 3 (wink / gray / blond) — nền alpha, loop.
3. Ảnh `SwirlGradient` (gradient cầu vồng cho Swirl).
4. `loox-max-badge.svg` (bản vẽ tham chiếu badge Max).

## Câu hỏi chưa chốt

1. Giá trị hex chính xác của "paywall blue" sau khi qua guard WCAG (base `#009DFF`, app tính runtime) — nếu web cần đúng tuyệt đối, đo từ app hoặc hỏi team native.
2. Website công bố subscription ngay hay chờ flag bật trên App Store?
3. Bộ icon trong bubble (Polaris SVG) có được cấp cho web dùng lại không, hay design team vẽ lại?
