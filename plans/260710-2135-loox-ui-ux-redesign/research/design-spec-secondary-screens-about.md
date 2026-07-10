# Design Spec — Màn phụ (Đợt 10) + About Us storytelling (Đợt 13)

Nguồn: `scratchpad/loox-design-unpacked/turns/t10.html` + `t13.html` (web mockup tham khảo flow, KHÔNG port pixel CSS).
Frame chuẩn: iPhone 402×874. Palette chung của mock: bg screen `#F3F3F7`, text primary `#17181C`, secondary `#6F7178`, tertiary `#A9ABB2`, accent blue `#1544FD`, success green `#1F9D5B`, warning amber `#B87D0E`/`#E9A13B`, destructive red `#E5484D`, purple `#7451EB`, teal `#0E9BA4` — map sang ThemeRole tương ứng khi implement (accent/success/warning/destructive), không hardcode.

Hai pattern container lặp lại toàn đợt 10:
- **Sheet pattern**: card sheet bo góc trên 28px trượt lên trên nền dimmed (`#9B9CA6`), có grabber (36×5 pill), header trong sheet = nút X tròn 34px (trái) + title bold căn giữa. → SwiftUI: `.sheet` với detent tuỳ chiều cao nội dung.
- **Push pattern**: full-screen bg `#F3F3F7`, nút back tròn 40px nền trắng mờ blur (chevron trái), không title bar (title nằm trong nội dung). → push trong NavigationStack.
- **Inset grouped card**: khối trắng bo 20px, shadow rất nhẹ, các row phân cách hairline `rgba(60,60,67,.1)`, row = label xám trái + value đậm phải.
- **Primary CTA**: nút pill full-width nền `#1544FD`, chữ trắng bold, shadow xanh, đặt sát đáy (bottom padding ~48px).

---

## 10a · Passkey detail (sheet)

**1. Mục đích + vị trí flow**: Màn chi tiết 1 passkey — mở từ item detail (login có passkey) hoặc list passkey. Sheet (không push) vì là thông tin phụ đọc nhanh + 1 hành động destructive.

**2. Layout trên → dưới**:
1. Grabber + header sheet: nút X trái, title **"Passkey"** giữa.
2. Hero căn giữa: monogram site 60×60 bo 17px (chữ "G"), tên site đậm 19px **"github.com"**, badge pill xanh lá nền `success` 11%: icon cloud-check + **"Backed up"**.
3. Card info 4 row (label trái xám / value phải đậm):
   - `Username` → `minh.anh`
   - `Created` → `Mar 12, 2026`
   - `Last used` → `Yesterday, 21:14`
   - `Credential ID` → monospace, truncate giữa: `kD82…f4Qz`
4. Card đơn: nút **"Delete Passkey"** chữ đỏ destructive, căn giữa.
5. Footnote xám nhạt 12px căn giữa dưới nút: **"Deleting permanently destroys the private key. You may lose access to this account."**

**3. Copy (EN)**: Passkey · Backed up · Username · Created · Last used · Credential ID · Delete Passkey · "Deleting permanently destroys the private key. You may lose access to this account."

**4. Trạng thái/biến thể**: Badge "Backed up" (xanh) — ngụ ý có biến thể ngược "Not backed up"/device-only (mock không vẽ; suy ra: badge xám/amber khi passkey chưa sync iCloud Keychain-style/envelope backup). Credential ID luôn truncate ellipsis.

**5. Tương tác**: X đóng sheet. Tap "Delete Passkey" → cần confirm destructive (mock không vẽ dialog nhưng bắt buộc theo chuẩn app). Không có nút Edit — passkey read-only ngoại trừ delete.

**6. Ghi chú VI designer**: option label: *"Passkey detail — badge backup, Delete huỷ private key vĩnh viễn"*.

**7. Insight**: (a) tách passkey thành detail sheet riêng thay vì nhét vào form login; (b) cảnh báo mất private key đặt NGAY dưới nút delete dạng footnote thường trực chứ không đợi confirm dialog — user đọc rủi ro trước khi bấm; (c) badge backup status nổi bật ngay hero → trấn an "xoá app không mất passkey" hoặc cảnh báo ngược lại. Map tốt vào gap hiện tại của Vaultify (in-app passkey section — xem memory passkey-in-share gaps).

---

## 10b · Change Master Password (sheet)

**1. Mục đích + flow**: Đổi master password, mở từ Settings → Security. Sheet cao (top 130px).

**2. Layout**:
1. Grabber + header: X + title **"Change Master Password"**.
2. Section label uppercase **"CURRENT PASSWORD"** → field trắng bo 16px: dấu chấm ẩn `••••••••••••` + icon check xanh phải (= đã verify đúng mật khẩu hiện tại).
3. Section label **"NEW PASSWORD"** → field: chữ monospace hiển thị rõ `plum-Rocket-91-harbor` + caret xanh + icon con mắt (toggle reveal). Dưới trong cùng field: **strength meter 4 đoạn** đều xanh lá + label **"Excellent"** bên phải.
4. Field confirm: dấu chấm `•••…` (21 chấm — khớp độ dài) + check xanh (= khớp).
5. Info banner nền accent 7% bo 16px, icon ⓘ xanh: **"Your Vault Key doesn't change — Face ID and your Emergency Kit keep working as before."**
6. CTA đáy: **"Save New Password"**.

**3. Copy (EN)**: Change Master Password · Current password · New password · Excellent · "Your Vault Key doesn't change — Face ID and your Emergency Kit keep working as before." · Save New Password.

**4. Trạng thái**: Field-level validation từng bước: check xanh xuất hiện khi (a) current password đúng, (b) confirm khớp. Strength meter 4 mức (mock chỉ vẽ mức Excellent — cần thang Weak/Fair/Good/Excellent, màu đỏ→amber→xanh). New password mặc định reveal (monospace) có eye toggle; current/confirm mặc định ẩn.

**5. Tương tác**: Eye toggle reveal new password. CTA disabled cho tới khi cả 3 điều kiện pass (suy ra). Save → re-wrap Vault Key bằng KDF mật khẩu mới (kiến trúc envelope: Vault Key bất biến).

**6. Ghi chú VI**: *"Change Master Password — Vault Key giữ nguyên"*.

**7. Insight**: **Banner "Vault Key doesn't change"** là điểm ăn tiền — chủ động trả lời nỗi sợ ngầm "đổi mật khẩu có làm hỏng Face ID / Emergency Kit / share không?". Khớp đúng kiến trúc Vaultify (master password chỉ wrap Vault Key). Strength meter nằm TRONG field card, không tách rời. Verify current password inline (check xanh) thay vì lỗi sau khi submit.

---

## 10c · Extra Protection (sheet)

**1. Mục đích + flow**: Thiết lập "mật khẩu phụ" (second password) bảo vệ các field siêu nhạy cảm — hỏi lại kể cả khi vault đã unlock. Mở từ Settings → Security (hoặc từ field editor khi user bật extra-protect cho 1 field). Đây là FEATURE MỚI chưa có trong Vaultify.

**2. Layout**:
1. Grabber + header: X + **"Extra Protection"**.
2. Explainer card trắng bo 18px: icon ổ khoá tím trong ô 38×38 nền tím 11% + text: **"A second password for your most sensitive fields — ID numbers, recovery codes, SSH keys. Asked _even when the vault is unlocked_."** (đoạn in đậm: "even when the vault is unlocked").
3. Section label **"EXTRA PASSWORD"** → field ẩn `••••••••••` + eye toggle.
4. Field confirm ẩn + check xanh (khớp).
5. Warning banner nền amber 13% bo 16px, icon tam giác amber: **"This password can't be recovered — not even with your Emergency Kit."**
6. CTA: **"Set Extra Password"**.

**3. Copy (EN)**: Extra Protection · "A second password for your most sensitive fields — ID numbers, recovery codes, SSH keys. Asked even when the vault is unlocked." · Extra password · "This password can't be recovered — not even with your Emergency Kit." · Set Extra Password.

**4. Trạng thái**: Setup lần đầu (mock này). Suy ra thêm: trạng thái đã bật (đổi/tắt extra password), và prompt nhập extra password khi mở field được bảo vệ. Không có strength meter (khác 10b — chấp nhận passphrase ngắn hơn? nên cân nhắc thêm meter khi implement).

**5. Tương tác**: Eye toggle. CTA enable khi 2 field khớp. Sau set → các field đánh dấu extra-protect sẽ yêu cầu nhập lại mật khẩu này mỗi lần reveal.

**6. Ghi chú VI**: *"Extra Protection — mật khẩu phụ cho field siêu nhạy cảm"*.

**7. Insight**: (a) định vị rõ scope = **field-level**, không phải item-level; ví dụ cụ thể (ID numbers, recovery codes, SSH keys) ngay trong explainer; (b) warning "không recover được kể cả Emergency Kit" = trung thực về trade-off, đặt trước CTA; (c) icon màu tím tách biệt khỏi accent xanh → ngôn ngữ màu riêng cho tầng bảo mật thứ 2. Về crypto: ngụ ý key riêng derive từ extra password, KHÔNG nằm trong Vault Key escrow — cần ADR khi implement (ảnh hưởng sync/share các field này).

---

## 10d · Automatic Dark Mode (push)

**1. Mục đích + flow**: Cài đặt chế độ dark mode tự động. Push từ Settings → Appearance. (Mock dùng sheet-like top 58px nhưng nút back là chevron ← → coi là push child screen.)

**2. Layout**:
1. Header: nút back chevron tròn + title **"Automatic Dark Mode"**.
2. Card radio group 4 lựa chọn (mỗi row: label trái + radio circle phải; selected = circle nền accent + check trắng):
   - **Off**
   - **Match system**
   - **Scheduled** ← đang chọn
   - **Below a brightness level**
3. Section label **"SCHEDULE"** (chỉ hiện khi chọn Scheduled) → card 2 row:
   - `From` → chip time `22:00` (nền xám nhạt bo 9px — style iOS time picker chip)
   - `To` → chip `07:00`
4. Card đơn: row **"Night theme"** → value phải **"Night Tinted"** + chevron xuống (disclosure menu chọn theme đêm).

**3. Copy (EN)**: Automatic Dark Mode · Off · Match system · Scheduled · Below a brightness level · Schedule · From · To · Night theme · Night Tinted.

**4. Trạng thái/biến thể**: 4 mode; section Schedule chỉ render khi mode = Scheduled (suy ra: mode "Below a brightness level" sẽ thay bằng slider brightness threshold). "Night theme" chọn theme dark áp dụng khi auto kích hoạt (Night Tinted là 1 preset — gợi ý có nhiều night theme).

**5. Tương tác**: Radio chọn 1; tap chip giờ → time picker; tap Night theme → menu/sheet chọn theme.

**6. Ghi chú VI**: *"Automatic Dark Mode — Scheduled 22:00–07:00"*.

**7. Insight**: Học từ Telegram: tách "khi nào dark" (trigger: off/system/schedule/brightness) khỏi "dark là theme nào" (Night theme). Vaultify hiện chỉ có light/dark/system — đây là mở rộng: scheduled + brightness trigger + chọn night theme riêng. Option "Below a brightness level" dùng ambient/screen brightness — iOS không có public API ambient light; thực tế dùng `UIScreen.brightness` observe — cân nhắc feasibility, có thể cắt.

---

## 10e · Alias detail (push)

**1. Mục đích + flow**: Chi tiết 1 email alias (masked email `@loox.email`) — push từ danh sách Aliases (Personas/Aliases area). Quản lý forwarding + pause/delete.

**2. Layout**:
1. Header push: back chevron tròn trắng blur.
2. Hero căn giữa: monogram site 56×56 bo 16px chữ "S" màu cam (`#E8590C` = brand shopee), địa chỉ alias **monospace đậm** `shopee.9fk2@loox.email`, badge pill xanh: dot xanh + **"Forwarding active"**.
3. Card info 3 row:
   - `Website` → `shopee.vn` (màu accent = tappable link)
   - `Label` → `Mua sắm`
   - `Created` → `May 4, 2026`
4. Section **"FORWARDING"** → card 1 row: icon phong bì xanh ô 34×34, cột giữa: **"m•••@icloud.com"** đậm + sub xanh lá **"Verified · default inbox"**, phải: nút text accent **"Change"**.
5. Section **"ACTIONS"** → card 2 row text button:
   - **"Pause forwarding"** — màu amber (`#B87D0E`)
   - **"Delete permanently"** — màu đỏ destructive
6. Footnote xám căn giữa: **"Deleting can't be undone — mail to this address will bounce forever."**

**3. Copy (EN)**: Forwarding active · Website · Label · Created · Forwarding · Verified · default inbox · Change · Actions · Pause forwarding · Delete permanently · "Deleting can't be undone — mail to this address will bounce forever."

**4. Trạng thái/biến thể**: Badge status: "Forwarding active" (xanh) ↔ biến thể Paused (suy ra: amber, actions đổi thành "Resume forwarding"). Email đích masked một phần (`m•••@icloud.com`) ngay cả trong app — privacy-first. Label hiển thị tiếng Việt user tự đặt ("Mua sắm") — user content không localize.

**5. Tương tác**: Tap Website → mở web/liên kết item. "Change" → picker đổi hộp thư nhận (danh sách inbox đã verify). "Pause forwarding" → soft-off, alias giữ nguyên, mail bounce tạm. "Delete permanently" → confirm destructive; bounce vĩnh viễn.

**6. Ghi chú VI**: *"Alias detail — đổi hộp thư nhận, Pause / Delete vĩnh viễn"*.

**7. Insight**: (a) phân cấp hành động 3 mức rõ ràng: Change (accent, an toàn) / Pause (amber, đảo ngược được) / Delete (đỏ, vĩnh viễn) — kèm footnote giải thích hậu quả delete bằng ngôn ngữ đời thường ("bounce forever"); (b) alias address là monospace — nhất quán "mã máy" như Credential ID; (c) map thẳng vào auxiliary domains/alias feature (loox.pw memory) — màn này là UI đích cho alias detail.

---

## 10f · Share — Invite sent (sheet, success state)

**1. Mục đích + flow**: Màn kết thúc flow gửi lời mời share (Approval Mode). Xuất hiện sau khi gửi invite thành công. Mục tiêu UX: **giải phóng user khỏi chờ đợi** — fix đúng pain point "owner stuck on Waiting" (memory approval-share-accept-detection).

**2. Layout** (sheet thấp, top 250px, nội dung căn giữa dọc):
1. Grabber.
2. Icon check tròn 72px nền xanh lá 11%.
3. Title đậm 20px: **"Invite sent to Hoàng Nam"**.
4. Body xám: **"No need to wait here — they'll get a notification, and we'll ping you the moment they accept. You can track it anytime from Home."**
5. Status chip pill nền trắng: dot amber + **"Sharing "GitHub" · waiting for Hoàng Nam"** — preview của chip trạng thái sẽ hiển thị ở Home.
6. Cụm nút đáy:
   - CTA primary **"Done"** (đóng sheet).
   - Nút secondary trắng chữ accent, icon bubble chat: **"Nudge via Messages"**.
   - Caption dưới cùng: **"First time sharing with someone? A Messages nudge helps them find the invite."**

**3. Copy (EN)**: Invite sent to {name} · "No need to wait here — they'll get a notification, and we'll ping you the moment they accept. You can track it anytime from Home." · Sharing "{item}" · waiting for {name} · Done · Nudge via Messages · "First time sharing with someone? A Messages nudge helps them find the invite."

**4. Trạng thái**: Đây chính là success/terminal state của send-invite flow. Chip amber "waiting" = pending; ngụ ý Home có chip tương ứng chuyển xanh khi accept (push notification "ping you the moment they accept").

**5. Tương tác**: "Done" đóng sheet về nơi bắt đầu share. "Nudge via Messages" → mở MSMessages/share sheet gửi iMessage kèm link/hướng dẫn tìm invite (đặc biệt cho lần đầu — CloudKit share invite dễ bị miss). Không có nút "chờ ở đây" — chủ đích.

**6. Ghi chú VI**: *"Share — Invite sent: không bắt đợi, đóng sheet, push sẽ báo khi accept"*.

**7. Insight**: 3 quyết định flow đáng học: (a) **không block user chờ accept** — thay polling screen bằng: notification push khi accept + chip theo dõi ở Home; (b) chip preview ngay trong success screen dạy user "trạng thái này sẽ nằm ở đâu"; (c) "Nudge via Messages" giải bài toán recipient không thấy CloudKit invite (pain thật của CKShare) — kèm caption giải thích khi nào nên dùng. Yêu cầu kỹ thuật đi kèm: cần cơ chế phát hiện accept ở background để bắn local/push notification (liên quan fix acceptanceStatus trong memory).

**8. Localization note**: title chứa tên riêng tiếng Việt ("Hoàng Nam") — format string với placeholder, không nối chuỗi.

---

## 10g · About (push) — "How your data is protected"

**1. Mục đích + flow**: Màn About ngắn gọn kỹ thuật (phiên bản compact — so sánh với đợt 13 là bản storytelling dài). Push từ Settings.

**2. Layout**:
1. Header push: back chevron tròn.
2. Hero căn giữa: logo Loox (wordmark, cao 26px) + caption **"Version 2.4.1 (1088)"**.
3. Section label **"HOW YOUR DATA IS PROTECTED"** → card 4 row, mỗi row = icon màu riêng trong ô 34×34 + 1 câu:
   - 🔒 (ổ khoá, xanh accent): **"Everything is encrypted _on this iPhone_ before it's stored."**
   - ⊘ (vòng gạch chéo, teal): **"No servers, no accounts, no telemetry. Zero backend."**
   - 🔑 (chìa khoá, tím): **"Keys derived with _Argon2id_, sealed with _AES-256-GCM_."**
   - 🛡 (khiên check, xanh lá): **"You hold the only keys — Master Password + Emergency Kit."**
4. Card đơn: row **"Privacy Policy"** + chevron phải.
5. Footer căn giữa xám nhạt: **"Made with care · Hà Nội, 2026"**.

**3. Copy (EN)**: đầy đủ như trên (4 câu là copy chốt, mỗi câu 1 ý; phần in đậm trong mock: "on this iPhone", "Argon2id", "AES-256-GCM").

**4. Trạng thái**: Tĩnh, không biến thể. Version string lấy runtime.

**5. Tương tác**: Privacy Policy → push/web. (Có thể thêm: tap version 5 lần → debug info, không có trong mock.)

**6. Ghi chú VI**: *"About — cách dữ liệu được bảo vệ"*. Cuối turn: *"Bộ mock hoàn chỉnh — 10 đợt, phủ trọn feature map."*

**7. Insight**: Trình bày security posture bằng **4 câu một-dòng có icon màu**, không đoạn văn — mỗi claim đúng kiến trúc Vaultify thật (Argon2id + AES-256-GCM: lưu ý code hiện dùng ChaCha20-Poly1305 ở vài chỗ — verify lại wording trước khi ship, đừng ghi sai thuật toán). Đây là bản "ngắn"; đợt 13 thay thế/mở rộng thành About Us storytelling — quyết định chọn 1 hoặc gộp (10g = tab "technical", 13 = "story") thuộc về plan.

---

# Đợt 13 · About Us — 1 màn CUỘN DÀI, 3 khung xem (13a → 13b → 13c)

Ghi chú VI của designer (nguyên văn, cuối turn): *"Vào app từ Settings → About. Thứ tự cuộn: 13a → 13b → 13c. Tên/vai trò đội ngũ là placeholder — gửi mình danh sách thật để thay."*
→ Đây KHÔNG phải 3 màn riêng: 1 ScrollView duy nhất, 3 viewport chụp 3 đoạn. Push từ Settings → About.

## 13a · Phần mở — câu hỏi khơi gợi + "lời từ chối định vị"

**1. Mục đích**: Hook cảm xúc mở đầu trang About Us; định vị sản phẩm bằng cách "từ chối" các thứ ngành này bắt user chấp nhận.

**2. Layout**:
1. Header push: back chevron tròn trắng blur (duy nhất, sticky theo màn).
2. **Hero**: logo Loox nhỏ (22px) căn trái → headline 30px extra-bold 2 dòng:
   - Dòng 1 (đen): **"Your passwords guard everything."**
   - Dòng 2 (gradient xanh `#1544FD → #20BDFD`): **"Who guards them?"**
   - Sub body xám: **"Every account you own — your money, your photos, your conversations — hangs on a handful of passwords. We think the thing that holds them should answer to _you_, and no one else."** (đậm: "you").
3. **Khối "refusal"** — card nền ĐEN `#17181C` bo 24px (đảo màu duy nhất trong trang):
   - Eyebrow uppercase màu cyan `#20BDFD`, tracking rộng: **"WHY WE BUILT LOOX"**
   - Đoạn chính 17px semibold trắng: **"We didn't invent a new need. We took one of the oldest needs on the internet — keeping secrets — and made it _10× better_."** ("10× better" màu cyan).
   - Đoạn phụ xám nhạt: **"No accounts to create. No servers holding your vault. No subscription holding your data hostage. Just your iPhone, your keys, your secrets."**
4. **Scroll cue** căn giữa: caption **"Our three promises"** + chevron xuống.

**3. Copy (EN) — ĐẦY ĐỦ**: toàn bộ như mục 2 (đã trích nguyên văn từng câu).

**4. Trạng thái**: tĩnh. Gradient text + dark card cần render đúng cả light/dark theme (dark card giữ nguyên đen ở cả 2 mode — nó là "ink block" chủ đích).

**5. Tương tác**: chỉ scroll. Scroll cue có thể animate nhẹ (tôn trọng Reduce Motion).

**6. Ghi chú VI**: option label: *"About Us — phần mở: câu hỏi khơi gợi → lời từ chối định vị"*; tên turn: *"kể chuyện 'một nhu cầu cũ, làm tốt hơn 10 lần'"*.

**7. Insight**: Cấu trúc storytelling: question hook → thesis ("answer to you") → refusal block liệt kê 3 cái KHÔNG (accounts/servers/subscription) → cue dẫn xuống. Khối đen làm "đoạn nhấn" giữa trang sáng — kỹ thuật editorial đáng giữ khi port SwiftUI.

## 13b · 3 lời hứa đánh số + chữ ký đội ngũ + CTA

**1. Mục đích**: Thân trang — 3 promise = 3 trụ giá trị, chốt bằng chữ ký nhân bản hoá + CTA sang trang giải thích mã hoá.

**2. Layout**:
1. **Promise cards** ×3, card trắng bo 22px, mỗi card: số thứ tự 34px extra-bold màu accent-nhạt (1=xanh 18%, 2=teal 22%, 3=tím 20%) + title 16.5px bold + body 13.5px xám:
   - **1 · "Your device is the vault"** — body: **"Everything is sealed with `AES-256` before it touches storage. If it ever leaves your iPhone — to iCloud, to another device — it leaves _already locked_. We couldn't read it if we wanted to. Nobody can."** (`AES-256` monospace).
   - **2 · "Trust is verified, never assumed"** — body: **"Share a password, pair a device, open on a computer — every handover makes both sides _compare a code out loud_ before anything moves. A little ceremony, on purpose. Secrets deserve it."**
   - **3 · "You can always walk away"** — body: **"Export everything, anytime, in formats other apps read. Your Emergency Kit recovers your vault without us. A lock that only locks _in_ is a cage — Loox is a door, and _you hold the key_."**
2. **Chữ ký**: text căn giữa **"Made by a small team that got tired of / trusting strangers with their secrets."** (2 dòng) → divider ngang 2 bên + **logo mark Loox gradient** (SVG infinity-knot) ở giữa → caption **"Hà Nội · since 2025"**.
3. **CTA** pill trắng chữ accent: **"Read how encryption works →"**.
4. Footer caption: **"Version 2.4.1 · Privacy Policy · Licenses"** (3 mục — Privacy Policy/Licenses là link).

**3. Copy (EN)**: đầy đủ như trên — nguyên văn.

**4. Trạng thái**: tĩnh; version runtime.

**5. Tương tác**: CTA → màn/anchor "How encryption works" (có thể tái dùng nội dung 10g hoặc trang riêng); Privacy Policy, Licenses → push.

**6. Ghi chú VI**: *"About Us — cuộn tiếp: 3 lời hứa đánh số → chữ ký đội ngũ"*.

**7. Insight**: (a) Promise #2 chính là SAS code-compare ceremony (Quick View handoff / device pairing / share) được nâng thành GIÁ TRỊ THƯƠNG HIỆU — "a little ceremony, on purpose" là copy đắt, nên tái dùng trong chính các màn compare-code; (b) Promise #3 (export + Emergency Kit độc lập) = anti-lock-in claim, đúng tính năng thật; (c) số đánh số màu nhạt lớn = hệ nhận diện xuyên suốt (mỗi promise 1 hue: xanh/teal/tím — trùng hue hệ icon 10g).

## 13c · Origin story timeline + team + email

**1. Mục đích**: Kết trang — câu chuyện khởi nguồn (timeline 3 mốc) + con người đứng sau + kênh liên hệ trực tiếp.

**2. Layout**:
1. Eyebrow uppercase accent: **"HOW IT STARTED"** → card trắng chứa **timeline dọc** 3 mốc (dot màu + đường nối nhạt; mỗi mốc: label năm màu riêng + đoạn văn):
   - Dot xanh accent — **"2024 · one bad night"**: **"A password manager we trusted got breached. Our vaults were "safe" — but the metadata wasn't, and the trust was gone. We asked: _why does keeping a secret require trusting a stranger's server at all?_"**
   - Dot teal — **"2025 · the bet"**: **"Three of us quit our jobs and bet on one idea: a vault that _works fully offline_, syncs only ciphertext through iCloud, and never asks you to open an account. If we can't see your data, we can't lose it."**
   - Dot xanh lá — **"2026 · today"**: **"Loox guards vaults on thousands of iPhones. Still no servers. Still no accounts. Still nothing to breach."**
2. Eyebrow **"THE PEOPLE BEHIND IT"** → card list 3 người (avatar tròn 46px gradient + initials, tên bold, mô tả 1 dòng):
   - **TL · Tuấn Linh** — "Founder · cryptography — writes the code that seals your vault" (gradient xanh)
   - **ML · Mai Lan** — "Design — believes security should feel calm, not scary" (gradient teal)
   - **QH · Quang Huy** — "iOS engineering — makes it feel native down to the last haptic" (gradient tím)
3. Footer căn giữa: **"We answer every email ourselves."** + dòng email accent semibold: **"hello@loox.app"**.

**3. Copy (EN)**: đầy đủ nguyên văn như trên.

**4. Trạng thái**: tĩnh. **Team là PLACEHOLDER** — designer ghi rõ: *"Tên/vai trò đội ngũ là placeholder — gửi mình danh sách thật để thay."* KHÔNG ship tên giả.

**5. Tương tác**: tap email → mở Mail compose. Timeline/team không tương tác.

**6. Ghi chú VI**: *"About Us — cuộn tiếp: chuyện bắt đầu (timeline) + những người đứng sau"* + note placeholder ở trên.

**7. Insight**: (a) Arc kể chuyện breach-của-đối-thủ → bet zero-backend → hiện tại, mỗi mốc chốt bằng 1 câu thesis lặp ("nothing to breach" echo "no servers"); (b) tagline kỹ thuật giấu trong prose: "syncs only ciphertext through iCloud" — đúng kiến trúc thật, dùng lại được cho marketing; (c) role description viết theo giá trị chứ không chức danh khô ("believes security should feel calm, not scary"); (d) "We answer every email ourselves" — điểm chạm nhân bản kết trang.

---

## Tổng hợp cho dev SwiftUI

- **Container mapping**: 10a/10b/10c/10f = sheet (detent theo nội dung); 10d/10e/10g/13 = push child. About Us (13) = 1 `ScrollView` duy nhất.
- **Quan hệ 10g vs t13**: 2 phương án About — 10g compact technical vs 13 storytelling. Note cuối t13 "Vào app từ Settings → About" gợi ý t13 là bản chốt cho About Us; "Read how encryption works →" (13b) có thể trỏ về nội dung 10g. Cần plan quyết định.
- **Feature mới cần ADR**: Extra Protection (10c — key derivation riêng, không recover bằng Emergency Kit, tương tác với sync/share); Auto Dark "Below a brightness level" (10d — feasibility iOS); Nudge via Messages (10f — MSMessages/share-sheet); alias pause/resume (10e — backend loox.email).
- **Localization**: mọi copy trên phải vào `Localizable.xcstrings` EN+VI; string có placeholder ({name}, {item}, version) dùng format string.
- **Copy chuẩn xác kỹ thuật cần verify trước ship**: "AES-256-GCM" (10g) vs "AES-256" (13b) vs cipher thực tế trong code; "thousands of iPhones" (13c) là claim marketing.
- **Đừng ship placeholder**: tên team 13c, số version, dữ liệu mẫu (minh.anh, Hoàng Nam, shopee...).

## Unresolved questions
1. 10g và t13 cùng là "About" — chọn 1, gộp, hay 10g thành trang "How encryption works" mà 13b CTA trỏ tới?
2. Extra Protection: scope crypto (per-field key? sealed thế nào? có sync field bị protect không?) — mock chỉ vẽ UI setup.
3. "Below a brightness level" có giữ không (không có public ambient-light API)?
4. Passkey detail: biến thể "Not backed up" trông thế nào (mock chỉ có Backed up)?
5. Alias Pause: trạng thái Paused + Resume chưa được vẽ.
