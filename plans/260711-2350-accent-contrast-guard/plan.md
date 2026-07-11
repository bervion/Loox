# Controlled Contrast — accent semantic ranks + runtime WCAG guard

**Ngày:** 2026-07-11 · **Branch:** `feat/accent-contrast-guard` (stacked trên feat/vault-audit)
**Nguồn:** proposal UI/UX user duyệt 260711-2350 (LOCKED) + research report
`plans/reports/accent-contrast-research-260711-2332-tint-color-wcag-guard-report.md`

## Quyết định LOCKED (user proposal — KHÔNG tự đảo)

| # | Quyết định |
|---|-----------|
| L1 | "One accent, multiple semantic expressions": brand hue → accentFill / accentText / accentSoft / onAccent / accentPressed. Component không dùng raw accent cho text rank |
| L2 | Guard **non-destructive**: màu pass giữ nguyên byte; chỉ combo fail mới dịch (Rule 1) |
| L3 | Designer chọn brand hue gốc; engine tự derive per-role, không tay tạo biến thể per theme (Rule 2) |
| L4 | Điều chỉnh ưu tiên luminance, giữ hue/sat tương đối (Rule 3 — blend về onColor, KHÔNG đổi hue) |
| L5 | Accent ≠ status color: success/warning/danger giữ semantic độc lập (Rule 4) |
| L6 | onAccent floor GIỮ 3.0 (large/bold label); KHÔNG nâng 4.5 global — thay bằng rule component: text <15pt không đặt trực tiếp trên accentFill, badge nhỏ dùng accentSoft+accentText |
| L7 | Selection: NGOÀI scope patch đầu; rule = selection bg là decorative fill, content dùng primaryText/accentText; thêm selectionFill/Foreground CHỈ khi có use case active-nav |
| L8 | Switch: system chrome, không guard riêng; nếu custom switch sau này → vào cùng contract accentFill |
| L9 | Input cực đoan (black/black): điều chỉnh giữ neutral identity, KHÔNG reject/không đổi preset/không error. Copy: "Some colors may be adjusted automatically to keep controls and text readable" — không nhắc WCAG/số |
| L10 | Focus ring (macOS): dùng accentFill (hoặc accentFocus derive từ fill guard), KHÔNG accentText |
| L11 | Theme transition: resolve toàn snapshot rồi apply atomic, crossfade 180-250ms, không frame trung gian fail contrast |
| L12 | Picker preview theo ngữ cảnh 3 rank (fill + text + link), preview light/dark; không hiện số contrast cho user thường |

## Phases

| Phase | Nội dung | Status |
|-------|----------|--------|
| 1 | Core token correction: `RGBMath.ensureContrast`, guard accentFill trong `recolored()`, token `accentText` (+ ThemeRole case), rewire ThemedTinted/ThemedCompact(.tinted)/link accent, matrix regression tests | 🔨 đang làm |
| 2 | Component audit toàn codebase: grep mọi fg=accent / accent trên controlBackground/accentSoft/selection, phân loại theo rank rồi rewire (không replace mù) | ☐ |
| 3 | Theme picker preview 3-rank + light/dark preview + copy điều chỉnh (§5, §8 proposal) | ☐ |
| 4 | Advanced theme support khi bật lại custom/import: guard mặc định, preview original-vs-adjusted (dev mode) | ☐ (gated: WallpaperFeature) |

## Phase 1 — chi tiết

**Files:**
- `VaultifyCore/Theme/ColorHex.swift`: `RGBMath.ensureContrast(_:on:floor:)` — binary search
  blend về `onColor(bg)`, ~10 bước, clamp cuối; non-destructive khi đã pass.
- `VaultifyCore/Theme/AppTheme.swift` `recolored(accent:)`: fill guard ≥3.0 vs
  groupedBackground rồi elevatedBackground (switchOn/checkmark ăn theo accent đã guard).
- `VaultifyCore/Theme/AppTheme+Tokens.swift`: `var accentText` = ensure ≥4.5 trên
  controlBackground rồi accentSoft (cùng hướng blend nên tuần tự an toàn — có test 2 ràng buộc).
- `Vaultify/DesignSystem/Components/ThemedComponents.swift`: ThemeRole case `.accentText`.
- `ThemedButtonStyles.swift`: TintedButtonStyle fg → accentText; CompactButtonStyle
  `.tinted` fg → accentText.
- `VaultAuditFlowScreen.swift`: link "View full report" `.accent` → `.accentText`.
- Tests `AccentContrastGuardTests`: KAT ensureContrast; matrix 7 preset × 4 builtin
  (fill ≥3 vs grouped+elevated, accentText ≥4.5 vs control+soft, onAccent ≥3); fixture cực
  đoan black-accent-on-Night và white-accent-on-Day qua `recolored()`; non-destructive
  assert (preset pass → output == input).

**Acceptance (từ §13 proposal):** matrix pass; preset nhận ra đúng màu; tinted/compact/link
không chìm; mono không giống disabled; pressed phân biệt được.

## Câu hỏi mở
- Phase 3 preview đặt trong AppearanceView hiện tại hay screen riêng (đợi design).
- `accentFocus` token: chỉ khi làm macOS focus ring thật (Phase Mac).
