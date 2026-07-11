# Nghiên cứu: contrast guard cho tint color mọi light/dark case — 260711

## Câu hỏi
User: "dark mode + tint black thì UI chìm — có giải pháp gì cover toàn bộ case chọn tint
cho dark/light mode chuẩn độ tương phản?"

## Hiện trạng (verified, file:line)

Kiến trúc accent 3 lớp:
1. `AccentPreset` (`VaultifyCore/Theme/AccentColor.swift`): 7 preset, MỖI preset mang cặp hue
   light + dark (`rgb(isDark:)`) — mono light = `0x1C1C1E`, mono dark = `0xFFFFFF`.
2. `AppTheme.recolored(accent:)` (`AppTheme.swift:45`): derive switchOn/checkmark/selection,
   `accentForeground = RGBMath.onAccent(accent)` (white-preferred, floor 3.0).
3. Derived tokens (`AppTheme+Tokens.swift:32-34`): `accentSoft = blend(selection, accent, .15)`,
   `accentPress`.

### Case giả định "black tint trên dark mode": KHÔNG xảy ra qua picker hiện tại
Preset tự flip hue theo `isDark` — chọn mono trên Night ra accent TRẮNG. Custom RGB đã bỏ
(`AppAccentColor.customRGB` chỉ còn để decode settings cũ, không apply). Theme editor/import
(`ThemeEditorView`, `ThemeFileDocument`) còn trong code nhưng KHÔNG reachable từ Settings
(grep 0 call site). Nếu ép black-on-Night: fill contrast = **1.0** (grouped) / 1.23 (elevated)
— đúng như user hình dung, nhưng đường vào đang bịt bằng curation.

### NHƯNG ma trận WCAG lộ 16 combo đang hở THẬT (accent-làm-TEXT)
Tính đủ 7 preset × 4 builtin theme (script trong report này, formula = RGBMath):

| Surface | Floor | Combo fail (tệ nhất) |
|---|---|---|
| Fill: accent vs grouped/elevated (WCAG 1.4.11, 3:1) | 3.0 | **0 fail** (min 3.51 — teal/dayClassic) |
| Text: accent trên `controlBackground` (compact tinted pill, `ThemedButtonStyles.swift:134`) | 4.5 | day/blue 4.27 · day/teal 3.51 · day/pink 3.99 · night/blue 4.35 · night/indigo 4.40 · nightTinted/blue 4.03 |
| Text: accent trên `accentSoft` (tinted button, `ThemedButtonStyles.swift:52`) | 4.5 | day/teal 3.08 · day/pink 3.26 · nightTinted/blue **3.05** · nightTinted/graphite 3.75 (12/28 combo fail) |
| `onAccent` trên accent (label button filled) | 3.0 (large/bold text) | 0 fail floor 3.0 (min night/blue 3.20 — đạt AA large-text, đúng convention iOS white-on-blue) |

Kết luận hiện trạng: **fill rank an toàn nhờ curation; text rank hở có hệ thống** — accent
hue được tune cho fill, đem nguyên hue đó làm text trên soft/control fill là rớt AA normal-text.

## Giải pháp đề xuất (B — runtime WCAG guard + tách token theo rank)

Đúng triết lý derived-tokens sẵn có (mọi theme builtin/custom đi qua một chỗ resolve):

1. **`RGBMath.ensureContrast(_ c, on bg, floor)`** (ColorHex.swift): nếu
   `contrastRatio(c, bg) < floor`, blend `c` về phía `onColor(bg)` (trắng ở dark, đen ở light)
   bằng binary search ~8 bước tới khi đạt floor. Pure, deterministic, off-main safe.
2. **Fill guard** trong `recolored(accent:)` + palette resolve:
   `accent = ensureContrast(accent, on: max-constraint(groupedBackground, elevatedBackground), floor: 3.0)`.
   → 7 preset hiện tại KHÔNG đổi pixel nào (đều ≥3.5); black-on-dark / white-on-light từ theme
   import hay custom accent tương lai tự được kéo về ngưỡng thấy được. Cover luôn khi bật lại
   wallpaper/custom theme engine.
3. **Token mới `accentText`** (AppTheme+Tokens, computed): accent đã ensure ≥4.5 trên
   `controlBackground` VÀ `accentSoft` (lấy constraint chặt hơn). Dùng cho: fg của
   `ThemedTintedButtonStyle`, compact tinted pill, link text accent (kiểu "View full report").
   → sửa đứt 16 combo hở; các combo đã pass giữ nguyên hue brand (guard chỉ dịch khi cần).
4. **`onAccent` giữ floor 3.0**: label button filled là headline semibold = large text theo
   WCAG; nâng 4.5 sẽ ép label đen trên dark-blue, phá convention iOS — không khuyến nghị.
5. **Matrix regression test** (`VaultifyTests`): assert đủ preset × builtin theme (+ 1 fixture
   custom theme cực đoan: accent đen nền đen) pass floors — palette retune sau này không thể
   lặng lẽ rớt chuẩn.

### Phương án so sánh
- **A. Curation-only (status quo):** đủ cho fill với 7 preset, nhưng đang hở text rank và
  không cover custom/import/tương lai. Không khuyến nghị đứng một mình.
- **B. Guard + accentText (đề xuất):** ~40 dòng core + đổi 2 button style + tests. Cover mọi
  case kể cả input cực đoan, không đổi hình hiện tại trừ chỗ đang sai chuẩn.
- **C. Tonal palette OKLCH/HCT (Material You style):** sinh thang tone 0-100 per hue, chọn
  tone theo surface — đẹp và tổng quát nhất nhưng thêm color-space math + retune toàn bộ;
  YAGNI khi B đạt cùng bảo đảm với chi phí nhỏ.

## Việc cần làm nếu duyệt B
1. `RGBMath.ensureContrast` + unit tests (KAT vài cặp màu).
2. Fill guard trong `recolored()`/palette resolve.
3. `accentText` token + rewire `ThemedTintedButtonStyle`, `ThemedCompactButtonStyle(.tinted)`,
   audit các chỗ text accent trên fill (grep `.accent` fg trên accentSoft/controlBackground).
4. Matrix regression test.
5. Verify mắt: tinted button 4 theme × 7 accent, light/dark.

## Unresolved questions
- `selection` (row highlight) và `switchOn` có cần guard riêng không? Switch track theo
  UISwitch chrome (exempt), selection là fill trang trí — đề xuất để ngoài scope, chỉ guard
  accent/accentText.
- Có muốn nâng onAccent lên 4.5 (AAA-lean) chấp nhận label đen trên dark-blue? Mặc định: không.
