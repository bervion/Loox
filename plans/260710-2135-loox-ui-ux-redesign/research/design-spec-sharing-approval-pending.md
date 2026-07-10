# Design Spec — Sharing / Approval / Share Pending (Đợt 4 + Đợt 12)

Nguồn: web-mockup HTML (inline styles, frame iPhone 402×874)
- `t4.html` — "Đợt 4 — Sharing · Approval (máy trạng thái 9 bước, rút về 6 màn chốt)" — 6 màn: 4a…4f
- `t12.html` — "Đợt 12 — Share đang chờ: đóng app vẫn thấy pending ở Home · Item Detail · sheet resume có stepper" — 3 màn: 12a…12c

Mục đích: spec FLOW + information architecture + copy để hoàn thiện Approval Mode sharing hiện có (CloudKit CKShare) trong app SwiftUI. KHÔNG port pixel CSS. Màu/px chỉ ghi khi mang ngữ nghĩa (semantic status color).

---

## 0. Tổng quan máy trạng thái share (suy ra từ 2 đợt)

Designer note (title Đợt 4, nguyên văn): **"máy trạng thái 9 bước, rút về 6 màn chốt"** — tức backend/protocol có 9 state, nhưng UI chỉ expose 6 màn chốt (4a choose → 4b config → [invite sent/waiting — KHÔNG có màn riêng, thể hiện qua pending rows Đợt 12] → 4c activate/safety-code → 4d approval request runtime → 4e quick-link result → 4f notifications hub). Không có màn "Waiting/Failed" riêng ở Đợt 4 — designer để mở: *"xem bước Waiting/Failed của share"* là gợi ý đợt sau, và Đợt 12 chính là câu trả lời cho Waiting.

Stepper 4 bước user-facing (canonical, từ màn 12c) — đây là trục chính của state machine phía owner:

1. **Invite sent** (via iCloud)
2. **Waiting for them to accept**
3. **Confirm safety code together** (= màn 4c)
4. **Access active** (revoke anytime)

Map sang flow màn hình:

```
Item Detail / Share entry
  → 4a Share — Choose (Quick Link | Loox user)
      ├─ Quick Link → [config field-pick] → 4e Link ready (one-time) → Done
      └─ Loox user → 4b Config (recipient + field permissions + device policy)
             → "Create Share" → invite sent (step 1)
             → SHEET CÓ THỂ ĐÓNG — trạng thái pending nổi ở:
                  · 12a Home row "Sharing 'GitHub' · waiting for Hoàng Nam"
                  · 12a badge SHARING… trên item row
                  · 12b Item Detail → section "Shared with" (Invite sent · waiting)
                  · 4f Notifications → "Shares you sent" (Ready to confirm — tap to resume)
             → tap bất kỳ điểm nào ở trên → 12c Resume sheet (stepper 4 bước)
             → recipient accept (step 2 done) → 4c Ready to activate (step 3, safety code)
             → "Activate Sharing" → Active (step 4)
Runtime sau khi Active:
  recipient bấm field "Ask each time" (vd One-time code)
      → owner nhận 4d Approval Request (match code + Approve with Face ID / Reject)
Tất cả sự kiện đổ về 4f Notifications (recipient: invitation Accept/Not Now; owner: approval request, resume, recent log).
```

Insight then chốt: **không bắt owner ngồi đợi trong sheet** — mọi bước async (waiting accept) đều thoát ra được, trạng thái persist, resume từ 4+ entry point.

---

## 1. Màn 4a — Share — Choose (`data-screen-label="Share — Choose"`)

### Mục đích & vị trí state machine
Bước 0/entry của flow share: chọn "kênh vận chuyển" cho item. Được present dạng **bottom sheet** (sheet cao ~65% màn, top:300px, nền sau mờ xám) từ Item Detail (nút Share this item / menu). Đi tiếp: tap Quick Link → nhánh quick-link (config field → 4e); tap "Share with a Loox user" → 4b.

### Layout (trên → dưới)
1. Grabber (thanh kéo sheet).
2. Header sheet: nút **X đóng** (tròn, trái) + title giữa **Share "GitHub"** (tên item động).
3. Subtitle giữa, secondary: `How should this item travel?`
4. 2 option card trắng bo lớn, mỗi card: icon tile màu (44pt, bo 13) + title bold + mô tả 2 dòng secondary + chevron phải:
   - Card 1 — icon **quả cầu/globe teal** (#0E9BA4 nền teal 11%): **Quick Link** / `An encrypted link that opens anywhere — no app needed. Expires automatically.`
   - Card 2 — icon **khiên + check xanh accent** (#1544FD nền 9%): **Share with a Loox user** / `Approval-based access over iCloud. You stay in control, revoke anytime.`
5. Footnote giữa, tertiary: `You'll pick exactly which fields to share on the next screen.`

### Trạng thái/biến thể
Chỉ 1 state tĩnh.

### Tương tác
- X → dismiss sheet.
- Tap card → push trong sheet sang màn config tương ứng (chevron ám chỉ điều hướng, không phải toggle).

### Copy đáng chú ý
Toàn bộ ở trên. Ngôn ngữ "travel"/"handed over" — nhấn mạnh item di chuyển có kiểm soát.

### Ghi chú designer (nguyên văn)
- olabel 4a: "Share Access — bước Choose: Quick Link vs Loox user"
- title đợt: "Đợt 4 — Sharing · Approval (máy trạng thái 9 bước, rút về 6 màn chốt)"

### Insight
- Hợp nhất 2 cơ chế share (Loox-Link snapshot vs Approval Mode CKShare) vào 1 entry point duy nhất, phân biệt bằng ngôn ngữ user-benefit chứ không technical.
- Hứa "pick exactly which fields" ngay từ đầu → giảm lo lộ toàn bộ item.

---

## 2. Màn 4b — Share — Config (`data-screen-label="Share — Config"`)

### Mục đích & vị trí state machine
Bước config của nhánh Loox user: nhập recipient + phân quyền từng field + device policy → "Create Share" phát invite (bước 1 stepper). Sheet gần full-height (top:58px). Từ 4a đi tới (nút back ‹ về 4a). Sau Create Share: invite sent, sheet có thể đóng — chuyển sang trạng thái pending (Đợt 12).

### Layout (trên → dưới)
1. Grabber + header: nút **back ‹** (không phải X — đang trong navigation stack của sheet) + title **Share with a Loox user**.
2. Section label uppercase: `RECIPIENT`
   - Card trắng input: `trang.nguyen@icloud.com`
   - Footnote dưới card: `Tied to their iCloud account — no Loox account needed.`
3. Section label: `WHAT THEY CAN USE`
   - Card trắng group, các row phân cách hairline:
     - `Username` — **toggle ON** (switch iOS accent xanh)
     - `Password` — **toggle ON**
     - `One-time code` — control kiểu **menu/dropdown**, value hiện tại: `Ask each time` (kèm chevron xuống — tức picker nhiều mức, không phải toggle nhị phân; các mức khác suy đoán: Off / Always allow / Ask each time)
     - `Recovery email` — row **mờ 45%**, có icon ổ khoá, trailing text: `Not shareable` (field protected — không tương tác được)
4. Card riêng — device policy:
   - Title: `Allow use on multiple devices` — **toggle ON**
   - Subtitle: `Off = only their first device works`
5. Section label: `SHARED WITH 1`
   - Row người đã share trước đó: avatar chữ cái gradient + **Hoàng Nam** + badge pill cam: `Invite sent`
6. CTA primary pill full-width: **Create Share**

### Trạng thái/biến thể
- Per-field 3 kiểu control: toggle on/off (share tĩnh), picker "Ask each time" (field nhạy cảm → sinh approval request runtime = màn 4d), disabled "Not shareable" (protected field, vd recovery email/passkey device-bound).
- Badge trạng thái recipient trong list "Shared with": `Invite sent` (cam) — cùng hệ badge với 12b (`Active` xanh lá).

### Tương tác
- Back ‹ → về 4a. Toggles/picker per field. Tap Create Share → gửi CKShare invite, chuyển pending.
- (Màn này cũng dùng làm edit-share cho recipient hiện hữu — list "Shared with" nằm ngay đây.)

### Ghi chú designer (nguyên văn)
- olabel 4b: "Config — phân quyền từng field; field protected không chia sẻ được"

### Insight
- **Field-level permission** với 3 mức: share luôn / ask-each-time / not shareable. "Ask each time" chính là cầu nối sang máy approval runtime (4d) — khớp mô hình askEachTime trong plan shared-vault-hardening V2 hiện có.
- Recipient chỉ cần iCloud email, không cần "tài khoản Loox" — copy chủ động trấn an.
- Device policy đơn giản hoá thành 1 toggle ("first device only" = per-device seal).

---

## 3. Màn 4c — Ready to activate (`data-screen-label="Share — Activate"`)

### Mục đích & vị trí state machine
Bước 3 stepper: **Confirm safety code together**. Xuất hiện SAU khi recipient accept (bước 2 xong) — owner được đưa/resume vào màn này (từ notification "accepted", từ Resume ở 12a/12b/4f, hoặc đang mở sẵn 12c thì stepper tiến sang bước 3). Đi tiếp: "Activate Sharing" → share Active (bước 4); "The codes don't match" → nhánh huỷ/abort (an toàn trước MITM).

### Layout (trên → dưới)
Sheet ~3/4 màn (top:210px), bố cục hero căn giữa:
1. Grabber.
2. Icon hero: khiên + check accent trong tile vuông bo 22.
3. Title lớn: **Ready to activate**
4. Body: `Hoàng Nam accepted. Before anything is handed over, make sure you both see the same code.`
5. Card trắng safety code:
   - Label uppercase nhỏ: `SAFETY CODE`
   - Code **monospace** cỡ lớn (25px, tracking rộng): `7H2K-9QLM` (format XXXX-XXXX chữ+số)
6. Footnote: `Ask them to read theirs out loud.`
7. Bottom actions (cột, dính đáy):
   - CTA primary pill: **Activate Sharing**
   - Text button đỏ destructive: **The codes don't match**

### Trạng thái/biến thể
1 state; nút đỏ là exit-path lỗi (mismatch → huỷ share, không activate).

### Tương tác
- Activate Sharing → hand over key material, share → Active.
- "The codes don't match" → abort (spec đề xuất: confirm destructive rồi cancel invite).

### Copy đáng chú ý
"Before anything is handed over" — khẳng định chưa có secret nào rời máy trước khi so code. "Read theirs out loud" — hướng dẫn hành vi so code out-of-band (gọi điện/gặp mặt).

### Ghi chú designer (nguyên văn)
- olabel 4c: "Ready to activate — so khớp safety code 2 máy"

### Insight
- SAS-style verification (giống safety number Signal / SAS trong Quick View handoff plan): 2 máy cùng derive 1 code ngắn, owner xác nhận bằng mắt/tai trước khi kích hoạt. Đây là gate chống MITM trên kênh CloudKit.
- Activation là hành động **chủ động của owner**, không auto khi accept — "accept" ≠ "được cấp quyền".

---

## 4. Màn 4d — Approval Request (`data-screen-label="Approval Request"`)

### Mục đích & vị trí state machine
Máy runtime SAU khi share Active: recipient bấm dùng field cấu hình "Ask each time" (vd One-time code/2FA) → owner nhận push → mở sheet này để duyệt từng lần. Vào từ: push notification, hoặc 4f Notifications → row "Approval requests", hoặc Home row "1 approval waiting for you" (12a). Đi tiếp: Approve (Face ID) → code được release cho recipient; Reject → từ chối.

### Layout (trên → dưới)
Sheet ~2/3 màn (top:250px), hero căn giữa:
1. Grabber.
2. Icon hero: khiên + dấu chấm than accent, trong **hình tròn** (khác 4c dùng tile vuông — phân biệt "cảnh báo cần quyết định" vs "sẵn sàng").
3. Title: **Code requested**
4. Body: **Thu Trang** (bold) ` wants a 2FA code for ` **VPBank Family** (bold — tên item).
5. Card trắng match code:
   - Label uppercase: `MATCH CODE`
   - Code monospace lớn (30px, tracking 5, **màu accent xanh**): `51 342` (5 số, nhóm 2-3)
   - Footnote trong card: `It should match the code on their screen.`
6. Bottom actions:
   - CTA primary pill kèm **icon Face ID**: **Approve with Face ID**
   - Text button đỏ: **Reject**

### Trạng thái/biến thể
1 state chờ quyết định. (Timeout/expired không vẽ ở đợt này.)

### Tương tác
- Approve with Face ID → biometric gate ngay trong nút (không phải bước riêng) → release code.
- Reject → deny, đóng sheet.

### Ghi chú designer (nguyên văn)
- olabel 4d: "Approval Request (chủ sở hữu) — mã đối chiếu + Approve with Face ID"
- dv-next cuối đợt: "Tiếp theo: «làm Đợt 5: Settings + màn con» · «xem bước Waiting/Failed của share» · «chỉnh copy 4d»"

### Insight
- **Match code per-request** (khác safety code per-share ở 4c): mỗi lần xin code có mã đối chiếu ngắn hiện trên cả 2 máy → owner chắc chắn đang approve đúng request của đúng người, chống request giả/replay.
- Approve = Face ID bắt buộc (biometric-gated release), Reject không cần.
- Copy nêu rõ AI (ai xin) + cái gì (2FA code) + cho item nào — đủ context quyết định trong 2 giây.

---

## 5. Màn 4e — Quick Link result (`data-screen-label="Quick Link result"`)

### Mục đích & vị trí state machine
Màn kết quả nhánh Quick Link (sau 4a → config field quick-link): link đã tạo xong, **one-time**. Kết thúc nhánh — Done đóng sheet. Không có pending state (link sống độc lập, tự hết hạn).

### Layout (trên → dưới)
Sheet ~3/4 màn (top:230px), hero căn giữa:
1. Grabber.
2. Icon hero: **check xanh lá** trong hình tròn nền xanh lá nhạt (success).
3. Title: **Link ready**
4. Body: `Anyone with this link can see the fields you picked — nothing else.`
5. Card trắng link: icon link accent + URL monospace truncate giữa: `loox.pw/s/8fj2…mkq4`
6. Pill cảnh báo cam (icon đồng hồ): **Disappears after it's opened once**
7. Bottom actions (cột):
   - CTA primary pill: **Copy Link**
   - Nút secondary trắng chữ accent: **Share Link** (iOS share sheet)
   - Text button xám: **Done**

### Trạng thái/biến thể
1 state. Variant hết hạn xuất hiện ở 4f Recent: "Quick Link for 'Wi-Fi Guest' expired".

### Tương tác
Copy Link (primary — hành vi chính), Share Link (system share sheet), Done (dismiss).

### Ghi chú designer (nguyên văn)
- olabel 4e: "Quick Link — Link ready (one-time), nơi duy nhất key tồn tại"

### Insight
- Ghi chú "nơi duy nhất key tồn tại" → key giải mã nằm trong chính URL (fragment), server không giữ — mất màn này/không copy = mất link. Vì vậy Copy Link là primary CTA và màn không auto-dismiss.
- One-time semantics ("opened once") hiển thị bằng pill cảnh báo màu warning, không giấu trong footnote.
- Khớp hạ tầng loox.pw / Loox-Link hiện có (short URL persist không fragment — DEC đã chốt).

---

## 6. Màn 4f — Notifications (`data-screen-label="Notifications"`)

### Mục đích & vị trí state machine
Hub gom mọi sự kiện sharing 2 chiều. Full screen (không phải sheet), có nút back — push từ Home (icon chuông có badge, thấy ở 12a). Là entry point resume trung tâm: từ đây nhảy tới 4d (approval), 12c (resume share), accept invite (phía recipient).

### Layout (trên → dưới)
1. Nút back tròn (trái).
2. Large title: **Notifications**
3. Section `SHARE INVITATIONS` (phía recipient nhận):
   - Card: chấm **xanh accent** (unread) + avatar T + `Thu Trang shared "VPBank Family"` / `2 minutes ago`
   - 2 nút inline trong card: pill primary **Accept** + pill xám **Not Now**
4. Section `APPROVAL REQUESTS` (phía owner):
   - Row: chấm **xanh lá** (active/live) + icon tile khiên + `Thu Trang requests a 2FA code` / `VPBank Family · waiting` + chevron → mở 4d
5. Section `SHARES YOU SENT` (phía owner, pending):
   - Row: avatar H + `GitHub → Hoàng Nam` / `Ready to confirm — tap to resume` + badge pill accent **Resume** → mở 4c (vì đã "ready to confirm" = recipient đã accept)
6. Section `RECENT` (log, card mờ 75%):
   - `You approved a code for Thu Trang` — icon check xanh lá — `2h`
   - `Quick Link for "Wi-Fi Guest" expired` — icon đồng hồ xám — `1d`

### Trạng thái/biến thể
- Unread dot: xanh accent (invitation mới) vs xanh lá (approval đang chờ — live).
- Row "Shares you sent" đổi subtitle theo state: mockup này là "Ready to confirm — tap to resume" (bước 3); khi còn bước 2 sẽ là dạng "waiting" (xem 12a).
- Recent = lịch sử passive, opacity thấp, không action.

### Tương tác
- Accept → recipient join CKShare (bước 2 phía owner tiến lên). **Not Now** — không phải Decline: hoãn, invite còn nguyên (khớp invite expiry 6 ngày ở 12c).
- Approval row → 4d. Resume → 4c/12c tuỳ state. Recent: không tap.

### Ghi chú designer (nguyên văn)
- olabel 4f: "Notifications — lời mời, yêu cầu phê duyệt, share đã gửi"

### Insight
- 1 hub 4 section phân theo VAI TRÒ + THÌ (việc người khác chờ mình / việc mình chờ người khác / lịch sử) — giải bài toán "owner stuck on Waiting" hiện tại: luôn có nơi nhìn thấy và resume share đang treo.
- "Not Now" thay "Decline" — giảm áp lực quyết định, đúng semantics invite có TTL.

---

## 7. Màn 12a — Home với share pending (`data-screen-label="Home — share pending"`)

### Mục đích & vị trí state machine
Home tab khi có ≥1 share đang pending (bước 1–3 chưa xong): trạng thái share nổi lên **level cao nhất của app** dù đã đóng sheet/kill app. Tap row → 12c resume sheet.

### Layout (trên → dưới)
1. Header Home: logo Loox (trái) + cụm 3 nút phải: **chuông có badge đỏ "1"**, nút **+** accent, nút scan/settings.
2. **Row "Share in progress"** (card trắng, ngay dưới header, TRÊN mọi list):
   - Chấm **cam** (#E9A13B — pending/in-progress) + text 1 dòng truncate: **Sharing "GitHub"** (bold) ` · waiting for Hoàng Nam` (secondary) + chevron.
3. Row approval (đặt cạnh để đối chiếu màu): chấm **xanh lá** + icon khiên + `1 approval waiting for you` + chevron.
4. Section list thường: `Personal · 24 items ⌄`
   - Item row **GitHub**: monogram G + tên + **badge "SHARING…"** (pill nhỏ nền cam nhạt, icon đồng hồ, chữ cam uppercase 10px) + subtitle `minh.anh` + sao favorite.
   - Item row Vietcombank (bình thường, không badge).
5. Caption chú thích của designer (giữa, tertiary): `Row pending tự biến mất khi share Active hoặc bị huỷ.`
6. Tab bar nổi + nút search tròn riêng.

### Trạng thái/biến thể
- Hệ màu status dot: **cam = share mình gửi đang chờ người khác** / **xanh lá = việc đang chờ MÌNH xử lý** — nhất quán với 4f, 12b, 12c.
- Badge item-level `SHARING…` trên row GitHub: item đang có share pending, hiện ngay trong list.
- Row pending là **ephemeral**: tự remove khi share → Active hoặc cancelled.

### Tương tác
- Tap row Sharing → 12c. Tap row approval → 4d (hoặc list). Chuông → 4f.

### Ghi chú designer (nguyên văn)
- olabel 12a: "Home — row 'Share in progress' nổi lên cạnh approval, tap để resume"
- caption trong màn: "Row pending tự biến mất khi share Active hoặc bị huỷ."
- title đợt 12: "Đợt 12 — Share đang chờ: đóng app vẫn thấy pending ở Home · Item Detail · sheet resume có stepper"

### Insight
- **Persistence xuyên app lifecycle**: pending share = first-class object, không phải trạng thái tạm của 1 sheet. Đóng app vẫn thấy ở Home.
- Phân biệt ngữ nghĩa 2 hàng chờ bằng màu: cam (chờ họ) vs xanh lá (chờ mình) → user scan được ưu tiên ngay.

---

## 8. Màn 12b — Item Detail, share pending (`data-screen-label="Detail — share pending"`)

### Mục đích & vị trí state machine
Item Detail của item đang share: section "Shared with" là source-of-truth per-item về mọi recipient và state của họ. Resume từ đây → 12c. Cũng là nơi quản trị (cancel invite, xem recipient Active).

### Layout (trên → dưới)
1. Header: back tròn + nút ••• (menu).
2. Item header: monogram G lớn (56pt, bo 16) + **GitHub** + subtitle `Login`.
3. Section label `SHARED WITH`, card trắng group:
   - **Row recipient PENDING (Hoàng Nam)**:
     - avatar + tên + subtitle **màu cam**: `Invite sent · waiting to accept · 2h ago`
     - trailing: badge pill accent **Resume**
     - Dưới (thụt theo avatar): **mini progress bar 4 đoạn** — đoạn 1 **xanh lá** (done), đoạn 2 **cam** (current), đoạn 3–4 xám (todo) + caption `2 of 4 · waiting` → mirror stepper 4 bước của 12c.
   - **Row recipient ACTIVE (Thu Trang)**: avatar + tên + badge pill xanh lá **Active** + chevron (→ màn quản lý recipient/permissions).
   - **Row action**: icon + tròn accent + text accent **Share this item** (thêm recipient mới → 4a/4b).
4. Caption designer (tertiary): `Swipe người nhận pending để Cancel invite. Trạng thái này giữ nguyên qua các lần đóng/mở app.`

### Trạng thái/biến thể
- Recipient state per-row: `Invite sent · waiting to accept · Xh ago` (cam, có progress 4 đoạn + Resume) vs `Active` (xanh lá, có chevron drill-in). Suy ra các state khác (ready-to-confirm) cùng pattern: progress 3/4, subtitle đổi.
- Progress segments màu: xanh lá = done, cam = đang ở bước này, xám = chưa tới.

### Tương tác
- Resume → 12c. Row Active → chi tiết recipient. Share this item → thêm người (4a). **Swipe row pending → Cancel invite** (destructive đỏ).

### Ghi chú designer (nguyên văn)
- olabel 12b: "Item Detail — section 'Shared with' giữ trạng thái pending + Resume"
- caption: "Swipe người nhận pending để **Cancel invite**. Trạng thái này giữ nguyên qua các lần đóng/mở app."

### Insight
- Mini progress 4 đoạn ngay trong list row = glanceable stepper, không cần mở sheet mới biết đang kẹt đâu.
- Cancel invite là swipe action (ẩn khỏi UI chính, đúng convention iOS cho destructive phụ).
- Item vừa có recipient Active vừa có recipient pending song song — data model phải là danh sách participant với state độc lập.

---

## 9. Màn 12c — Share sheet resume, stepper (`data-screen-label="Share — resume stepper"`)

### Mục đích & vị trí state machine
Sheet mở lại share đang pending (từ 12a row, 12b Resume, 4f). Hiển thị stepper 4 bước — "biết ngay đang kẹt ở đâu" — kèm action đẩy tiến trình. Mockup thể hiện state **đang kẹt bước 2** (waiting accept). Khi recipient accept → nội dung tiến sang bước 3 = chính là màn 4c.

### Layout (trên → dưới)
Sheet cao (top:150px):
1. Grabber + header: nút **X** + title **Sharing "GitHub"**.
2. Subtitle giữa: `with ` **Hoàng Nam** ` · started 2h ago`
3. Card trắng — **stepper dọc 4 bước**, mỗi bước: bubble tròn 26pt trái + title + subtitle:
   - **Bước 1 (done)** — bubble xanh lá đặc, icon check trắng: **Invite sent** / `via iCloud · today 07:24`
   - **Bước 2 (current)** — bubble viền cam, icon spinner/vòng xoay cam, title **màu cam**: **Waiting for them to accept** / `They haven't opened the invitation yet. Nudge them below.`
   - **Bước 3 (todo, mờ 40%)** — bubble viền xám số "3": **Confirm safety code together** / `You'll compare a short code before anything is handed over.`
   - **Bước 4 (todo, mờ 40%)** — bubble số "4": **Access active** / `They can use what you allowed — revoke anytime.`
4. Dòng expiry (icon đồng hồ, giữa, secondary): `Invite expires in 6 days if not accepted`
5. Bottom actions:
   - CTA primary pill icon Messages: **Send Invite via Messages** (nudge — gửi lại/nhắc qua iMessage)
   - Hàng 2 nút secondary trắng: **Check Now** (chữ accent — poll CloudKit thủ công) | **Cancel Invite** (chữ đỏ — huỷ)

### Trạng thái/biến thể
- Stepper 3 visual state/bước: done (xanh lá + check) / current (cam + spinner + title cam) / todo (mờ, số thứ tự).
- Bộ action đáy đổi theo bước hiện tại: bước 2 = Nudge/Check/Cancel; bước 3 = màn 4c (Activate / codes don't match). Bước 4 đạt được thì không còn sheet pending (row biến mất — caption 12a).
- Invite TTL 6 ngày (đếm ngược, khớp CKShare invite semantics).

### Tương tác
- X → đóng, pending vẫn persist (quay lại qua 12a/12b/4f).
- Send Invite via Messages → share invite URL qua iMessage (giải bài toán recipient "chưa mở invitation").
- Check Now → refresh trạng thái accept ngay (manual poll — khớp bài toán accept-detection hiện tại của app).
- Cancel Invite → huỷ share pending.

### Ghi chú designer (nguyên văn)
- olabel 12c: "Mở lại Share sheet — stepper 4 bước, biết ngay đang kẹt ở đâu"
- dv-next cuối đợt 12: "Muốn thêm push notification khi họ accept («Hoàng Nam accepted — confirm the code») hay badge SHARING… trên row item ở mọi list?"

### Insight
- Stepper 4 bước là **văn bản chuẩn của máy trạng thái phía UI** — dev nên map state CKShare/approval nội bộ (9 bước protocol) về đúng 4 nhãn này.
- "Send Invite via Messages" + "Check Now" xử lý trực diện 2 pain point đã biết của codebase: (1) recipient không thấy invite, (2) owner không phát hiện accept (bug accept-detection plan 260708-2151 — mockup xác nhận hướng UI: cho owner nút Check Now + tự động qua push).
- Designer đề xuất thêm (dv-next): push notification khi accept ("Hoàng Nam accepted — confirm the code") và badge SHARING… ở mọi list — nên coi là part of spec.

---

## 10. Bảng ngôn ngữ trạng thái chung (dùng thống nhất)

| Semantic | Màu mockup | Dùng ở |
|---|---|---|
| Done / Active / success | xanh lá #1F9D5B | stepper done, badge Active, dot approval, icon Link ready |
| Pending / waiting (mình chờ họ) | cam #E9A13B / chữ #B87D0E | dot share-in-progress, badge Invite sent, badge SHARING…, stepper current, pill one-time warning |
| Action / accent / resume | xanh #1544FD | CTA, badge Resume, match code, toggle ON |
| Destructive / mismatch | đỏ #E5484D | Reject, Cancel Invite, codes don't match, Cancel invite swipe |
| Disabled / not shareable | opacity .45 + xám | row Recovery email |

Copy pattern lặp lại (giữ nguyên khi làm EN, dịch VI khi localize): "handed over", "revoke anytime", "waiting for them to accept", "tap to resume", "Ask each time", "Not shareable", "You stay in control".

## 11. Checklist flow-insight tổng (cho dev)

1. Share = máy trạng thái 9 bước protocol, UI expose 4 bước stepper + 6 màn chốt.
2. **Không bắt user đợi trong sheet**: mọi bước async đều đóng được; pending persist qua kill app; resume từ 4 entry (Home row, item badge/detail, Notifications, push).
3. Activation tách khỏi accept: accept xong owner vẫn phải so **safety code** rồi bấm Activate mới hand over.
4. Field-permission 3 mức: share / ask-each-time / not-shareable; ask-each-time sinh **approval request** runtime có **match code** riêng + Face ID.
5. Quick Link: one-time, key-in-URL, Copy Link là primary, không auto-dismiss.
6. Trạng thái mã màu nhất quán: cam = chờ họ, xanh lá = chờ mình/hoàn tất.
7. Nudge (Messages) + Check Now là escape hatch khi accept-detection chậm.
8. Invite TTL 6 ngày; "Not Now" thay "Decline" phía recipient.
9. Row pending tự biến mất khi Active/cancelled; Cancel invite = swipe trên recipient row (12b) hoặc nút trong resume sheet (12c).

## Unresolved questions

- 9 bước protocol cụ thể là gì — mockup không liệt kê; chỉ có 4 bước user-facing. Cần chốt mapping từ state nội bộ (CKShare + safety-code + activation + revoke) sang 4 nhãn stepper.
- Màn config field-pick của nhánh Quick Link (giữa 4a và 4e) không có trong 2 file này — có thể nằm ở đợt khác.
- Các mức của picker "Ask each time" (One-time code) chưa vẽ hết (Off/Always?).
- Flow "The codes don't match" sau khi bấm (confirm? auto-cancel?) chưa vẽ.
- Phía recipient sau Accept (màn chờ owner activate, màn nhập/so safety code phía họ) không nằm trong 2 file này.
