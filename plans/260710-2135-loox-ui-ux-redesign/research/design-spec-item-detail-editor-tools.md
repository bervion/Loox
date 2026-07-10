# Design Spec — Item Detail · Editor · Generator · 2FA · Shared Item · Tools · Private Email

Nguồn: mockup HTML `loox-design-unpacked/turns/t2.html` (Đợt 2), `t7.html` (Đợt 7), `t11.html` (Đợt 11).
Mục đích: spec ngữ nghĩa flow/IA/copy/state để dev SwiftUI implement — KHÔNG port pixel CSS. Mỗi màn nằm trong khối `data-screen-label`, option id = 2a…11c.

Quy ước chung của hệ design (rút từ cả 3 file):
- Nền màn: light gray (#F3F3F7). Card trắng bo tròn lớn (radius ~20), shadow rất nhẹ.
- Accent xanh #1544FD (primary), success xanh lá #1F9D5B, destructive đỏ #E5484D, warning cam #B87D0E/#E8590C, teal #0E9BA4 (device-link/handoff), tím #7451EB (passkey).
- Push screen (Item Detail, Watchtower, Trash): nút tròn 40pt glass (blur) — back trái, actions phải. KHÔNG nav bar đặc.
- Sheet (Editor, Generator, 2FA, Protect Field, Open on Computer, Recovery): grabber 36×5, header = nút X tròn xám trái + title giữa + nút primary phải (checkmark tròn xanh hoặc pill).
- Field label: caps 11.5px xám; value 16px. Field "active/nổi bật" có nền tint xanh nhạt (accent 4–8%) + label đổi màu accent.
- Password/mã/alias/recovery key: font mono; digits tô xanh accent, symbols tô đỏ — cả ở editor, generator, large type.
- Strength: 4 vạch segment + label (Strong/Excellent) màu xanh lá; hoặc chấm tròn + chữ "Strong" inline cạnh dấu chấm password.
- Tag: chip pill trắng, `#` màu accent + tên tag.
- Primary CTA cuối màn: pill full-width nền accent, shadow màu accent.
- Destructive action = card trắng riêng, text đỏ, căn giữa (Move to Trash / Leave Share / Empty).
- Footer metadata: text nhỏ xám nhạt căn giữa ("Created … · Modified …").

---

## 2a · Item Detail (login của mình) — `data-screen-label="Item Detail"`

**1. Mục đích + flow:** Màn xem chi tiết 1 login item do mình sở hữu. Từ list (Home/Search/Vault) push tới. Đi tiếp: Edit (nút …/menu hoặc share icon), passkey row → passkey detail, "Share this item" → share flow, shared-person row → quản lý share, Move to Trash → Recently Deleted.

**2. Layout trên xuống:**
1. Top bar glass: back (trái) · phải: nút share/export (mũi tên lên khỏi khay) + nút "…" (3 chấm).
2. Hàng vault-switcher: chip pill trắng `🔒 Personal ⌄` (vault hiện tại, có chevron đổi vault) — bên phải là **star** (favorite) đang FILL màu accent (item được favorite).
3. Identity header: icon monogram 56pt bo 16 ("G" nền xám) + title "GitHub" (23px bold) + subtitle "Login".
4. Hàng tag chips: `#work` `#dev`.
5. **Card fields chính** (1 card trắng, các row ngăn bằng hairline):
   - Row Username — đang ở state Copied: cả row nền tint accent 8%, label "USERNAME" đổi màu accent, bên phải checkmark + chữ "Copied" màu accent.
   - Row Password: value là bullet ẩn `••••…` + inline badge "● Strong" xanh lá; icon con mắt (reveal) bên phải.
   - Row One-time code: label "ONE-TIME CODE", value mono 18px "483 921", bên phải **countdown ring** tròn (track xám, progress accent, quay từ 12h).
   - Row Website: value "https://" xám nhạt + "github.com" màu accent (scheme de-emphasized, host là link).
   - Row Recovery email — **protected field**: value thay bằng `🔒 Protected — tap to reveal` (xám, icon khoá).
6. Section label caps "PASSKEYS" → card: row icon passkey (tím) + "minh.anh" + "Passkey · Created Mar 12, 2026" + chevron.
7. Section label "SHARED WITH" → card: row avatar gradient "T" + "Thu Trang" + badge pill xanh lá "Active" + chevron; row cuối "+ Share this item" (icon + tròn nền accent nhạt, text accent).
8. Card "Move to Trash" (đỏ, căn giữa).
9. Footer: "Created Jan 8, 2026 · Modified 2 days ago".

**3. Copy đáng chú ý (EN):** "Personal" · "Login" · "USERNAME/PASSWORD/ONE-TIME CODE/WEBSITE/RECOVERY EMAIL" · "Copied" · "Strong" · "Protected — tap to reveal" · "Passkeys" · "Passkey · Created Mar 12, 2026" · "Shared with" · "Active" · "Share this item" · "Move to Trash" · "Created Jan 8, 2026 · Modified 2 days ago".

**4. States/biến thể:**
- **Copied flash**: tap row copy → row highlight tint accent + label accent + "✓ Copied" thay cho affordance thường; tự trở về sau ~1–2s.
- Password ẩn mặc định, strength dot luôn hiện kể cả khi ẩn.
- TOTP ring đếm ngược liên tục (xem 2d cho state ≤5s cam).
- Protected field: không hiện value, tap → auth (xem 7b) rồi reveal.
- Favorite star fill = on / outline = off (so sánh 11a: outline).

**5. Tương tác:** tap row = copy (mặc định); tap eye = reveal password; tap protected row = auth-then-reveal; tap passkey row/share row → push; tap vault chip → switch/move vault; tap star → toggle favorite; tap host website → mở web.

**6. Ghi chú designer (VI, nguyên văn):** label option: "Item Detail — login của mình; row Username đang nháy “Copied”". Header đợt: "Đợt 2 — Item Detail · Editor · Generator · 2FA · Shared item (theo hệ đã chốt ở turn 1)". Footer đợt: "Tiếp theo: «làm Đợt 3: Onboarding + Lock Screen» · «xem Large Type của 2a» · «chỉnh sheet 2c»".

**7. Điểm mới:** (a) copy-first row (tap cả row để copy, feedback inline trên chính row — không toast); (b) per-field protection (Recovery email khoá riêng dù vault đã mở); (c) sharing per-item hiển thị ngay trong detail với trạng thái người nhận; (d) TOTP sống ngay trong detail với ring; (e) vault chip + favorite ở đầu màn thay vì trong menu.

---

## 2b · Item Editor (sheet) — `data-screen-label="Item Editor"`

**1. Mục đích + flow:** Sheet tạo/sửa login (mock đang là create mới "Shopee"). Mở từ nút + hoặc Edit từ 2a. X = hủy (kèm confirm discard nếu có draft), checkmark xanh = save. GenerateChip → mở Generator (2c). Chip "Create private email" → flow alias (đợt 11).

**2. Layout:**
1. Sheet full-height (top 58px), grabber; header: X (trái) · title "Login" (giữa) · nút save = check tròn nền accent (phải).
2. Vault chip `🔒 Personal ⌄` căn giữa dưới header.
3. Hàng title: icon monogram 52pt ("S" cam) + text field tên item "Shopee" — underline accent + caret (đang focus), style tựa title lớn chứ không phải ô input thường.
4. **Hàng suggestion chips ngang (scroll)** ngay dưới title — ngữ cảnh email/username:
   - Chip 1 (nổi bật, viền dashed accent, nền tint): icon ✉ + 2 dòng "Create private email" / "Unique for shopee.vn".
   - Chip 2 (trắng): "minh.anh@icloud.com" (email thật gợi ý điền nhanh).
5. Section "CREDENTIALS" → card: row Username (đã điền "minh.anh@icloud.com"); row Password đang focus — nền tint accent, label accent, value mono có màu digit/symbol + caret, icon eye phải, dưới value là **strength meter 4 vạch** (3 xanh + 1 nhạt).
6. **GenerateChip**: pill floating căn giữa NGAY DƯỚI card credentials (bám theo field password đang focus) — nền glass trắng blur, viền accent nhạt, icon sparkles + "Generate strong password" chữ accent.
7. Section "WEBSITES" → card: row "https:// shopee.vn"; row "＋ Add website" (accent) — multi-website.
8. Section "TAGS": chip `#shopping ×` (có nút xoá) + placeholder "Add tag…".
9. Card "Rotation reminder" — value phải "90 days ⌄" (picker).

**3. Copy:** "Login" · "Create private email" / "Unique for shopee.vn" · "minh.anh@icloud.com" · "CREDENTIALS" · "Username" · "Password" · "Generate strong password" · "WEBSITES" · "＋ Add website" · "TAGS" · "#shopping" · "Add tag…" · "Rotation reminder" / "90 days".

**4. States:** field focus = nền tint + label accent + caret; strength meter cập nhật live theo password; chip private-email là trạng thái "chưa tạo alias" (viền dashed = action tạo mới; so sánh 11b khi alias đã gắn); GenerateChip chỉ hiện khi password field focus/trống (chip "bám field").

**5. Tương tác:** tap chip email → điền vào field; tap "Create private email" → tạo alias theo domain của website; tap GenerateChip → mở Generator sheet với nút "Use"; tap eye toggle; tap ＋ Add website thêm row; tap × trên tag để xoá, tap "Add tag…" nhập; tap Rotation reminder → picker (off/15/30/90 ngày — khớp cadence hiện có của app); X → discard confirm; ✓ → save.

**6. Ghi chú designer:** "Editor (sheet) — login, private-email chips, GenerateChip bám field".

**7. Điểm mới:** (a) suggestion chips ngữ cảnh trên keyboard-area của editor (private email alias per-site + email thật) — pattern giống iCloud Hide My Email nhưng in-app; (b) GenerateChip nổi bám field thay vì nút trong field; (c) domain-aware alias suggestion ("Unique for shopee.vn" lấy từ field Websites); (d) title item là ô nhập kiểu heading, icon monogram tự sinh theo tên.

---

## 2c · Generator (sheet) — `data-screen-label="Generator"`

**1. Mục đích + flow:** Sheet generator mật khẩu. 2 ngữ cảnh: mở từ editor (có nút "Use" — trả kết quả về field) hoặc mở standalone từ Tools (không có Use, chỉ copy). Mock là bản mở-từ-editor.

**2. Layout:**
1. Sheet cao ~3/4 (top 150px); header: X · "Generator" · pill "✓ Use" (nền accent, phải).
2. **Segmented control** 3 tab: `Password` (active — nền trắng nổi) | `Passphrase` | `PIN`.
3. Card output: password mono 20px căn giữa, wrap, digits xanh/symbols đỏ: `kV7#pq2!Xw9$dCf4Rt@Zm6`; dưới là strength 4/4 vạch xanh + label "Excellent"; caption "Tap to copy".
4. Card Length: label "Length" + value mono accent "20"; slider (thumb tròn trắng, fill accent).
5. Card toggles (4 row switch):
   - "Uppercase (A–Z)" — ON
   - "Digits (0–9)" — ON
   - "Symbols (!#$)" — ON
   - "Avoid ambiguous (0/O, 1/l)" — OFF
6. Nút pill trắng căn giữa: icon refresh + "Regenerate" (chữ accent).

**3. Copy:** "Generator" · "Use" · "Password / Passphrase / PIN" · "Excellent" · "Tap to copy" · "Length" · "Uppercase (A–Z)" · "Digits (0–9)" · "Symbols (!#$)" · "Avoid ambiguous (0/O, 1/l)" · "Regenerate".

**4. States:** tab active nổi trắng; strength label đổi theo output (Excellent 4/4); toggles ON = accent, OFF = xám; đổi bất kỳ option nào → regenerate ngay (implied); mở standalone: header phải trống hoặc copy thay cho Use.

**5. Tương tác:** tap output = copy; kéo slider length; toggle options; Regenerate = sinh mới; Use = ghi vào password field của editor rồi đóng sheet; segmented đổi mode (Passphrase → options từ ngữ; PIN → độ dài số).

**6. Ghi chú designer:** "Generator (sheet) — output tô màu, options, Use khi mở từ editor".

**7. Điểm mới:** màu hoá ký tự output (đọc dễ, chống nhầm); "Avoid ambiguous" là option riêng; nút Use ngữ cảnh (chỉ khi mở từ editor).

---

## 2d · 2FA Codes (sheet) — `data-screen-label="2FA Codes"`

**1. Mục đích + flow:** Sheet danh sách TẤT CẢ mã TOTP đang có trong vault — dạng authenticator tổng. Mở từ Tools/Home quick action. Row → có thể push item detail.

**2. Layout:** sheet top 100px, grabber; header: X · "2FA Codes" (giữa, không có action phải). 1 card trắng chứa list row, mỗi row:
- Icon monogram 38pt màu theo brand (G xám GitHub, G đỏ Google, B vàng Binance, D xanh Dropbox, L teal LinkedIn).
- Cột giữa: tên service (15px semibold) + **username phụ** (12.5px xám, ellipsis) — để phân biệt nhiều tài khoản cùng service.
- Phải: mã TOTP mono 19px "483 921" (nhóm 3-3) + countdown ring 22pt.

Data mẫu: GitHub/minh.anh · GitHub/minh-anh-dev (work) · Google/minh.anh@gmail.com · Binance/minh.anh@icloud.com · Dropbox/minh.anh@icloud.com · LinkedIn/minh.anh@work.vn.

**3. Copy:** "2FA Codes"; mã "483 921", "771 265", "059 214", "728 430", "194 552", "640 187".

**4. States:** **≤5s còn lại → mã VÀ ring chuyển màu cam** (#E8590C, row Google trong mock, dashoffset lớn = sắp hết); bình thường mã đen + ring accent. Mỗi row có chu kỳ độc lập.

**5. Tương tác:** tap row = copy mã (theo pattern copy-first); ring tự đếm; 2 tài khoản GitHub minh hoạ cần subtitle username.

**6. Ghi chú designer:** "2FA Codes (sheet) — row: icon + username phân biệt tài khoản, vòng cam khi ≤5s".

**7. Điểm mới:** password manager kiêm authenticator tổng (màn riêng gom mọi TOTP), cảnh báo sắp hết hạn bằng đổi màu cam cả mã lẫn ring thay vì chỉ ring.

---

## 2e · Shared Item Detail (item nhận chia sẻ) — `data-screen-label="Shared item detail"`

**1. Mục đích + flow:** Detail của item NGƯỜI KHÁC chia sẻ cho mình — read-only. Từ list "Shared with Me" push tới. Ánh xạ trực tiếp Approval Mode sharing hiện có (recipient side): TOTP không được giao key → phải "Request Code" chờ owner approve, kèm match code chống MITM; safety code xác thực share.

**2. Layout:**
1. Top bar glass: back + "…" (KHÔNG có share/export — read-only).
2. Chip trạng thái thay vault chip: pill nền xanh-lá nhạt, icon người-check, "Shared with Me" (không có star favorite).
3. Identity header: monogram "V" xanh lá + "VPBank Family" + subtitle "Login · from Thu Trang" (ghi rõ người share).
4. **Banner info** (nền accent 7%, icon shield): "Shared with you — you can use what's listed here, but not edit it."
5. Card fields:
   - Row Username: "trang.nguyen88" (copy được).
   - Row Password: bullets + eye (dùng được, không sửa).
   - **Row One-time code · ask owner** (nền tint accent 4%) — state pending:
     - Spinner + "Waiting for the owner…" / caption "Ask them to check their Loox app."
     - Sub-card trắng: "Match code" + mã mono accent lớn "51 342".
     - Caption: "Must match the code on the owner's screen".
6. Section "SAFETY CODE" → card: mã mono lớn căn giữa "7H2K-9QLM-X3RD" + caption "Compare with the code on the owner's device to confirm this share is authentic."
7. Card destructive "Leave Share" (đỏ).
8. Footer: "Shared Jun 2, 2026 · Verified just now".

**3. Copy:** "Shared with Me" · "Login · from Thu Trang" · "Shared with you — you can use what's listed here, but not edit it." · "ONE-TIME CODE · ASK OWNER" · "Waiting for the owner…" · "Ask them to check their Loox app." · "Match code" · "51 342" · "Must match the code on the owner's screen" · "Safety code" · "7H2K-9QLM-X3RD" · "Compare with the code on the owner's device to confirm this share is authentic." · "Leave Share" · "Shared Jun 2, 2026 · Verified just now".

**4. States:** TOTP row có 3 state ngầm: idle ("Request code" — không hiển thị trong mock), **pending (mock: spinner + match code)**, delivered (hiện mã + ring như 2a). "Verified just now" ở footer = safety code đã đối chiếu.

**5. Tương tác:** tap username = copy; eye reveal password; request code → chuyển pending, hiện match code; Leave Share → confirm rời.

**6. Ghi chú designer:** "Item nhận chia sẻ — read-only, Request Code đang chờ, safety code".

**7. Điểm mới:** (a) askEachTime TOTP — người nhận phải xin owner từng lần, có **match code 5 số** 2 phía đối chiếu (chống kẻ giả mạo request); (b) **safety code** cố định của share (fingerprint) hiển thị ngay trong detail; (c) copy hướng dẫn "check their Loox app" — không cần kênh ngoài; (d) header đổi ngữ nghĩa hoàn toàn theo vai (badge Shared with Me thay vault chip).

---

## 7a · Large Type — `data-screen-label="Large Type"`

**1. Mục đích + flow:** Hiển thị password thật to, từng ký tự đánh số, để đọc-gõ-tay sang thiết bị khác. Mở từ Item Detail (menu … hoặc long-press row password). Full screen (không phải sheet trong mock nhưng ngữ nghĩa modal).

**2. Layout:**
1. Header: X (trái) · giữa 2 dòng "GitHub" / "Password · large type".
2. Nội dung giữa màn: **grid 4 cột** ô ký tự — mỗi ô card trắng bo 14: ký tự mono 28px (digit xanh accent, symbol đỏ, chữ đen) + số thứ tự nhỏ bên dưới (1,2,3…).
3. Ô states: **đã gõ (done) = mờ opacity .45, số xám**; **ô hiện tại = viền accent 2px, số đổi màu accent** (mock: ô 4 "#"); chưa tới = bình thường.
4. Caption: "Tap a tile to mark it as typed · dimmed = done".
5. CTA đáy: pill accent full-width "Copy" (icon copy).

**3. Copy:** "GitHub" · "Password · large type" · "Tap a tile to mark it as typed · dimmed = done" · "Copy".

**4. States:** per-tile: normal / current (ring accent) / done (dimmed). Tiến trình do user tự tap đánh dấu.

**5. Tương tác:** tap ô = toggle đã-gõ (dim); Copy = copy cả password; X đóng.

**6. Ghi chú designer:** "Large Type — ô ký tự đánh số, tap để đánh dấu đã nhập". Header đợt: "Đợt 7 — Large Type · Protect Field · Open on Computer · Watchtower detail · Trash · Recovery". Footer đợt: "Feature map đã phủ gần trọn. Tiếp được: «bản Night toàn bộ» · «Name/Theme/Done onboarding» · «Personas editor + Space editor» · «export PNG để đưa vào Figma»."

**7. Điểm mới:** large type có **checklist tương tác** (tap từng ô đánh dấu đã gõ) — hơn hẳn large-type tĩnh của 1Password; đánh số + tô màu digit/symbol giảm lỗi chép tay.

---

## 7b · Protect Field (sheet) — `data-screen-label="Protect Field"`

**1. Mục đích + flow:** Sheet cấu hình khoá 1 field riêng lẻ (mock: field "Recovery email" — chính là field "Protected — tap to reveal" ở 2a). Mở từ editor/detail context menu của field. Kết quả: field chỉ reveal sau khi nhập mật khẩu bảo vệ phụ.

**2. Layout:** sheet thấp (top 250px):
1. Grabber; header: X · title `Protect “Recovery email”` (tên field nội suy).
2. **Segmented 2 tab**: `Extra Password` (active) | `Custom code` — dùng mật khẩu bảo vệ chung của app, hoặc mã riêng chỉ cho field này.
3. Card giải thích (icon khoá accent): "This field will only reveal after you enter your **Extra Protection password** — even when the vault is unlocked."
4. **Warning card** (nền vàng nhạt, icon tam giác): "If you forget it, this field can't be recovered. There is no reset."
5. CTA đáy: pill accent "Protect Field".

**3. Copy:** `Protect “Recovery email”` · "Extra Password" / "Custom code" · "This field will only reveal after you enter your Extra Protection password — even when the vault is unlocked." · "If you forget it, this field can't be recovered. There is no reset." · "Protect Field".

**4. States:** tab Extra Password (mock) vs Custom code (sẽ cần thêm ô nhập + confirm mã — không có trong mock, dev tự suy).

**5. Tương tác:** chọn tab; Protect Field → field chuyển sang state protected (2a row "Protected — tap to reveal"); reveal sau đó yêu cầu nhập đúng mật khẩu/mã.

**6. Ghi chú designer:** "Protect Field — khoá field bằng Extra Password hoặc mã riêng".

**7. Điểm mới:** bảo vệ **per-field** với 2 chế độ (mật khẩu phụ toàn app tái dùng vs mã riêng từng field), cảnh báo no-reset rõ ràng — vượt mô hình lock toàn vault thông thường.

---

## 7c · Open on Computer (sheet) — `data-screen-label="Open on Computer"`

**1. Mục đích + flow:** Approve yêu cầu browser-handoff (Quick View "Open on Computer" — khớp plan QV hiện có): browser xin xem field của item "GitHub". Mở khi app nhận request (sau khi user quét/nhập trên máy tính). Kết thúc: Approve with Face ID → gửi field đã chọn; hoặc "They don't match" → hủy.

**2. Layout:** sheet top 120px:
1. Grabber. KHÔNG có header X/title — mở đầu bằng hero.
2. Hero: icon globe tròn teal 64pt + heading `A browser wants to view fields from “GitHub”`.
3. **Card Safety phrase**: label caps "SAFETY PHRASE" · phrase mono teal đậm 21px "brave-lemon-cloud" (SAS 3 từ) · caption "Make sure this matches the phrase on your computer." · badge pill vàng đồng-hồ "Expires in 42 seconds" (countdown TTL).
4. **Card chọn field** (toggle từng field sẽ gửi):
   - "Username" — ON
   - "Password" — ON, kèm sub-warning cam: "Password will be visible on this computer."
   - "Current 2FA code" — OFF.
5. Đáy: CTA pill accent icon Face ID "Approve with Face ID"; dưới là text button đỏ "They don't match" (thay thế cancel — KHÔNG có lối "continue anyway").

**3. Copy:** `A browser wants to view fields from “GitHub”` · "Safety phrase" · "brave-lemon-cloud" · "Make sure this matches the phrase on your computer." · "Expires in 42 seconds" · "Username" · "Password" · "Password will be visible on this computer." · "Current 2FA code" · "Approve with Face ID" · "They don't match".

**4. States:** countdown TTL badge (42s, đếm lùi → hết hạn tự hủy); toggle từng field; SAS phrase phải trùng 2 đầu.

**5. Tương tác:** đối chiếu phrase bằng mắt; bật/tắt field-scope; Approve = Face ID rồi gửi; "They don't match" = hủy ngay (đường thoát duy nhất — thiết kế cưỡng bức so-khớp, không cho bỏ qua).

**6. Ghi chú designer:** "Open on Computer — SAS phrase, chọn field, không có “continue anyway”".

**7. Điểm mới:** (a) SAS dạng cụm-3-từ dễ đọc thay số; (b) field-scoped consent (chọn đúng field gửi, 2FA mặc định OFF); (c) TTL hiển thị ngay; (d) nút hủy đặt tên theo hành vi xác minh ("They don't match") — anti-phishing UX; (e) cảnh báo hệ quả per-field ("Password will be visible on this computer").

---

## 7d · Watchtower — Compromised — `data-screen-label="Watchtower — Compromised"`

**1. Mục đích + flow:** Màn chi tiết 1 danh mục audit (Compromised) từ Watchtower tổng. Push từ Watchtower. Row "Change" → item/flow đổi password.

**2. Layout:**
1. Top bar glass: chỉ back.
2. Header: icon shield-! đỏ trong tile 44pt + title "Compromised" (24px) + subtitle "2 passwords appeared in known breaches".
3. Card list item bị lộ, mỗi row: monogram + tên ("Dropbox", "Forum cũ (voz)") + dòng đỏ "Seen 3 times in breaches" / "Seen 11 times in breaches" + nút pill accent nhạt "Change".
4. **Banner info** (accent 7%, icon ⓘ): "Checked with k-anonymity — only a partial hash left this device. Change these passwords, then re-run the audit."

**3. Copy:** "Compromised" · "2 passwords appeared in known breaches" · "Seen N times in breaches" · "Change" · "Checked with k-anonymity — only a partial hash left this device. Change these passwords, then re-run the audit."

**4. States:** mức nghiêm trọng thể hiện qua số lần lộ (đỏ); sau khi đổi password item nên rời list (re-run audit).

**5. Tương tác:** tap Change → mở item editor/website đổi mật khẩu; tap row → item detail; banner giải thích privacy.

**6. Ghi chú designer:** "Watchtower — danh mục Compromised, số lần lộ breach".

**7. Điểm mới:** hiển thị **số lần xuất hiện trong breach** per-item; tuyên bố k-anonymity in-context (củng cố định vị offline/zero-backend của app); CTA "Change" ngay trên row.

---

## 7e · Recently Deleted — `data-screen-label="Recently Deleted"`

**1. Mục đích + flow:** Trash 30 ngày. Push từ Settings/Vault. Row swipe → Restore hoặc Delete vĩnh viễn; "Empty" xoá tất cả.

**2. Layout:**
1. Top bar: back (trái) + text button đỏ "Empty" (phải).
2. Large title "Recently Deleted" (31px) + caption xám "Items in Trash are still encrypted. Deleting them is permanent."
3. Card list: mỗi row monogram xám + tên ("Tumblr", "MySpace") + subtitle "Deleted 3 days ago · gone in 27 days" / "Deleted 12 days ago · gone in 18 days".
4. Row 2 minh hoạ **swipe-open**: lộ 2 action phải — "Restore" (nền xanh lá) và "Delete" (nền đỏ), mỗi ô 66px.
5. Hint cuối: "Swipe a row for Restore / Delete permanently".

**3. Copy:** "Empty" · "Recently Deleted" · "Items in Trash are still encrypted. Deleting them is permanent." · "Deleted N days ago · gone in M days" · "Restore" · "Delete" · "Swipe a row for Restore / Delete permanently".

**4. States:** countdown tự hết hạn per-item ("gone in X days"); row swiped state.

**5. Tương tác:** swipe trái mở 2 action; Empty (confirm) xoá toàn bộ; tap row → xem read-only (implied).

**6. Ghi chú designer:** "Recently Deleted — swipe Restore/Delete, nút Empty".

**7. Điểm mới:** subtitle gộp cả "deleted ago" lẫn "gone in" (đếm ngược trực quan); nhấn mạnh "still encrypted" — copy trấn an đúng threat model.

---

## 7f · Recovery — `data-screen-label="Recovery"`

**1. Mục đích + flow:** Khôi phục vault bằng recovery key từ Emergency Kit + đặt Master Password mới. Mở từ Lock Screen ("quên mật khẩu"). Khớp flow Emergency Kit PDF hiện có (key + QR scan-to-recover).

**2. Layout:** sheet top 100px:
1. Grabber; header: X · "Recover your vault".
2. Intro: "Enter the recovery key from your Emergency Kit, then set a new Master Password."
3. Section "RECOVERY KEY" → card input: key mono "HXK4-9PLM-22QD-7V" + caret; bên phải nút "Scan" (icon camera, accent) — quét QR từ Emergency Kit.
4. Section "NEW MASTER PASSWORD" → card: ô secure (bullets) + eye; dưới là strength 4 vạch (3 xanh) + "Strong".
5. Card confirm password: bullets + **checkmark xanh lá** (đã khớp).
6. CTA đáy: pill accent "Recover Vault".

**3. Copy:** "Recover your vault" · "Enter the recovery key from your Emergency Kit, then set a new Master Password." · "RECOVERY KEY" · "Scan" · "NEW MASTER PASSWORD" · "Strong" · "Recover Vault".

**4. States:** strength live; confirm match = checkmark xanh (mismatch cần state lỗi — dev tự suy); key nhập tay hoặc scan.

**5. Tương tác:** nhập/scan key; nhập password mới ×2; Recover Vault thực thi.

**6. Ghi chú designer:** "Recovery — nhập recovery key + đặt mật khẩu mới".

**7. Điểm mới:** không mới về flow (đã có trong app) — giá trị là chuẩn hoá UI: key mono formatted, nút Scan inline trong input, strength + match-check trực quan, một màn duy nhất.

---

## 11a · Item Detail — Private Email — `data-screen-label="Item Detail — private email"`

> **Quy ước nhận diện alias (designer, nguyên văn):** "field email dùng alias luôn có ① badge PRIVATE cạnh label, ② alias hiển thị font mono (đúng hệ alias toàn app), ③ dòng phụ “↳ forwards to {mail gốc}” + chấm xanh verified. Tap-to-copy luôn copy *alias*, không copy mail gốc."

**1. Mục đích + flow:** Item Detail (Shopee) khi field Email dùng private-email alias — user thấy ngay alias ↔ mail gốc và trạng thái forwarding. "Manage alias" → màn quản lý Private Email.

**2. Layout:** như 2a (top bar glass 3 nút, vault chip Personal, star — ở đây OUTLINE = chưa favorite, identity "Shopee / Login") nhưng card fields khác:
1. **Row Email (private) — nền tint accent 5%**:
   - Hàng label: "EMAIL" + **badge pill "🛡 PRIVATE"** (nền accent 10%, chữ accent 10px caps).
   - Value: alias **mono** "shopee.9fk2@loox.email" + icon copy phải.
   - Hàng phụ: label caps nhỏ "FORWARDS TO" + "minhanh.nguyen.2026@gmail.com" + chấm xanh + "Active".
2. Row Password (bullets + Strong dot + eye).
3. Row Website (https:// + shopee.vn accent).
4. **Banner info** (icon ✉): "Shopee only ever sees the alias. Copy always copies the alias — your real address stays private. **Manage alias**" (Manage alias là link accent inline).
5. Move to Trash + footer "Created May 4, 2026 · Modified today".

**3. Copy:** "EMAIL" · "PRIVATE" · "shopee.9fk2@loox.email" · "FORWARDS TO" · "Active" · "Shopee only ever sees the alias. Copy always copies the alias — your real address stays private." · "Manage alias" · "Move to Trash".

**4. States:** alias Active (chấm xanh); designer gợi case "alias đang paused" chưa vẽ (footer đợt 11: "Muốn mình áp badge PRIVATE này vào cả 2a/2b hiện có, hay xem thêm case «alias đang paused» trong detail?") — dev cần dự phòng state Paused (chấm xám/vàng).

**5. Tương tác:** tap row Email = **copy ALIAS** (không bao giờ copy mail gốc); tap Manage alias → Private Email management; các row khác như 2a.

**6. Ghi chú designer:** label: "Item Detail — login dùng Private Email, thấy ngay alias ↔ mail gốc". Header đợt: "Đợt 11 — Private Email trong item: nhận diện alias + mail gốc ở Detail · Editor · AutoFill". + đoạn quy ước nhận diện trích ở trên.

**7. Điểm mới:** hệ nhận diện alias 3 dấu hiệu nhất quán toàn app (badge PRIVATE + mono + forwards-to line); nguyên tắc copy-luôn-copy-alias; minh bạch mail gốc + trạng thái forward ngay trong item.

---

## 11b · Editor — Private Email — `data-screen-label="Editor — private email"`

**1. Mục đích + flow:** Editor login khi alias ĐÃ GẮN vào field Email; cho phép gỡ alias / đổi lại mail thật 1 chạm. Từ 2a/11a bấm Edit.

**2. Layout:** sheet editor như 2b (X · "Login" · ✓ save; identity Shopee) khác biệt:
1. Card CREDENTIALS — **row Email alias-attached** (nền tint, badge PRIVATE, alias mono): bên phải value là **nút × tròn xám nhỏ** (detach alias khỏi field); dưới là hàng "FORWARDS TO … ● Active" như 11a.
2. Row Password bullets.
3. **Hàng chips dưới card**: chip trắng icon người "Use real email instead" (swap 1 chạm) + chip "Manage alias…" (chữ accent).
4. Section WEBSITES: card 1 row "https:// shopee.vn".
5. **Banner info** (icon ⓘ): "Switching to your real email keeps the alias alive — pause or delete it in Private Email."

**3. Copy:** "Login" · "EMAIL" · "PRIVATE" · "FORWARDS TO" · "Active" · "Use real email instead" · "Manage alias…" · "Switching to your real email keeps the alias alive — pause or delete it in Private Email."

**4. States:** alias attached (mock) vs chưa attach (2b: chip "Create private email" dashed). Nút × = detach; sau detach field trở về ô email thường + chips quay lại bộ 2b.

**5. Tương tác:** tap × trên alias → gỡ alias khỏi field (alias KHÔNG bị xoá); "Use real email instead" → thay value = mail thật ngay; "Manage alias…" → màn Private Email (pause/delete alias tại đó, không tại editor).

**6. Ghi chú designer:** "Editor — alias đang gắn vào field, đổi lại mail thật 1 chạm".

**7. Điểm mới:** tách bạch vòng đời alias khỏi item ("keeps the alias alive") — editor chỉ attach/detach, quản trị alias ở module riêng; swap alias↔real 1 chạm.

---

## 11c · AutoFill — Private Email — `data-screen-label="AutoFill — private email"`

**1. Mục đích + flow:** AutoFill extension sheet (nền app ngoài blur phía sau) khi app/web là Shopee: nhận diện login dùng alias trong list, và tạo login mới kèm alias mới ngay từ AutoFill (flow đăng ký).

**2. Layout:** sheet AutoFill top 300px:
1. Grabber; header: "Cancel" (accent, trái) + logo Loox giữa.
2. Section "FOR THIS APP" → card:
   - **Row Shopee**: monogram S cam + hàng tên "Shopee" kèm **badge PRIVATE mini**; dòng 2 = alias mono "shopee.9fk2@loox.email"; dòng 3 = icon ✉→ + mail gốc xám "minhanh.nguyen.2026@gmail.com"; chevron phải.
   - **Row "Create new login"** (accent): subtitle "with a fresh private email for this app" — tạo login + alias mới 1 phát khi đăng ký.
3. Section "OTHER LOGINS" → card: row GitHub / "minh.anh" (login thường, không badge).
4. Hint cuối: "Long-press a login to fill with its private email."

**3. Copy:** "Cancel" · "FOR THIS APP" · "Shopee" · "PRIVATE" · "shopee.9fk2@loox.email" · "minhanh.nguyen.2026@gmail.com" · "Create new login" / "with a fresh private email for this app" · "OTHER LOGINS" · "GitHub" / "minh.anh" · "Long-press a login to fill with its private email."

**4. States:** row có alias = badge + 3 dòng (tên/alias mono/mail gốc); row thường = 2 dòng; matched-app section tách khỏi "Other logins".

**5. Tương tác:** tap row = fill (điền alias làm username); tap Create new login → sinh alias mới cho app này + generator password (implied) rồi fill; **long-press row = fill bằng private email của login đó** (kể cả khi field đang xin email); Cancel đóng.

**6. Ghi chú designer:** "AutoFill — nhận diện alias ngay trong list + tạo alias khi đăng ký mới". Footer đợt 11: "Muốn mình áp badge PRIVATE này vào cả 2a/2b hiện có, hay xem thêm case «alias đang paused» trong detail?"

**7. Điểm mới:** (a) alias hiển thị đầy đủ 3 tầng ngay trong AutoFill row (biết mình sắp điền alias nào, forward về đâu); (b) "Create new login with a fresh private email" ngay trong extension = one-tap signup privacy; (c) long-press như secondary fill action.

---

## Tổng hợp cho dev SwiftUI (cross-cutting)

1. **Copy-first row pattern**: mọi field row tap = copy, feedback inline trên row (tint + "✓ Copied"), không toast — cần component `CopyableFieldRow` dùng chung Detail/2FA/Shared.
2. **Field row states**: normal / copied-flash / focused (editor, tint+caret) / protected (locked placeholder) / private-email (badge+mono+forwards-line) / pending-request (shared TOTP).
3. **TOTP ring component** dùng chung 2a + 2d + (2e delivered), có state cam ≤5s (đổi cả màu mã).
4. **Ký tự tô màu** (digit accent / symbol đỏ / chữ thường): dùng ở editor password, generator output, large type, alias không cần — cần 1 `ColorizedSecretText` helper.
5. **Sheet chrome chuẩn**: grabber + X tròn xám + title giữa + primary phải (check tròn hoặc pill) — mọi sheet (Editor/Generator/2FA/Protect/Recovery).
6. **Push chrome chuẩn**: nút glass tròn 40pt, không nav bar — Detail/Watchtower/Trash.
7. **Banner info/warning**: card tint accent 7% (info, icon shield/ⓘ/✉) và tint vàng (warning) — dùng ở 2e, 7b, 7d, 11a, 11b.
8. Mọi string trên đây là EN source — cần thêm VI vào `Localizable.xcstrings` khi implement (convention repo).

## Unresolved questions
- State "alias paused" trong Detail/AutoFill chưa được vẽ (designer chủ động hỏi) — cần quyết visual (chấm vàng "Paused"?).
- Protect Field tab "Custom code": UI nhập mã chưa vẽ.
- Shared TOTP state "idle" (nút Request Code trước khi pending) không có mock — chỉ có state pending.
- Generator tab Passphrase/PIN: options cụ thể chưa vẽ.
- Nút share/export (mũi tên lên) trên Detail: chưa rõ mở share-flow hay export item — mockup không đi tiếp.
