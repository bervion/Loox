# Design DNA audit — Watchtower status rows padding + app-wide sweep

Trigger: user report — "Every password is strong and unique" row + "Check for known breaches"
card có khoảng trắng quá lớn, sai DNA (screenshot 260711 13:47, VI locale).

## Root cause (CONFIRMED, fixed)

`ThemedCard` / `.themedCard()` đã tự pad `Space.s4` (16pt) quanh content
(`Vaultify/DesignSystem/Components/ThemedComponents.swift:158`). Ba view trong
WatchtowerScreen pad thêm `Space.s4` thủ công TRƯỚC khi bọc card → padding đôi 32pt mỗi cạnh,
row một dòng cao gấp rưỡi chuẩn (CategoryRow chuẩn = `Metric.rowHeight` 56pt).

| Site | File:line (trước fix) | Fix |
| --- | --- | --- |
| `emptyVaultView` | WatchtowerScreen.swift:288 | bỏ `.padding(Space.s4)` |
| `allClearView` ("Every password is strong and unique") | WatchtowerScreen.swift:304 | bỏ `.padding(Space.s4)` |
| `hibpToggleSection` ("Check for known breaches") | WatchtowerScreen.swift:324 | bỏ `.padding(Space.s4)` |

DNA check fail: rule 4 (every space a token — 32pt không phải giá trị chủ đích) + protocol
câu 4 ("anything pinched/flared" — row flared).

## App-wide sweep — pattern tương tự

Grep toàn bộ `Vaultify/` + `VaultifyCore/`: mọi chỗ `.padding(...)` đứng ngay trước
`.themedCard(...)` hoặc content bên trong `ThemedCard { }`.

- Kết quả: **chỉ 3 site trên** dính padding đôi. `themedCard()` chỉ có 3 call-site trong
  Features, đều ở WatchtowerScreen.
- `ThemedCard(cornerRadius:padding: 0)` tại WatchtowerScreen.swift:194 ("To fix" list) dùng
  đúng (padding 0 vì row tự quản mật độ).
- Các feature khác (Profile, Sharing, Onboarding…) dùng `.padding(Space.s4)` +
  `.background(...)` trực tiếp, không qua `themedCard` → không đôi.

## Ghi chú phụ (minor, chưa sửa)

- `CountBadge` pad `.vertical, 3` (WatchtowerComponents.swift:121) và readout ring pad
  `.top, 2` — giá trị micro ngoài thang Space; dạng optical adjustment phổ biến toàn app,
  không coi là defect trừ khi chuẩn hoá đồng loạt.
- Screenshot cho thấy đỉnh gauge có thể lọt dưới floating header ở vị trí scroll nghỉ —
  chưa xác định được là do user đã scroll hay spacer thiếu; cần check trên máy
  (VaultHeaderScrollSpacer inset vs chiều cao ringSection).

## Việc đã làm cùng đợt (theo feedback mid-session)

- Số trên ring: `Font.vaultCode` → `.vaultType(.largeTitle)` (SF bold, giữ
  `.monospacedDigit()` cho odometer roll).
- Ramp màu gauge + bar lift +10% về trắng (token success tuned cho text, đậm trên band rộng).
- Strength bar đổi sang 2 capsule kiểu 1Password (fill success + track cùng hue 30% opacity,
  seam 3pt) — thay spectrum push-out cũ theo yêu cầu user 260711.

## Unresolved questions

1. Thang điểm hiển thị: giữ 0–100 hay nhân 10 tầng display (1P dùng /1000)? Ảnh hưởng Home
   ring + accessibility strings — chờ user chốt.
2. Green sau lift +10% có còn "đậm" không — cần nhìn trên máy; nếu còn, tăng lift hoặc đổi
   hue token success (quyết định brand).
3. Gauge-under-header ở scroll nghỉ (ghi chú phụ) — cần xác nhận device.
