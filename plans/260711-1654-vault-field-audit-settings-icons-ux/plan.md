# Vault field-type audit + Home switcher affordance + Settings icon badges

Adversarial sweep (user request 260711): soi mọi FieldKind qua editor/detail/keyboard/icon,
tìm điểm UX sai DNA, kèm 2 ví dụ user chỉ: Home Space switcher text xám, Settings icon đơn sắc.

## Audit kết quả — từng FieldKind (evidence file:line)

| Kind | Editor | Detail | Keyboard | Verdict |
| --- | --- | --- | --- | --- |
| text | generic TextField | plain copy row | default | OK |
| username | generic | plain | default + no-autocap | OK |
| password | protected masked + generate chip | GlyphResolve + strength badge | default | OK |
| totp | protected + scan QR | live code + ring | default | OK |
| url | generic | scheme-grey/domain-accent + Open | .url | OK |
| email | generic | PRIVATE badge match | .emailAddress | OK |
| number | generic | plain | .numberPad | OK |
| multiline | axis .vertical / masked khi protected | multi-line copy | default | OK |
| monospace | generic protected + card overrides | vaultCode + card grouping | default | OK |
| date | DateFieldEditor round-trip | plain | — | OK |
| fileRef | AttachmentFieldRow (editor: meta row) | AttachmentFieldRow | — | OK |
| **phone** | **THIẾU KIND** — identity template dùng `.text` (ItemCategory.swift:74-75, comment thú nhận numberPad thiếu '+') | — | cần `.phonePad` | **GAP G1** |

Không phát hiện kind nào thiếu treatment editor/detail ngoài G1. Copy/reveal/large-type/
protect phủ đủ (DetailFieldRow.swift:194-228).

## Findings

- **G1 — thiếu `.phone` FieldKind**: phonePad có '+' '#' '*', đúng cho SĐT quốc tế.
  Kèm hardening: FieldKind decode unknown rawValue → fallback `.text` (vault sync tới
  bản app cũ không vỡ item khi gặp kind mới — hôm nay chưa có fallback, thêm case là
  rủi ro nếu không làm).
- **G2 — Home Space switcher sai affordance** (HomeScreen.swift:576-587): control tương
  tác render `.tertiary` y hệt section label tĩnh; Sort bên cạnh lại accent → user không
  biết switcher bấm được (đúng report). Fix: tên Space màu primary + chevron accent,
  count secondary — đọc là menu, không phải label (DNA #3 protocol "purpose obvious").
- **G3 — Settings icon đơn sắc** (SettingsScreen.swift ~24 Label): user muốn badge màu
  kiểu iOS Settings. Component mới `SettingsIconBadge` (29pt rounded-square continuous,
  tint đặc, icon Polaris trắng 16pt), palette cố định decorative (dynamic light/dark)
  gán theo ngữ nghĩa row (FaceID xanh lá, Auto-Lock indigo, Notifications đỏ, Erase đỏ…).
  Cập nhật exemption trong design-dna-standard (white-on-tint cho settings badge tiles).

## Adversarial checks đã chạy trên chính plan

- A1: thêm case enum String Codable → item cũ decode OK (rawValue cũ vẫn hợp lệ); item
  MỚI sync về app CŨ vỡ decode → fallback G1 chỉ cứu từ bản này trở đi; ghi chú release
  note nội bộ. Không migrate template item cũ (Phone .text cũ vẫn hoạt động).
- A2: exhaustive switches over FieldKind (iconAsset/defaultLabel/title + call sites
  QuickView/LooxLink/AutoFill) — compiler bắt; xử lý từng chỗ theo ngữ nghĩa (phone map
  như text ở share payloads).
- A3: Add Field menu = allCases.filter != fileRef → Phone tự xuất hiện; "Phone" đã có
  EN+VI trong xcstrings (stale → sẽ hết stale khi dùng).
- A4: Settings badge trắng-trên-tint = vi phạm semantic-only NẾU không ghi exemption →
  cập nhật doc cùng PR (giống tiền lệ quick-action).
- A5: G2 không đổi hit target (frame minHeight 44 giữ nguyên), chỉ đổi màu chữ/chevron.
- A6: macOS MacSettingsView dùng chung rows? — check khi triển; nếu Label tách riêng thì
  scope iOS trước.

## Phases

1. G1 `.phone` kind + decode fallback + template identity + tests decode fallback.
2. G2 Home switcher affordance (đổi màu, giữ layout/hit target).
3. G3 SettingsIconBadge + palette + áp vào SettingsScreen + DNA doc exemption.

Success: compile 2 target, full test pass, PR mở vào main.
