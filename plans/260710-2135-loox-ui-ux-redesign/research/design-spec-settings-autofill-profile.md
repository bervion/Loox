# Design Spec — Đợt 5 & 6: Settings, AutoFill extension, Profile/Private Email, Pair Device

Nguồn: mockup HTML `loox-design-unpacked/turns/t5.html` + `t6.html` (web mockup tham khảo FLOW, không port pixel CSS).
Mục tiêu: spec đủ chi tiết để dev SwiftUI hoàn thiện flow/copy mà không cần mở lại HTML.

Quy ước chung của mockup (áp cho mọi màn Đợt 5):
- Settings và các màn con đều là **sheet** (nền dimmed phía sau, card bo góc trên 28px, có grabber pill).
- Header sheet: grabber → title căn giữa bold → nút phải "Done" (root Settings) hoặc nút back tròn trái (màn con). Màn con KHÔNG có "Done".
- Section: label uppercase nhỏ (13px, gray) + card trắng bo 20px chứa các row, separator hairline giữa rows.
- Row chuẩn: icon 30×30 trong ô bo 8px nền tint nhạt (mỗi row 1 màu tint riêng: blue/teal/purple/amber) + label 15px + phải là toggle / value+chevron-down (inline picker) / chevron-right (push) / value tĩnh.
- Action row: text-only, màu accent (blue #1544FD) cho action thường, đỏ #E5484D cho destructive.
- CTA đáy màn: nút pill full-width màu accent (hoặc đỏ nếu nguy hiểm), có soft shadow màu theo nút.
- Footnote giải thích: text 12px gray nhạt đặt NGAY DƯỚI card liên quan.

---

## 5a · Settings (sheet) — nửa trên: Security / AutoFill / Online features / Privacy

**1. Mục đích + vị trí flow:** Root Settings, mở dạng sheet từ Home/Profile. Điểm vào của mọi màn con (Appearance, iCloud Sync, Import, Export…). Nút "Done" đóng sheet.

**2. Layout trên→xuống:**
- Grabber; header: title "Settings" giữa, "Done" (bold, accent) bên phải, trái để trống.
- Section **"Security"** — card 6 rows:
  1. "Unlock with Face ID" — icon Face ID (blue tint) + toggle ON (accent).
  2. "Auto-Lock" — icon đồng hồ (teal tint) + value "5 minutes" + chevron-down (inline picker/menu, không push).
  3. "Shake to lock" — icon (purple tint) + toggle OFF.
  4. "Change Master Password" — không icon, chevron-right (push).
  5. "Emergency Kit" — không icon, chevron-right.
  6. "Extra Protection" — value "Set" (gray) + chevron-right.
- Section **"AutoFill"** — card 2 action rows (text accent, semibold, không icon):
  1. "Set up password AutoFill"
  2. "Set up verification codes"
- Section **"Online features"** — card 2 rows, mỗi row 2 dòng (title + status line nhỏ) + toggle:
  1. "Private Email" / status xanh lá "Available" — toggle ON.
  2. "Share Links" / status vàng cam "Maintenance — back soon" — toggle ON.
- Section **"Privacy"** — card 2 rows:
  1. "Hide contents in App Switcher" — toggle ON.
  2. "Clear clipboard" — value "30 seconds" + chevron-down.

**3. Copy đáng chú ý (EN):** "Unlock with Face ID", "Auto-Lock · 5 minutes", "Shake to lock", "Change Master Password", "Emergency Kit", "Extra Protection · Set", "Set up password AutoFill", "Set up verification codes", "Private Email · Available", "Share Links · Maintenance — back soon", "Hide contents in App Switcher", "Clear clipboard · 30 seconds", "Done".

**4. Trạng thái/biến thể:**
- Online features có **status line theo dịch vụ**: xanh "Available" vs vàng "Maintenance — back soon" — toggle vẫn giữ nguyên trạng thái user, status chỉ phản ánh server health.
- "Extra Protection" value "Set" gợi ý trạng thái chưa thiết lập (call-to-action dạng value).
- Row Security có icon; row action thuần (Change Master Password, Emergency Kit) không icon — phân cấp visual: row có icon = setting thường trực, row không icon = action/push.

**5. Tương tác:** Toggle in-place; value+chevron-down = picker inline (menu); chevron-right = push child screen trong sheet; "Done" đóng sheet; AutoFill rows mở system settings/hướng dẫn.

**6. Ghi chú tiếng Việt của designer:** label option: "Settings (sheet) — Security / AutoFill / Online Features (cuộn tiếp)".

**7. Flow insight:**
- Settings là sheet chứ không phải tab/push — thoát nhanh bằng Done/swipe.
- Online features gom các tính năng cần mạng vào 1 section riêng, có health status per-feature ngay trong Settings (transparency cho app "offline-first").
- Thứ tự ưu tiên: Security đứng đầu (đúng bản chất app), AutoFill ngay sau.

---

## 5g · Settings — nửa dưới: Vault & data / Look & feel / About / danger zone

**1. Mục đích + vị trí flow:** Phần cuộn tiếp của cùng sheet Settings (5a). Chứa data management, appearance, about và danger zone.

**2. Layout trên→xuống:**
- Header giống 5a ("Settings" + "Done").
- Section **"Vault & data"** — card 3 rows (đều có icon):
  1. "iCloud Sync" — icon cloud (blue) + value "On" (gray) + chevron-right → màn 5c.
  2. "Import" — icon mũi tên xuống vào khay (teal) + chevron-right → màn 5d.
  3. "Export" — icon mũi tên lên khỏi khay (teal) + chevron-right → màn 5e.
- Section **"Look & feel"** — card 2 rows:
  1. "Appearance" — icon nửa tối nửa sáng (purple) + value "Day · Loox Blue" + chevron-right → màn 5b.
  2. "Language" — icon dịch chữ (amber) + value "Tiếng Việt" + chevron-right.
- Section **"About"** — card 2 rows (không icon):
  1. "About Loox" — value "v2.4.1" + chevron-right.
  2. "Help & feedback" — chevron-right.
- **Danger zone** — card cuối KHÔNG có section label:
  1. "Lock Now" — action accent blue.
  2. "Erase Vault…" — action đỏ (ellipsis báo hiệu có confirm) → dialog 5f.

**3. Copy:** "Vault & data", "iCloud Sync · On", "Import", "Export", "Look & feel", "Appearance · Day · Loox Blue", "Language · Tiếng Việt", "About", "About Loox · v2.4.1", "Help & feedback", "Lock Now", "Erase Vault…".

**4. Trạng thái/biến thể:** Value của Appearance là composite "Day · Loox Blue" (theme mode + accent name) — hiển thị cả 2 lựa chọn ngay tại row. iCloud Sync hiển thị "On/Off" summary.

**5. Tương tác:** Tất cả chevron-right = push màn con; "Lock Now" khóa vault ngay lập tức (đóng sheet + về lock screen); "Erase Vault…" mở dialog xác nhận.

**6. Ghi chú designer:** "Settings — cuộn tiếp: Vault & Data · Appearance · About · danger zone".

**7. Flow insight:** Danger zone tách card riêng, không header, đặt cuối cùng; "Lock Now" (an toàn, dùng thường) ghép cùng card với "Erase Vault…" (destructive) — cùng nhóm "hành động tức thời với vault". Ellipsis trên "Erase Vault…" là tín hiệu chuẩn iOS cho "sẽ hỏi thêm".

---

## 5b · Appearance — Day/Night preview + 7 accent, apply tức thì

**1. Mục đích + vị trí flow:** Child screen push từ Settings → Look & feel → Appearance. Chọn theme mode + accent, mọi thay đổi apply ngay lập tức (không nút Save).

**2. Layout trên→xuống:**
- Grabber; header: nút back tròn trái, title "Appearance" giữa.
- Section **"Theme"** — grid 2 cột, 2 card chọn theme:
  - Card "Day": khung preview mini (nền sáng #F3F3F7, 1 thanh title giả + 2 row card trắng giả) + label "Day" + checkmark tròn accent (đang chọn). Card có border 2px accent khi selected.
  - Card "Night": preview mini nền tối (#121319, thanh #3A3C46, rows #1E2028) + label "Night" + vòng tròn rỗng (chưa chọn), border transparent.
- Section **"Accent"** — card trắng 1 hàng ngang 7 swatch tròn 34px, cách đều: Blue #1544FD (selected — ring: khoảng trắng 2.5px + vòng ngoài cùng màu), Indigo #4B3FD6, Teal #0E9BA4, Purple #7451EB, Pink #D6479B, Graphite #5D6069, Mono/Black #17181C.
- Card tiếp theo 3 rows:
  1. "Automatic Dark Mode" — value "Scheduled" + chevron-right.
  2. "Text Size" — value "Default" + chevron-down (picker inline).
  3. "Reduce Motion" — toggle OFF.
- Card cuối 1 row: "Language" — value "Tiếng Việt" + chevron-down (lặp lại từ Settings cho tiện, chọn inline).

**3. Copy:** "Theme", "Day", "Night", "Accent", "Automatic Dark Mode · Scheduled", "Text Size · Default", "Reduce Motion", "Language · Tiếng Việt".

**4. Trạng thái/biến thể:** Selection state theme = border accent + checkmark filled; accent selected = ring 2 lớp (white gap + màu). "Automatic Dark Mode: Scheduled" gợi ý có các mode: Off / Scheduled / (System?) — mockup chỉ show value.

**5. Tương tác:** Tap card theme / swatch accent → apply tức thì toàn app (không confirm). Automatic Dark Mode push màn cấu hình lịch. Text Size + Language chọn inline.

**6. Ghi chú designer:** "Appearance — Day/Night preview + 7 accent, apply tức thì".

**7. Flow insight:**
- Theme picker dạng **preview thu nhỏ trung thực** (mini skeleton của UI thật) thay vì chỉ label — user thấy trước kết quả.
- Đúng 7 accent preset (khớp quyết định hiện tại của app: 7 Design-System presets, bỏ custom RGB).
- Đặt tên theme "Day/Night" (thân thiện) thay vì "Light/Dark". Accent có tên riêng ("Loox Blue" hiển thị ở row Settings cha).
- Reduce Motion là setting in-app (bổ sung, không chỉ ăn theo hệ thống).

---

## 5c · iCloud Sync — chỉ ciphertext, Sync Now, Pair New Device

**1. Mục đích + vị trí flow:** Child screen từ Settings → Vault & data → iCloud Sync. Quản lý sync + điểm khởi phát pairing thiết bị mới (đầu "máy cũ" của flow 6e/6f).

**2. Layout trên→xuống:**
- Grabber; header back + title "iCloud Sync".
- Card 1 row: icon cloud (blue tint) + "Sync with iCloud" + toggle ON.
- **Footnote ngay dưới card:** "Only encrypted ciphertext ever reaches iCloud. Apple can't read your vault — neither can we."
- Card 2 action rows:
  1. "Sync Now" (accent, semibold) + phụ chú phải cùng hàng "Last sync 09:41" (gray nhỏ).
  2. "Pair New Device" (accent, semibold) + chevron-right → flow quét QR (đối ứng 6e/6f).
- Section **"This vault syncs to"** — card danh sách thiết bị:
  1. Icon iPhone + "iPhone 17 Pro" / subtitle "This device" + badge pill xanh lá "Active".
  2. Icon iPhone + "iPhone 15" / subtitle "Paired Jun 12, 2026" + badge pill xám "Synced 2h ago".

**3. Copy:** "Sync with iCloud", footnote trust ở trên, "Sync Now", "Last sync 09:41", "Pair New Device", "This vault syncs to", "This device", "Paired Jun 12, 2026", badges "Active" / "Synced 2h ago".

**4. Trạng thái/biến thể:** Toggle sync ON/OFF (OFF chắc chắn ẩn/disable các phần dưới — mockup chỉ show ON). Badge thiết bị: xanh "Active" (máy hiện tại) vs xám "Synced Xh ago" (máy khác, hiển thị độ trễ sync). Subtitle ghi ngày pair.

**5. Tương tác:** "Sync Now" trigger sync thủ công (cập nhật "Last sync"); "Pair New Device" mở camera/scanner quét QR trên máy mới; row thiết bị có thể tap để quản lý/revoke (mockup không show màn detail).

**6. Ghi chú designer:** "iCloud Sync — chỉ ciphertext, Sync Now, Pair New Device".

**7. Flow insight:**
- Câu trust copy "Only encrypted ciphertext… neither can we" đặt ngay dưới toggle — trấn an đúng chỗ user đang do dự bật sync.
- Device list minh bạch "vault này sync tới đâu" + trạng thái từng máy — nền tảng cho revoke sau này.
- "Pair New Device" nằm trong iCloud Sync (không phải mục riêng) → mô hình: sync = ciphertext qua iCloud, còn **key được chuyển qua pairing QR riêng** (khớp kiến trúc "Vault Key never syncs" của app; pairing là kênh provision key).

---

## 5d · Import — preview trước khi ghi vào vault

**1. Mục đích + vị trí flow:** Child screen từ Settings → Vault & data → Import. Import file (vd 1Password CSV) với bước preview bắt buộc trước khi ghi.

**2. Layout trên→xuống:**
- Grabber; header back + title "Import".
- Card file đã chọn: icon file (teal) + "1password-export.csv" / subtitle "1Password CSV · parsed" + nút text accent "Change" bên phải.
- Section **"Preview · 34 records"** — card danh sách preview:
  - Row: avatar chữ cái màu (A/Y/M/W, mỗi cái 1 tint) + tên item ("Amazon", "YouTube Premium", "MB Bank", "Wi-Fi passwords") + type bên phải gray ("Login", "Login", "Login", "Note").
  - Row cuối căn giữa: "…and 30 more · includes 2 passkeys".
- CTA đáy (pinned): pill accent "Import 34 Records".

**3. Copy:** "1password-export.csv", "1Password CSV · parsed", "Change", "Preview · 34 records", types "Login"/"Note", "…and 30 more · includes 2 passkeys", "Import 34 Records".

**4. Trạng thái/biến thể:** Trạng thái mockup = file đã parse thành công. Ngầm định còn: trạng thái chưa chọn file (file picker), parse error, format khác (subtitle tự nhận diện format "1Password CSV"). Số record lặp lại ở cả section label lẫn nút CTA.

**5. Tương tác:** "Change" đổi file; danh sách chỉ để duyệt (row không chevron); "Import N Records" ghi vào vault rồi báo kết quả.

**6. Ghi chú designer:** "Import — preview trước khi ghi vào vault".

**7. Flow insight:**
- **Preview-first**: user thấy đúng những gì sẽ được ghi (tên + type + tổng số + số passkey) trước khi commit — không import mù.
- Auto-detect format hiển thị ngay subtitle ("1Password CSV · parsed") → tăng confidence.
- CTA nêu số lượng cụ thể "Import 34 Records" thay vì "Import" chung chung.
- Ghi chú "includes 2 passkeys" — import có hỗ trợ passkey (đối lập với export, xem 5e).

---

## 5e · Export — tab Encrypted/CSV, cảnh báo đỏ cho CSV

**1. Mục đích + vị trí flow:** Child screen từ Settings → Vault & data → Export. 2 chế độ: Encrypted (mặc định, tab đầu) và CSV (plain text, phải cảnh báo). Mockup show tab CSV đang chọn.

**2. Layout trên→xuống:**
- Grabber; header back + title "Export".
- **Segmented control** 2 tab: "Encrypted" | "CSV" (CSV active trong mockup; Encrypted đứng trước = mặc định).
- (Tab CSV) **Banner cảnh báo đỏ** (nền đỏ nhạt, icon tam giác đỏ): "A CSV file is **not encrypted**. Anyone who opens it sees every password in plain text. Passkeys are never included." ("not encrypted" nhấn đỏ đậm).
- Section **"What's included"** — card 3 rows dạng label + count:
  1. "Logins & passwords" — "34".
  2. "Secure notes" — "5".
  3. "Passkeys" — "Never exported" (cả row mờ ~45% opacity).
- CTA đáy: pill **ĐỎ** "Create Unencrypted Export" (shadow đỏ).

**3. Copy:** tabs "Encrypted"/"CSV"; warning như trên; "What's included"; "Logins & passwords · 34"; "Secure notes · 5"; "Passkeys · Never exported"; "Create Unencrypted Export".

**4. Trạng thái/biến thể:** 2 tab = 2 biến thể màn. Tab Encrypted (không show trong mockup) suy ra: không banner đỏ, CTA màu accent, passkeys có thể vẫn "Never exported" (câu warning nói "Passkeys are never included" cho CSV; mockup không xác nhận cho Encrypted — cần quyết định khi implement). Row Passkeys luôn dim để thể hiện không nằm trong export.

**5. Tương tác:** Đổi tab đổi toàn bộ nội dung + màu CTA; "Create Unencrypted Export" nên có thêm confirm/Face ID trước khi tạo file (mockup không show, đề xuất theo chuẩn app).

**6. Ghi chú designer:** "Export — tab CSV với cảnh báo đỏ; Encrypted là mặc định".

**7. Flow insight:**
- **Friction có chủ đích cho CSV**: banner đỏ + CTA đỏ + tên nút tự thú "Create *Unencrypted* Export" — user không thể không biết mình đang làm gì. Encrypted là default path.
- Bảng "What's included" với count cụ thể + row Passkeys dim "Never exported" — minh bạch giới hạn export ngay trong UI thay vì giấu trong docs.

---

## 5f · Erase Vault — dialog xác nhận

**1. Mục đích + vị trí flow:** Alert dialog xuất hiện khi tap "Erase Vault…" ở Settings (5g). Nền Settings phía sau blur + dim.

**2. Layout:** Native-style alert căn giữa (rộng ~280, nền frosted trắng, bo 16):
- Title bold: "Erase Everything?"
- Body: "This permanently deletes every item and key on this iPhone. Without your Emergency Kit, nothing can be recovered."
- 2 nút chia đôi ngăn bởi hairline: "Cancel" (accent, semibold, bên trái) | "Erase" (đỏ, bold, bên phải).

**3. Copy:** như trên, nguyên văn.

**4. Trạng thái/biến thể:** 1 trạng thái. Cân nhắc thêm bước 2 (gõ chữ xác nhận / Face ID) khi implement — mockup chỉ có 1 dialog.

**5. Tương tác:** Cancel đóng dialog; Erase xóa toàn bộ item + key trên máy → về onboarding.

**6. Ghi chú designer:** "Erase Vault — dialog xác nhận, copy nói rõ hệ quả".

**7. Flow insight:** Copy nói rõ 2 hệ quả: (a) xóa cả item lẫn **key** trên thiết bị này, (b) không có Emergency Kit thì không cứu được — nhắc đúng recovery path của app. Title dạng câu hỏi "Erase Everything?" mạnh hơn "Erase Vault?".

---

## 6a · AutoFill extension — list "For this app" / "Other logins", shared item đánh dấu

**1. Mục đích + vị trí flow:** UI của Credential Provider extension khi user tap trường password trong app khác (nền sau là app bị blur). Sheet nổi từ ~1/3 màn.

**2. Layout trên→xuống:**
- Nền: app đích blur + dim (skeleton 2 input + 1 nút).
- Sheet bo 28 trên: grabber → header: "Cancel" (accent, trái) + **logo Loox** căn giữa (brand, không title chữ) + phải trống.
- Section **"For this app"** — card:
  1. Row credential match: favicon chữ "S" (tint cam) + "Shopee" / subtitle username "minh.anh@icloud.com" + chevron-right.
  2. Row "Create new login" — icon dấu cộng (blue tint) + text accent semibold → màn 6b.
- Section **"Other logins"** — card:
  1. "GitHub" / "minh.anh" (không chevron — tap là fill).
  2. "VPBank Family **· Shared**" (chữ "· Shared" màu xanh lá inline ngay sau tên) / "trang.nguyen88".
- **Footnote cuối, căn giữa:** "Shared items need an internet connection."

**3. Copy:** "Cancel", "For this app", "Create new login", "Other logins", "· Shared", "Shared items need an internet connection."

**4. Trạng thái/biến thể:**
- Match theo app/domain → section "For this app"; còn lại vào "Other logins" (search toàn vault).
- Shared item: suffix "· Shared" xanh lá — phân biệt item nhận qua Approval Mode sharing; các item này cần mạng để dùng (footnote).
- Row match có chevron (có thể xem chi tiết/chọn field?), row khác không chevron — tap fill trực tiếp.

**5. Tương tác:** Tap credential → Face ID (nếu cần) → fill; "Create new login" → 6b; "Cancel" trả về app đích.

**6. Ghi chú designer:** "AutoFill — 'For this app' / 'Other logins', item shared đánh dấu".

**7. Flow insight:**
- Header dùng logo brand thay title chữ — extension nhận diện ngay là Loox.
- "Create new login" đặt NGAY TRONG section "For this app" (bên dưới match) — path tạo mới cho app hiện tại rất ngắn.
- Shared item được đánh dấu inline + giải thích ràng buộc mạng bằng footnote — quan trọng với kiến trúc share online-gated hiện tại của app.

---

## 6b · AutoFill — Create new login: password tự sinh, Save & Fill

**1. Mục đích + vị trí flow:** Push từ 6a "Create new login". Tạo login mới ngay trong extension: website + username prefill, password auto-generated, 1 nút vừa lưu vừa điền.

**2. Layout trên→xuống:**
- Nền app đích blur; sheet cao hơn (từ ~290px).
- Grabber; header: "Back" (trái, accent) + title "New Login" giữa.
- Card form 3 field (label caption uppercase nhỏ + value):
  1. "WEBSITE" → "shopee.vn" (prefill từ context app/domain).
  2. "USERNAME" → "minh.anh@icloud.com" (prefill/editable).
  3. "PASSWORD · GENERATED" → password monospace có syntax highlight (ký tự đặc biệt đỏ, số xanh: `tR8!mWq3vZk#pY7d`) + nút regenerate (icon 2 mũi tên vòng, accent) bên phải.
- **Footnote căn giữa:** "Saved to your vault, then filled into Shopee."
- CTA đáy: pill accent "Save & Fill".

**3. Copy:** "Back", "New Login", labels "Website"/"Username"/"Password · generated", footnote trên, "Save & Fill".

**4. Trạng thái/biến thể:** Password mặc định là generated (label ghi rõ "· generated"); regenerate đổi password mới. Username/website editable.

**5. Tương tác:** Icon refresh → sinh password mới; "Save & Fill" = lưu vào vault + fill vào app đích trong 1 tap; "Back" về 6a.

**6. Ghi chú designer:** "AutoFill — Create new login: password tự sinh, Save & Fill".

**7. Flow insight:**
- **Một nút "Save & Fill"** gộp 2 hành động — không có nút Save riêng rồi phải fill lại.
- Footnote nói rõ trình tự "Saved to your vault, then filled into Shopee" (nêu đích danh tên app) — xóa mơ hồ "lưu ở đâu".
- Password highlight màu theo loại ký tự (đỏ = symbol, xanh = digit) + monospace — dễ đọc/kiểm tra bằng mắt. App đã có Font.vaultCode, cần thêm attributed coloring.
- Label field "Password · generated" tự documenting.

---

## 6c · Profile — persona đang hoạt động, Identity & Payment tap-to-copy

**1. Mục đích + vị trí flow:** Màn Profile full-screen (không phải sheet), push từ Home. Trung tâm: persona active, quản lý personas, Private Email, Identity autofill data, Payment card.

**2. Layout trên→xuống:**
- Nút back tròn frosted (trái, trên).
- Khối avatar căn giữa: avatar tròn 84px gradient (chữ "M") + badge camera nhỏ góc dưới-phải (đổi ảnh) + tên "Minh Anh" (20px, extrabold) bên dưới.
- Section **"Persona"** — card 3 rows:
  1. Row persona active: icon người (blue tint) + "Personal" / subtitle "Standard privacy · active" + nút pill nhỏ accent nhạt "Switch".
  2. "Manage personas" — chevron-right.
  3. "Private Email" — value "3 addresses" + chevron-right → màn 6d.
- Section **"Identity"** — header có nút "Edit" (accent, phải). Card 3 field (label caption + value, dạng giống form read-only):
  1. "FULL NAME" → "Nguyễn Minh Anh"
  2. "EMAIL" → "minh.anh@icloud.com"
  3. "PHONE" → "+84 90 ••• 4421" (mask giữa)
- Section **"Payment card"** — header có "Edit". Card 1 row: icon thẻ (teal) + "Vietcombank Visa" / số thẻ monospace "•••• •••• •••• 4421".

**3. Copy:** "Persona", "Personal", "Standard privacy · active", "Switch", "Manage personas", "Private Email · 3 addresses", "Identity", "Edit", "Full name", "Email", "Phone", "Payment card", "Vietcombank Visa".

**4. Trạng thái/biến thể:** Persona row show persona đang active + mô tả privacy level ("Standard privacy"); subtitle "· active". Phone/số thẻ mask mặc định. Count alias hiển thị trên row Private Email.

**5. Tương tác:** Theo label designer: field Identity & Payment là **tap-to-copy** (tap value copy vào clipboard — kết hợp Clear clipboard 30s ở Settings). "Switch" đổi nhanh persona không cần vào Manage. "Edit" bật chế độ sửa từng section. Badge camera đổi avatar.

**6. Ghi chú designer:** "Profile — persona đang hoạt động, Identity & Payment tap-to-copy".

**7. Flow insight:**
- Persona đưa lên đầu Profile với nút "Switch" 1-tap — persona là khái niệm hạng nhất (khớp Persona/Relay proposal V3 của app).
- Private Email neo trong section Persona (alias thuộc persona) chứ không nằm trong Settings — Settings chỉ có toggle bật/tắt dịch vụ (5a).
- Identity + Payment = dữ liệu autofill cá nhân, mask mặc định, tap-to-copy, Edit riêng từng section — Profile kiêm "identity autofill hub".

---

## 6d · Private Email — alias theo persona, trạng thái forwarding

**1. Mục đích + vị trí flow:** Push từ Profile → Private Email. Quản lý alias email nhận-chuyển-tiếp, chia 2 loại: reusable và site-specific.

**2. Layout trên→xuống:**
- Header: back tròn frosted (trái) + nút "+" tròn accent (phải, tạo alias mới).
- Title lớn kiểu large-title: "Private Email" (31px extrabold).
- **Banner info xanh nhạt** (icon phong bì accent): "Receive-only aliases. Mail forwards to **m•••@icloud.com** — senders never see your real address." (địa chỉ thật được mask).
- Section **"Reusable addresses"** — card 1 row: icon phong bì (blue tint) + alias monospace "swift.otter@loox.email" / status xanh "Forwarding active" + chevron-right.
- Section **"Site-specific addresses"** — card:
  1. Favicon "S" cam + "shopee.9fk2@loox.email" (mono) / status xanh "Forwarding active · Shopee" + chevron.
  2. Favicon "T" xám + "tiki.k3wp@loox.email" / status vàng "**Tap to activate** · Tiki" + chevron.
  3. Row "Create address" — icon "+" + text accent semibold.
- Card cuối 1 row: "Forwarding inboxes" + badge pill xanh "Verified" + chevron-right.

**3. Copy:** banner như trên; "Reusable addresses"; "Site-specific addresses"; statuses "Forwarding active", "Forwarding active · Shopee", "Tap to activate · Tiki"; "Create address"; "Forwarding inboxes · Verified".

**4. Trạng thái/biến thể:** Alias có 2 trạng thái: active (xanh) / chưa kích hoạt "Tap to activate" (vàng). Site-specific alias gắn tên site trong status. Forwarding inbox có trạng thái verify (badge "Verified"; ngầm định có trạng thái unverified).

**5. Tương tác:** "+" header và "Create address" cùng tạo alias mới; tap alias → detail (đổi trạng thái, copy, xóa — không show trong mockup); row status vàng tap để kích hoạt luôn; "Forwarding inboxes" quản lý địa chỉ đích + verify.

**6. Ghi chú designer:** "Private Email — alias theo persona, trạng thái forwarding". (Alias thuộc persona hiện hành — vào từ Profile/persona.)

**7. Flow insight:**
- Mô hình 2 loại alias: **reusable** (tên đẹp, dùng nhiều nơi: `swift.otter@`) vs **site-specific** (auto-gen theo site: `shopee.9fk2@`) — naming convention `site.rand@loox.email`.
- Banner giải thích mô hình receive-only + mask cả địa chỉ thật của chính user ngay trong UI.
- Trạng thái forwarding per-alias hiển thị inline bằng màu — không cần vào detail.
- "Forwarding inboxes" tách riêng: alias nhiều — inbox đích ít và phải verified.

---

## 6e · Join Flow — máy MỚI hiện QR, chờ máy cũ quét

**1. Mục đích + vị trí flow:** Màn onboarding/join trên **thiết bị mới** khi user chọn pair với máy cũ. Đầu kia của flow là 5c "Pair New Device" (máy cũ mở scanner) và 6f (máy cũ confirm).

**2. Layout:** Full-screen sáng, căn giữa dọc:
- Nút back tròn (trên trái).
- Title: "Pair with your other iPhone" (24px extrabold, căn giữa).
- Hướng dẫn: "On your old device, open Loox → Settings → iCloud Sync → **Pair New Device**, then scan this code."
- **QR code lớn** trong card trắng bo 24 (232×232).
- Pill trạng thái bên dưới (nền frosted): spinner accent + "Waiting for your other device…".

**3. Copy:** như trên, nguyên văn (path chỉ dẫn khớp đúng IA của Settings 5g→5c).

**4. Trạng thái/biến thể:** Trạng thái chờ (spinner). Ngầm định các trạng thái tiếp: máy cũ đã quét → chờ approve → nhận key thành công / hết hạn QR.

**5. Tương tác:** Back hủy pairing; màn tự tiến khi máy cũ Approve (6f).

**6. Ghi chú designer:** "Join Flow — máy mới hiện QR, chờ máy cũ quét".

**7. Flow insight:**
- **Chiều QR: máy MỚI hiển thị, máy CŨ quét** — máy đang giữ key là bên chủ động xác thực, chống việc máy lạ tự quét để xin key.
- Hướng dẫn inline lặp lại đúng breadcrumb Settings của máy cũ — user không phải đoán.
- Status pill "Waiting…" cho biết pairing là realtime 2 máy.

---

## 6f · Pair Device (máy CŨ) — confirm trước khi gửi key

**1. Mục đích + vị trí flow:** Sheet trên **máy cũ** sau khi quét QR của máy mới (từ 5c "Pair New Device"). Bước xác nhận cuối trước khi gửi encrypted vault key. Không bao giờ tự gửi.

**2. Layout:** Sheet nổi từ ~1/3 dưới màn (nền dim):
- Grabber.
- Icon lớn giữa: iPhone + dấu cộng trong ô bo 22 nền accent nhạt (72×72).
- Title: "Add this device to your vault?" (22px extrabold, căn giữa).
- Body: "**iPhone 15** · scanned just now. It will receive your encrypted vault key and start syncing." (tên máy bold).
- **Pill cảnh báo vàng** (icon tam giác): "Only approve if that's your phone in your hand."
- Nút: pill accent full-width "Approve" + text button "Cancel" bên dưới.

**3. Copy:** như trên, nguyên văn.

**4. Trạng thái/biến thể:** 1 trạng thái confirm. Body nêu device name + độ tươi của scan ("scanned just now") — chống replay/QR cũ.

**5. Tương tác:** "Approve" gửi encrypted vault key tới máy mới → máy mới (6e) tiến sang hoàn tất; "Cancel" hủy. Nên yêu cầu Face ID trước khi gửi key (mockup không show, khuyến nghị).

**6. Ghi chú designer:** "Pair Device (máy cũ) — xác nhận trước khi gửi key, không bao giờ tự gửi" — nguyên tắc: **không bao giờ tự động gửi key**, luôn cần approve thủ công trên máy cũ.

**7. Flow insight:**
- Consent rõ ràng ở máy giữ key: nêu tên thiết bị, thời điểm quét, và hệ quả ("will receive your encrypted vault key and start syncing").
- Câu cảnh báo social-engineering "Only approve if that's your phone in your hand" — phòng kịch bản kẻ xấu gửi QR nhờ quét hộ.
- Kết hợp 5c + 6e + 6f = flow key-provisioning hoàn chỉnh giải quyết gap "Vault Key never syncs" của kiến trúc multi-device hiện tại: ciphertext qua iCloud, key qua QR pairing có approve.

---

## Tổng hợp pattern xuyên suốt (cho dev SwiftUI)

1. **Sheet-first Settings**: root Settings + child screens đều trong 1 sheet stack (Done ở root, back tròn ở child).
2. **Footnote-dưới-card**: mọi điểm nhạy cảm (sync, shared item, save&fill, erase) đều có 1 câu giải thích ngắn ngay tại chỗ.
3. **Màu = mức nguy hiểm**: accent cho action thường, đỏ cho destructive (cả banner + CTA), vàng cho cảnh báo/chưa kích hoạt, xanh lá cho trạng thái tốt/verified/shared.
4. **CTA nêu hệ quả cụ thể**: "Import 34 Records", "Create Unencrypted Export", "Save & Fill" — không dùng động từ chung chung.
5. **Value composite trên row cha**: "Day · Loox Blue", "3 addresses", "v2.4.1" — row Settings tóm tắt trạng thái màn con.
6. **Status inline per-row**: Online features, alias forwarding, device sync — trạng thái sống ngay trong list, không cần mở detail.
7. **Passkey policy nhất quán**: import CÓ passkey, export KHÔNG BAO GIỜ (CSV chắc chắn; Encrypted cần chốt), row Passkeys luôn dim trong Export.
8. **Key provisioning**: pairing QR (máy mới show, máy cũ quét + approve) tách khỏi iCloud sync ciphertext.

## Unresolved questions

- Tab "Encrypted" của Export: mockup không show — format file (vault bundle?), passkeys có kèm không, có passphrase riêng không?
- "Extra Protection" (Settings) là gì — secret key kiểu 1Password hay PIN phụ? Mockup chỉ có row.
- Alias Private Email theo persona: mockup không show UI đổi persona trong màn 6d — filter theo persona active hay show tất cả?
- Row credential "For this app" có chevron còn "Other logins" không — chủ ý (detail vs fill-ngay) hay chỉ minh họa?
- Erase Vault: có cần bước xác thực thứ 2 (Face ID/typed confirmation) ngoài dialog?
