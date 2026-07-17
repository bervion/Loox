# Loox — Spec Animation Ring màn Bảo mật (Watchtower Score Gauge)

**Ngày:** 17/07/2026 · **Nguồn:** trích xuất trực tiếp từ `WatchtowerScoreRing.swift` (app iOS)
**Người nhận:** Team FE web — tài liệu bổ sung cho file handoff brand đã gửi trước
(`handoff-260717-1018-loox-web-brand-animations.md`)

---

## 1. Khái niệm & quyết định thiết kế cốt lõi

Ring ở màn Bảo mật là **đồng hồ đo "nhiệt kế" 270°** hiển thị Security Score (0–1000), phong cách 1Password. Có 3 quyết định thiết kế **bắt buộc giữ đúng** khi port sang web:

1. **Vòng band LUÔN được vẽ đầy đủ 270°** — điểm số KHÔNG được thể hiện bằng độ dài cung. Điểm số được truyền đạt bằng: (a) **màu** của cả band, (b) **con số đếm lên kiểu odometer**, (c) **mũi tên tam giác** chỉ vị trí điểm trên band.
2. **Cả mặt đồng hồ là một ĐĨA QUAY (flywheel)**: gradient conic của band + các vạch tick quay CÙNG NHAU như bánh đà gắn lò xo underdamped — quay nhanh về phía trước, vượt quá, quay ngược lại, dao động rồi đứng yên.
3. **Animation là "khoảnh khắc dữ liệu đến", không phải trang trí tab**: intro chỉ chạy khi có dữ liệu mới (đổi persona / pull-to-refresh), KHÔNG chạy lại mỗi lần quay lại màn. Điểm thay đổi ngầm (do sửa item ở nơi khác) → cập nhật số lặng lẽ, không animation.

Toàn bộ animation là **hàm thuần của thời gian trôi qua** (elapsed time), render mỗi frame bằng clock thật (trên web: `requestAnimationFrame`). Sau khi intro kết thúc → **đóng băng thành render tĩnh** (không vẽ tiếp, tiết kiệm pin/CPU).

---

## 2. Hình học (không gian gốc, scale tỉ lệ theo khung)

| Thông số | Giá trị |
|---|---|
| Khung gốc | **260 × 218** (mọi số dưới đây theo không gian này; scale = `viewWidth / 260`) |
| Tâm cung (cx, cy) | **(130, 118)** |
| Bán kính (đường tâm của band) | **104** |
| Bề dày band | **26** |
| Đầu nét | Bo tròn (round cap) ở cả 2 đầu |
| Góc bắt đầu | **135°** (hướng 0° = 3 giờ, quay theo chiều kim đồng hồ dương) |
| Góc quét | **270°** (kết thúc tại 135° + 270° = 405° ≡ 45°) — khe hở 90° nằm ở đáy |
| Số tick trên đĩa | **28** vạch chia đều FULL 360° (không phải chỉ trong cửa sổ 270°) |

28 chia hết 360° → pattern liền mạch khi quay, so le dài/ngắn đều, và khi đĩa đứng yên có đúng 1 tick nằm tại mỗi mép cửa sổ.

Lưu ý clip: mép ngoài band (`cy − radius − bandWidth/2`) phải cách mép canvas ≥ 1pt, nếu không đỉnh cung bị cắt phẳng.

---

## 3. Thang điểm & band ngữ nghĩa

- Điểm hiển thị trực tiếp trên thang **0–1000**.
- Phân band theo ngưỡng: **≥ 800** "Fairly secure" (role success, xanh) · **≥ 500** "Needs attention" (warning, hổ phách) · **< 500** "At risk" (destructive, đỏ).
- `targetFraction = clamp(score, 0, 1000) / 1000` — dùng cho vị trí marker và pha màu.

---

## 4. Timeline intro — tổng **2.3 giây**

Tiến độ `p = elapsed / 2.3`, clamp về [0, 1]. Các mốc là **phân số của p**:

| Phase | p | Thời gian thực | Nội dung |
|---|---|---|---|
| 1. Ignite | 0 → 0.16 | 0 → 0.368s | Track xám crossfade sang màu ĐỎ (destructive) trên TOÀN band |
| 2. Hold | 0.16 → 0.25 | 0.368 → 0.575s | Ngưng một nhịp ở màu đỏ, số vẫn là 0 |
| 3. Count | 0.25 → 0.83 | 0.575 → 1.909s | Số cuộn lên odometer; màu CẢ BAND morph đỏ → hổ phách → xanh; đĩa bắt đầu quay lò xo |
| 4. Marker rise | 0.74 → 1.0 | 1.702 → 2.3s | Tam giác marker "mọc" từ phía số lên sát band, nảy nhẹ, fade-in |
| 5. Spin fade | 0.88 → 1.0 | 2.024 → 2.3s | Dao động dư của lò xo được blend về đúng tư thế nghỉ (để đóng băng liền mạch) |

Đồng thời trong Count: caption "Calculating" hiển thị; khi settle xong → crossfade sang nhãn band ("Fairly secure"…).

### 4.1 Các hàm tiến độ con

```
igniteAmount(p) = easeInOut( clamp01( p / 0.16 ) )              // 0 = track xám, 1 = full màu
countProgress(p) = easeInOut( clamp01( (p − 0.25) / (0.83 − 0.25) ) )  // 0→1 cho số + màu
markerProgress(p) = clamp01( (p − 0.74) / (1 − 0.74) )          // tuyến tính, easing nằm trong marker
```

`f = countProgress(p) × targetFraction` — "fraction hiện hành" dùng để pha màu band tại từng frame (màu chạy từ 0 đến điểm thật, tức luôn đi qua đỏ → … → màu đích).

---

## 5. Đĩa quay — lò xo underdamped (phần hồn của animation)

Đĩa (gradient conic + ticks) quay theo **step response của lò xo giảm chấn dưới mức**:

**Tham số:**
- Góc đích (rest pose): `travel = 80°`
- Damping ratio: `ζ = 0.28` (underdamped → có đảo chiều)
- Tần số tự nhiên: `ω = 4.2 rad/s`

**Công thức** (s = số giây kể từ lúc Count bắt đầu, tức `s = (p − 0.25) × 2.3`):

```
discRotation(p):
  nếu p ≤ 0.25:  return 0
  nếu p ≥ 1:     return 80
  s     = (p − 0.25) × 2.3
  zw    = ζ·ω                        // 1.176
  wd    = ω·√(1 − ζ²)                // ≈ 4.032 rad/s (tần số giảm chấn)
  decay = e^(−zw·s)
  response = 1 − decay·( cos(wd·s) + (zw/wd)·sin(wd·s) )
  spring   = 80 × response
  // Blend dao động dư về đúng 80° trong đoạn cuối (p ≥ 0.88):
  blend = easeInOut( clamp01( (p − 0.88) / (1 − 0.88) ) )
  return spring + (80 − spring) × blend
```

**Cách áp dụng — QUAN TRỌNG:** góc quay áp vào gradient/tick là **delta so với tư thế nghỉ**: `spin = discRotation(p) − 80`. Tức khi settle, `spin = 0` và layout gradient + tick trùng khớp 100% với thiết kế tĩnh (frame đóng băng không bị lệch). Trong lúc quay, `spin` âm (đĩa đang "đuổi theo" tư thế nghỉ), có lúc dương nhẹ khi vượt quá.

Cảm giác thị giác: quay tới nhanh → vượt đích → quay ngược → dao động tắt dần → đứng yên (đúng "flywheel" 1Password).

---

## 6. Hệ màu

### 6.1 Hàm blend cơ bản
`blend(a, b, t)` = nội suy tuyến tính **từng kênh RGB** từ màu a về màu b theo t ∈ [0,1] (làm tròn từng kênh).

### 6.2 Màu hiển thị của gauge (display hues)
Token ngữ nghĩa `success`/`warning` của theme được tinh cho CHỮ (đậm, đủ tương phản) — dùng thẳng lên band rộng sẽ bị nặng và lệch tông. Nên band dùng bản "vivid" kéo về màu thuần:

```
gaugeGreen(theme) = blend(theme.success, #2DB616, 0.60)
gaugeAmber(theme) = blend(theme.warning, #F5A623, 0.55)
```

**Giá trị tính sẵn cho 2 theme mặc định:**

| Theme | destructive | gaugeAmber | gaugeGreen | accent (base) |
|---|---|---|---|---|
| Day (light) | `#E5484D` | `#D68D13` (từ warning `#B06F00`) | `#25A633` (từ success `#1A8E5F`) | `#009DFF` |
| Night (dark) | `#FF5C5C` | `#FABC18` (từ warning `#FFD60A`) | `#2EC130` (từ success `#30D158`) | `#009DFF` |

**Chú ý:** chữ/nhãn band vẫn dùng token ngữ nghĩa gốc (success/warning/destructive), chỉ có SƠN BAND dùng bản vivid.

### 6.3 Đường morph màu an toàn (safety blend)
Màu nền của band tại fraction `f` (piecewise, 2 chặng):

```
safetyRGB(f):
  nếu f < 0.5:  blend( destructive, gaugeAmber, f / 0.5 )
  ngược lại:    blend( gaugeAmber, gaugeGreen, (f − 0.5) / 0.5 )
```

Trong intro, `f` chạy từ 0 → targetFraction, nên band luôn khởi đầu đỏ và morph dần tới màu đích — kể cả điểm cao.

### 6.4 Gradient conic của band (multi-tone, quay cùng đĩa)
Với `base = safetyRGB(f)` tại frame hiện hành:

```
head = blend(base, #000000, 0.10)                       // đầu đậm hơn 10%
tail = blend(base, theme.accent, 0.30 × fraction)       // đuôi ngả accent theo điểm
```

Conic gradient (tâm = tâm cung, góc gốc = `135° + spin`), các stop **wrap liền mạch**:

| Location | Màu |
|---|---|
| 0.00 | head |
| 0.42 | base |
| 0.75 | tail |
| 1.00 | head (nối vòng — mối nối nằm trong khe 90° ẩn khi đứng yên, và không lộ seam khi quay) |

Ở tư thế nghỉ: cửa sổ 270° chiếm location 0 → 0.75 của vòng conic (head tại đầu cung, base ở đỉnh, tail tại cuối cung); đoạn 0.75 → 1 là phần blend ngược về head nằm trong khe hở.

Toàn bộ band nhân alpha = `igniteAmount(p)` (giai đoạn ignite: track xám → màu).

### 6.5 Track nền
Cung 270° y hệt band, vẽ TRƯỚC band: màu `primaryText` của theme với **opacity 0.08**, cùng bề dày 26, round cap. (Day: đen 8% trên nền trắng; Night: trắng 8%.)

---

## 7. Ticks (vạch chia trên band)

- **28 vạch** chia đều đĩa 360°, góc mỗi vạch = `(360/28)·i + spin`, chuẩn hoá về [0, 360); **chỉ vẽ vạch có offset ≤ 270.5°** (clip vào cửa sổ khi đĩa quay — vạch "chạy" vào/ra hai mép).
- Xen kẽ dài/ngắn: i chẵn = major, i lẻ = minor.
- Bán kính trong: `innerR = r − bw/2 + 3` (tức 104 − 13 + 3 = 94 ở scale 1).
- Bán kính ngoài: major `innerR + bw × 0.58`, minor `innerR + bw × 0.38`.
- Nét: **1.8** (× scale), round cap.
- Màu: `blend(base, #000000, 0.30)` — bản đậm hơn 30% của màu band hiện hành — với opacity `0.85 × igniteAmount(p)`. Tick đổi màu THEO band trong suốt quá trình morph.

---

## 8. Marker tam giác

Tam giác nằm **bên trong** vòng, **đỉnh chỉ ra ngoài** về phía band, đặt tại góc của điểm số THẬT (không sweep theo count):

- Góc: `angle = 135° + 270° × targetFraction`.
- Kích thước: rộng **16**, cao **13** (× scale). Khe cách mép trong band: **6**.
- Bo góc: đạt được bằng stroke **4** với `lineJoin: round` đè lên fill cùng màu (web: `stroke-linejoin="round"` cùng màu fill, hoặc path bo sẵn).
- Màu: `safetyRGB(targetFraction)` — màu đích cuối, KHÔNG đổi theo màu đang morph.
- **Animation rise (trong cửa sổ p = 0.74 → 1):**
  - Vị trí tâm bán kính: `centreR = r − bw/2 − 6 − 13/2 − rise`, với `rise = (1 − easeOutBack(progress)) × 26` — marker khởi đầu thấp hơn 26pt (gần con số), đi lên, **vượt nhẹ quá vị trí nghỉ rồi nảy về** (easeOutBack).
  - Opacity: `easeOut(progress)` (cubic).
  - Tam giác xoay theo góc: hướng đỉnh trùng phương bán kính (rotate `angle + 90°`).

---

## 9. Readout (con số + nhãn) — nằm NGOÀI canvas

Con số không vẽ trong canvas (để tận dụng hiệu ứng chữ số cuộn):

- **Số:** typography cỡ largeTitle, màu chữ primary, **monospaced digits** (chống giật ngang khi cuộn).
- **Odometer roll:** trong pha Count, cứ mỗi **40ms** cập nhật `displayedScore = round(countProgress(p) × score)`, mỗi bước chuyển được animate tuyến tính **90ms** với hiệu ứng chữ số cuộn dọc (iOS: `.contentTransition(.numericText)`; web: kỹ thuật digit-roll — mỗi chữ số là cột trượt dọc, hoặc thư viện tương đương). Cadence 40ms đủ nhanh để cuộn liên tục thành "blur odometer", đủ chậm để rẻ.
- **Blur khi đang cuộn:** number có `blur 1.1px` trong lúc `rolling = true` (p trong [0.25, 0.83)), gỡ blur bằng transition 0.2s khi dừng.
- **Nhãn dưới số:** 2 lớp chồng nhau, crossfade 0.2s (curve chuẩn `cubic-bezier(0.32, 0.72, 0, 1)`):
  - "Calculating" — style sectionLabel, màu secondary, letter-spacing 1.4 — hiện khi chưa settle.
  - Nhãn band ("Fairly secure" / "Needs attention" / "At risk") — màu dùng **token ngữ nghĩa rời rạc** theo ngưỡng 800/500 (success/warning/destructive gốc, KHÔNG phải màu sweep) — hiện khi settle.
- Vị trí: số đặt sao cho baseline khối nằm quanh tâm cung (trong app: cột dọc bắt đầu tại `cy − 28`, số rồi nhãn cách 2pt).

Kết thúc intro: set số về đúng target với transition chuẩn 0.2s, `settled = true`, và **tắt clock** (đóng băng canvas thành frame tĩnh).

---

## 10. Logic replay (gate) — hành vi, không phải hiệu ứng

- Intro gắn với **introKey = "persona|refreshCount"** (định danh ngữ cảnh dữ liệu). Chỉ chạy khi key ĐỔI (lần đầu vào, đổi persona, pull-to-refresh). Quay lại màn cùng key → hiển thị ngay trạng thái settled, không replay.
- Điểm số thay đổi ngầm khi không animate → cập nhật số/màu tức thì, không intro.
- Nếu điểm đổi GIỮA intro → clock đang chạy tự đáp xuống target mới (vì mọi thứ tính từ `score` hiện hành mỗi frame).
- Web tương đương: chạy intro khi dữ liệu score được fetch/refresh xong, không chạy khi điều hướng qua lại.

---

## 11. Reduce Motion

`prefers-reduced-motion: reduce` → **không chạy intro**: render ngay frame settled (band full màu đích, số = target, marker tại chỗ, nhãn band hiện sẵn). Không có phiên bản rút gọn — bỏ hẳn.

---

## 12. Thư viện easing dùng trong ring

```
clamp01(x)      = min(max(x, 0), 1)
easeInOut(t)    = t < 0.5 ? 4t³ : 1 − (−2t + 2)³/2          // cubic in-out
easeOut(t)      = 1 − (1 − t)³                               // cubic out (marker fade)
easeOutBack(t)  : c1 = 1.70158; c3 = c1 + 1; u = t − 1
                  return 1 + c3·u³ + c1·u²                   // marker bounce (chuẩn CSS easeOutBack)
Spring underdamped: xem mục 5 (ζ = 0.28, ω = 4.2, travel = 80°)
```

Curve chuẩn cho micro-transition (blur, crossfade nhãn, số đáp cuối): `cubic-bezier(0.32, 0.72, 0, 1)`, 0.20s.

---

## 13. Thứ tự vẽ mỗi frame (pseudocode tổng hợp)

```
render(now):
  p     = clamp01((now − start) / 2.3)
  f     = easeInOut(clamp01((p − 0.25) / 0.58)) × (score / 1000)
  spin  = discRotation(p) − 80
  base  = safetyRGB(f)
  alpha = easeInOut(clamp01(p / 0.16))

  1. drawTrack()                       // cung 270°, primaryText @ 8%
  2. drawBand(base, spin, alpha)       // conic gradient head/base/tail quay theo spin
  3. drawTicks(base, spin, alpha)      // 28 vạch full đĩa, clip cửa sổ 270°
  4. drawMarker(targetFraction, markerProgress(p))   // tam giác rise + fade
  // Ngoài canvas: odometer number (tick 40ms) + crossfade nhãn
  nếu p ≥ 1: dừng rAF, giữ frame tĩnh
```

Gợi ý kỹ thuật web (tuỳ team chọn): `<canvas>` 2D với conic gradient (`createConicGradient`) là gần bản gốc nhất; SVG cũng khả thi (mask cung 270° + conic bằng foreignObject/paint-server hạn chế — canvas dễ hơn cho gradient quay). Số + nhãn nên là DOM text đè lên canvas để lấy digit-roll và accessibility.

Accessibility: phần tử tổng nên có label dạng "Security score: {score}, {band label}"; canvas ẩn với screen reader.

---

## Câu hỏi chưa chốt

1. Web dùng theme màu riêng hay bám 2 theme Day/Night của app? Nếu web có palette riêng, chỉ cần thay 4 màu neo (destructive, warning, success, accent) rồi giữ nguyên toàn bộ công thức blend/gradient.
2. Trên web, score lấy từ đâu (không có vault cục bộ) — nếu ring chỉ dùng minh hoạ marketing với số cố định, vẫn nên chạy đủ choreography intro với `score` cứng để đúng cảm giác brand.
