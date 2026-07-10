# Design Spec — Đợt 1 (Core 4 tabs) + Đợt 9 (Privacy Shield · special states · Night)

Nguồn: mockup HTML `loox-design-unpacked/turns/t1.html` + `t9.html`. Spec mô tả FLOW + cấu trúc thông tin + copy + states — KHÔNG port pixel CSS. App giữ tab bar + home header hiện tại (`MainTabView`, native `TabView`).

## 0. Hệ thống giả định của designer (khối intro Đợt 1 — trích nguyên văn)

> "Giả định & hệ thống: accent solid `#1544FD` · nền warm-gray, card trắng bo 20 · type SF Pro, số/secret dùng SF Mono · icon line 1.8pt (placeholder cho Polaris, thay sau) · tab bar liquid glass icon-only, tab Search tách pill riêng theo iOS 26 · copy EN (bản VI làm sau) · dữ liệu mẫu."

Ghi chú map sang app:
- Icon trong mock chỉ là placeholder → thay bằng Polaris SVG hiện có.
- Tab bar 4 tab: **Home / Items / Watchtower / Search** — Search là pill tròn tách riêng bên phải cụm 3 tab (giống iOS 26 `Tab(role: .search)` app đã có). Tab active = icon fill + nền accent 12%.
- Palette Day: bg `#F3F3F7`, card `#fff` radius 20, text primary `#17181C`, secondary `#6F7178`, tertiary `#A9ABB2`, accent `#1544FD`, destructive `#E5484D`, warning `#B87D0E`, success `#1F9D5B`, teal `#0E9BA4`, purple `#7451EB`.
- Palette Night (9d/9e/9f): bg `#0F1015`, card `#1B1D24` (không shadow, chỉ tách bằng màu), text `#F2F3F7`/`#9EA1AB`/`#787C88`, accent sáng hơn `#3B62FF`, accent-on-dark cho text/icon `#6E8FFF`, destructive `#FF5A60`, warning `#E9B23B`, success `#2BB56F`, teal `#14B0BA`, purple `#8A66FF`. Separator row: `rgba(255,255,255,.07)`. → nguyên tắc: **mỗi semantic token có 2 hue light/dark**, không tái dùng hue light trên nền tối (app đã có `AccentColor` light+dark hues — khớp).
- Số/TOTP/secret: monospace (SF Mono trong mock; app dùng `Font.vaultCode`).

---

## 1a · Home — dashboard (data-screen-label: "Home")

**1. Mục đích + flow**: Tab root #1, màn mở đầu sau unlock. Hub điều phối: profile switcher, quick actions, approvals, TOTP nhanh, cảnh báo bảo mật, danh sách item. Đi tới: Notifications, Add Item, Settings, Profile/Space switcher, 2FA list, Watchtower, Item detail, Search.

**2. Layout trên xuống**:
1. **Header** (floating glass): logo Loox trái · phải 3 nút tròn 38px: (a) Bell + badge đỏ số `3` (notification count), (b) nút `+` nền accent solid (Add Item — nút nổi bật nhất header), (c) nút Settings (icon gear dạng vòng tròn nét đứt).
2. **Profile row** (card trắng): avatar tròn gradient chữ cái `M` · tên `Minh Anh` · subtitle `Personal · minh.anh@icloud.com` · chevron phải. → tap mở profile/Space switcher. Subtitle cho biết Space đang active + identity email.
3. **Quick actions 2×2 grid** (4 tile màu nhạt tint, mỗi tile: icon tròn màu solid + label):
   - `Add Item` (accent blue)
   - `Generate Password` (teal)
   - `2FA Codes` (purple) + badge góc phải `6` (số mã TOTP)
   - `Watchtower` (green) + badge góc phải `14` (số issue)
4. **Approval banner** (conditional, prop `approvalPending`): card 1 dòng — chấm xanh lá (live dot) + icon shield accent + text `1 approval waiting for you` + chevron. → tap vào hàng chờ Approval Mode.
5. **Section "Authenticator Codes"** + link `View All` (accent): hàng card ngang scroll, mỗi card 150px: favicon monogram + **vòng đếm ngược TOTP tròn** (ring progress, chuyển màu cam `#E8590C` khi sắp hết chu kỳ) · mã 6 số monospace nhóm `483 921` · tên service (`GitHub`, `Google`, `Binance`) · account.
6. **Section "Needs Attention"** + count mờ `3`: card list, mỗi row: monogram + tên item + dòng lý do màu semantic (đỏ = khẩn: `Password overdue for rotation`, `Weak password`; vàng = sắp: `Rotation due in 5 days`) + nút pill `Change` (accent soft) mỗi row.
7. **Section item list theo Space**: header `Personal · 24 items` + chevron xuống (dropdown đổi Space) + icon sort (2 mũi tên lên/xuống) bên phải. Card list rows: monogram 38px + title + subtitle (username / số tài khoản masked `0021 04 88 ···` / email), row favorite có **icon sao fill accent** bên phải (GitHub).
8. Bottom fade gradient + tab bar glass (Home active).

**3. Copy đáng chú ý (EN)**: `Add Item` · `Generate Password` · `2FA Codes` · `Watchtower` · `1 approval waiting for you` · `Authenticator Codes` / `View All` · `Needs Attention` · `Password overdue for rotation` · `Weak password` · `Rotation due in 5 days` · `Change` · `Personal · 24 items`.

**4. States**: approval banner ẩn/hiện theo `approvalPending` (bool). Badge counts động (bell 3, 2FA 6, Watchtower 14). TOTP ring: màu accent bình thường → cam khi gần hết. Empty state → xem 1f.

**5. Tương tác**: tap từng khối như trên; TOTP card có thể tap-to-copy (ngụ ý bởi pattern); section Personal có dropdown Space + sort; scroll ngang dãy TOTP.

**6. Ghi chú designer**: label option: "Home — dashboard, đủ mật độ (cuộn tiếp dưới fold)". Cuối đợt: "chỉnh 1a: quick actions gọn hơn" (designer tự nhận grid 2×2 có thể còn to).

**7. Điểm đáng học**:
- Home = **dashboard hành động** chứ không phải chỉ list item: quick actions + badge số liệu ngay fold đầu.
- **TOTP carousel ngay Home** — mã 2FA là thứ cần nhanh nhất, đưa lên trước cả item list.
- **"Needs Attention" inline trên Home** với nút `Change` per-row — kéo Watchtower issue ra chỗ user nhìn hằng ngày (app hiện có rotation reminders + RotationStatus → map thẳng).
- Approval banner realtime với live dot — control-plane sharing nổi lên Home.
- Profile row gộp identity + Space đang active thành 1 điểm chạm.

---

## 1b · Items (data-screen-label: "Items")

**1. Mục đích + flow**: Tab root #2 — màn tổ chức/điều hướng vault (không phải flat list). Đi tới: từng Space, từng Category, tag-filtered list, Archive, Recently Deleted, Create Space.

**2. Layout**:
1. Header: title lớn `Items` + nút `+` accent tròn (Add Item).
2. **Section label "SPACES"** (uppercase, nhỏ, xám) — card list:
   - `Personal` (icon khoá, blue) — count `24` + chevron
   - `Work` (icon cặp táp, teal) — `12`
   - `Family` (icon 2 người, purple) — `6`
   - `Unfiled` (icon khay, gray) — `3`
   - `Shared with Me` (icon người + check, green) — `2`
   - `Create Space` (icon `+`, chữ màu accent, không count) — hàng action cuối card
3. **Section "CATEGORIES"** — card list: `Logins` 28 · `Payment Cards` 3 · `Secure Notes` 5 · `Identities` 2 (mỗi loại icon + màu riêng).
4. **Section "TAGS"** — chips wrap: `#banking 4` · `#work 7` · `#crypto 2` (dấu `#` màu accent, count mờ).
5. **Card cuối**: `Archive` 2 (icon hộp, gray) · `Recently Deleted` 1 (icon thùng rác, ĐỎ).
6. Tab bar (Items active — grid icon fill).

**3. Copy**: `Items` · `Spaces` · `Personal/Work/Family/Unfiled/Shared with Me` · `Create Space` · `Categories` · `Logins/Payment Cards/Secure Notes/Identities` · `Tags` · `Archive` · `Recently Deleted`.

**4. States**: counts động per row. Không thấy empty-state riêng trong đợt này.

**5. Tương tác**: mỗi row push list tương ứng; chip tag tap để lọc; `Create Space` mở flow tạo Space.

**6. Ghi chú designer**: "Items — tổ chức: Spaces / Categories / Tags / Archive".

**7. Điểm đáng học**:
- Tách 4 trục tổ chức **Spaces (container cứng) / Categories (loại item) / Tags (nhãn mềm) / Archive** trên cùng 1 màn — thay cho 1 list phẳng.
- `Unfiled` là Space mặc định cho item chưa phân loại; `Shared with Me` được nâng cấp thành Space ngang hàng (app đang có shared-projection → khớp).
- `Recently Deleted` icon đỏ tách khỏi `Archive` — 2 khái niệm khác nhau (ẩn vs chờ xoá vĩnh viễn).
- `Create Space` là row cuối trong chính card Spaces (inline-create pattern).

---

## 1c · Watchtower (data-screen-label: "Watchtower")

**1. Mục đích + flow**: Tab root #3 — security health. Đi tới: từng nhóm issue (Compromised/Reused/Weak/Missing 2FA) → list item lỗi → item detail/change password.

**2. Layout**:
1. Header: title `Watchtower` + nút `+` accent (đồng nhất mọi tab root).
2. **Score card**: gauge kim đồng hồ **270°, 44 tick**, tick fill chuyển màu đỏ→xanh theo tỉ lệ điểm (hue 8→140), tick chưa fill màu xám `#E8E9EF` (dark: `#2A2D37`). Giữa gauge: mũi tên tam giác màu trạng thái + **điểm số lớn** (thang 0–1200) + label uppercase màu trạng thái.
   - **Logic score (từ script mock)**: `>=1000 → "Fantastic"` xanh `#1F9D5B` · `>=750 → "Good"` xanh lá nhạt `#5FA832` · `>=450 → "Needs attention"` vàng `#B87D0E` · `<450 → "At risk"` đỏ `#E5484D`. Default demo 812.
3. Caption dưới gauge: `Fix the 14 issues below to keep your accounts safe.`
4. **Card "Overall password strength"**: label + `72%` (xanh) + **stacked bar** 4 đoạn màu (xanh đậm/xanh lá/vàng/đỏ = phân bố strong→weak, flex 56/12/22/10).
5. **Section "TO FIX"** — card list 4 nhóm, mỗi row: icon + title + subtitle + badge count màu semantic + chevron:
   - `Compromised` / `Seen in known data breaches` — badge đỏ `2`
   - `Reused` / `Same password on multiple sites` — badge vàng `4`
   - `Weak` / `Easy to guess` — badge vàng `3`
   - `Missing 2FA` / `2FA available but not set up` — badge accent `5`
6. **HIBP card**: `Check for known breaches` + toggle switch (đang ON, accent). Footnote dưới card (ngoài card, xám nhỏ): `Uses k-anonymity — only a partial hash of your password ever leaves this device.`
7. Tab bar (Watchtower active — shield fill).

**3. Copy**: như trên; các cặp title/subtitle của 4 nhóm To fix là copy chuẩn nên dùng lại.

**4. States**: gauge + label + màu đổi theo score (slider Tweaks trong mock); count 14 = tổng issue; toggle HIBP on/off (off ⇒ ẩn nhóm Compromised?— mock không chỉ rõ, cần quyết).

**5. Tương tác**: tap từng nhóm To fix → drill-down; toggle HIBP; kéo Tweaks (chỉ trong mock).

**6. Ghi chú designer**: "Watchtower — score gauge (kéo Tweaks để thử điểm), To fix, HIBP".

**7. Điểm đáng học**:
- **Score dạng điểm tuyệt đối 0–1200** (kiểu 1Password) thay vì %, kèm 4 band label — dễ gamify.
- Gauge tick-style (44 vạch) — render SwiftUI dễ (ForEach + rotation), có sẵn logic màu.
- Stacked bar phân bố strength — nhìn 1 giây biết tỉ lệ mật khẩu yếu.
- HIBP opt-in bằng toggle ngay trên màn + **giải thích k-anonymity 1 câu tại chỗ** — quan trọng với app zero-backend/privacy-first: nói rõ chỉ partial hash rời máy.
- `Missing 2FA` là nhóm riêng biệt màu accent (không phải "lỗi" đỏ/vàng) — phân biệt cơ hội cải thiện vs rủi ro.

---

## 1d · Search — kết quả (data-screen-label: "Search")

**1. Mục đích + flow**: Tab #4 (pill tách riêng). Mở tab → search field tự kích hoạt + keyboard bật sẵn (mock render keyboard). Kết quả live theo từng ký tự.

**2. Layout**:
1. Title lớn `Search`.
2. **Search field** (card trắng): icon kính lúp + text đang gõ `git` + caret accent + nút clear (×) tròn xám.
3. **Scope chips** (3 chip ngang): `Personal` (active — accent soft) · `All Spaces` · `Shared with Me`. → scope mặc định là Space hiện tại.
4. **Results card list**: mỗi row monogram + title có **highlight substring khớp** (nền accent 14% quanh chữ "Git") + subtitle ngữ cảnh:
   - `GitHub` / `minh.anh · github.com`
   - `GitLab` / `minh.anh@work.vn · gitlab.com`
   - `Git deploy keys` / `Secure Note · Work` ← kết quả cross-category (note), subtitle nêu loại + Space.
5. Không tab bar khi keyboard mở.

**3. Copy**: `Search` · chips như trên · subtitle pattern `<username> · <domain>` và `<Category> · <Space>`.

**4. States**: đang gõ + có kết quả. Empty scope → 1e.

**5. Tương tác**: gõ realtime; tap chip đổi scope; clear ×; tap row → detail.

**6. Ghi chú designer**: "Search — tự kích hoạt, scope chips, kết quả".

**7. Điểm đáng học**:
- **Scope theo Space** với chips ngay dưới field — search mặc định trong Space đang làm việc, không phải toàn vault.
- Highlight substring khớp trong title.
- Kết quả trộn category (Login + Secure Note), subtitle tự thích nghi để phân biệt.
- App đã có SearchScreen auto-activate `.searchable` → chỉ cần thêm scope chips + highlight.

---

## 1e · Search — không có kết quả trong scope (data-screen-label: "Search empty scope")

**1. Mục đích + flow**: Biến thể của 1d khi query không khớp trong Space đang scope, nhưng CÓ THỂ tồn tại nơi khác. Escape hatch 1 chạm.

**2. Layout**: Title + field (query `vietin`, không caret/keyboard) + 3 scope chips (Personal active) → giữa màn: icon kính lúp lớn trong tile xám → title `No results in Personal` → body `"vietin" isn't in this Space. It might be somewhere else in your vault.` → nút pill accent soft **`Search all Spaces`**. Tab bar hiện (Search pill active — accent tint).

**3. Copy**: nguyên văn trên — chú ý title nêu đích danh tên Space đang scope.

**4. States**: đây chính là state "empty trong scope". (Empty toàn vault không có trong đợt này.)

**5. Tương tác**: tap `Search all Spaces` → đổi scope chip sang All Spaces + re-run query ngay.

**6. Ghi chú designer**: "Search — không có kết quả trong scope, mở rộng 1 chạm".

**7. Điểm đáng học**: empty state **actionable** — không dead-end; copy nêu rõ nguyên nhân (scope) + gợi ý item "might be somewhere else", nút mở rộng scope 1 tap.

---

## 1f · Home — vault trống, first run (data-screen-label: "Home empty")

**1. Mục đích + flow**: Home lần đầu sau onboarding, 0 item. Dồn mọi thứ vào 1 CTA.

**2. Layout**: Header giữ nguyên (logo + bell KHÔNG badge + nút `+` + settings) → giữa màn: tile icon ổ khoá lớn (accent soft, radius 32) → title `Your vault is empty` → body `Add your first login, card or note. Everything is encrypted on this iPhone before it's stored.` → **nút CTA solid accent `+ Add Item`** (pill lớn, shadow accent). Tab bar đầy đủ (Home active).

**3. Copy**: nguyên văn trên. Câu body vừa hướng dẫn vừa **trust message** ("encrypted on this iPhone before it's stored" — đúng positioning offline/zero-backend).

**4. States**: first-run/empty; profile row, quick actions, các section đều ẨN (không render skeleton rỗng).

**5. Tương tác**: CTA + nút `+` header → Add Item flow.

**6. Ghi chú designer**: "Home — vault trống (first run)".

**7. Điểm đáng học**: empty Home không show dashboard rỗng; nhét value-prop bảo mật vào empty copy; liệt kê 3 loại item chính ("login, card or note") để gợi ý.

---

## 9a · Privacy Shield (data-screen-label: "Privacy Shield")

**1. Mục đích + flow**: Overlay phủ toàn màn khi app vào App Switcher / resign active. Không phải màn điều hướng — auto hiện/ẩn theo lifecycle.

**2. Layout**: Nội dung Home phía sau bị **blur 9px + opacity .7** (chỉ là skeleton block trong mock) → phủ full-screen layer `backdrop-blur(26px) saturate(160%)` + tint nền 55% → giữa: **logo mark Loox** trong tile trắng 96px radius 27 (shadow accent mềm) → caption `Contents hidden` (xám, nhỏ).

**3. Copy**: `Contents hidden`.

**4. States**: chỉ 1 state; theme-aware (mock là Day).

**5. Tương tác**: không có — tự gỡ khi app active lại (rồi tuỳ autoLock timer quyết định lock hay không, theo Lock UX hiện có).

**6. Ghi chú designer**: "Privacy Shield — phủ khi vào App Switcher".

**7. Điểm đáng học**: hai lớp che (blur content + branded overlay) thay vì chỉ black-out; có caption text rõ nghĩa; snapshot trong App Switcher thành brand card đẹp thay vì màn hình lộ dữ liệu.

---

## 9b · SharedAccessGate — offline (data-screen-label: "Shared gate — offline")

**1. Mục đích + flow**: User mở 1 shared item (từ Shared with Me) khi offline. Vì shared item cần verify access online (Approval Mode / control plane), gate chặn TRƯỚC khi render bất kỳ secret nào. Vào từ: shared item row. Ra: back, hoặc tự vào detail khi online lại.

**2. Layout**:
1. Nav: nút back tròn glass (không title giữa).
2. **Item header** (hiện metadata KHÔNG nhạy cảm): monogram `V` lớn 56px (green) + title `VPBank Family` + subtitle `Login · from Thu Trang` (loại item + người chia sẻ).
3. **Gate card** (trắng, padding lớn, căn giữa): icon **wifi-slash** (wifi xám + gạch chéo đỏ) trong tile xám → title `You're offline` → body `You need an internet connection to view this shared item. Its secrets stay sealed until access is verified.` → nút pill accent soft `Try Again`.
4. Footnote dưới card: `Re-checks automatically when the connection returns.`

**3. Copy**: nguyên văn trên. "Its secrets stay sealed until access is verified" = câu chốt security model.

**4. States**: offline (màn này). Ngụ ý các state anh em: online-verifying, denied, revoked (không thuộc đợt này). Tự retry khi có mạng (footnote) — cần network monitor.

**5. Tương tác**: `Try Again` (manual re-check) · back · auto re-check.

**6. Ghi chú designer**: "SharedAccessGate — offline, **secret không bao giờ render trước cổng**" (nguyên văn label).

**7. Điểm đáng học**:
- Nguyên tắc cứng: **metadata (tên, loại, người share) được hiện — secret tuyệt đối không render trước khi gate pass**. Map thẳng vào sealed snapshot/participant escrow hiện có.
- Cung cấp cả manual retry lẫn auto retry, và NÓI cho user biết sẽ tự retry.
- Copy giải thích "vì sao cần mạng" cho app vốn offline-first — tránh user hoang mang.

---

## 9c · Approval — issuing, chờ chu kỳ TOTP mới (data-screen-label: "Approval — issuing")

**1. Mục đích + flow**: Sheet (bottom sheet có grabber, nền sau mờ tối) phía OWNER sau khi bấm approve một yêu cầu xin mã TOTP: thay vì gửi ngay mã hiện tại (có thể chỉ còn vài giây sống), app đợi chu kỳ 30s kế tiếp rồi mới phát mã.

**2. Layout** (bottom sheet ~2/3 màn):
1. Grabber.
2. Giữa: **spinner arc accent** (vòng cung hở, ngụ ý quay) → title `Preparing a fresh verification code…` → body `Loox waits for the next 30-second window so Thu Trang gets a full-life code. The old one is never sent.`
3. **Countdown pill** (nền trắng): ring TOTP nhỏ màu cam (gần cạn — dashoffset 47/53.4) + text `New window in 4s`.
4. Footer caption: `This sheet stays open while the code is being issued.`

**3. Copy**: nguyên văn trên — chú ý cá nhân hoá tên người nhận ("so Thu Trang gets a full-life code") và câu "The old one is never sent."

**4. States**: issuing/countdown (màn này) → ngụ ý state kế: đã phát mã (không thuộc đợt này). Countdown `4s` động theo chu kỳ TOTP thật.

**5. Tương tác**: không có action — sheet non-dismissable về mặt logic (caption nói sheet tự giữ mở). Chờ hết countdown thì chuyển state.

**6. Ghi chú designer**: "Approval — chờ chu kỳ TOTP mới, **không gửi trước mã cũ**" (nguyên văn label).

**7. Điểm đáng học**:
- **UX hoá một quyết định kỹ thuật**: full-life TOTP cho recipient — biến độ trễ 0–30s thành trải nghiệm minh bạch có countdown thay vì loading câm. Rất hợp ApprovalSession/TOTP hiện có của app.
- Copy nói lý do ("full-life code") + cam kết ("old one is never sent") ngay trong sheet.
- Ring countdown tái dùng đúng visual TOTP ring ở Home → ngôn ngữ nhất quán.

---

## 9d · Home — Night (data-screen-label: "Home — Night")

**1. Mục đích + flow**: Cùng IA với 1a, chứng minh token light/dark. Khác biệt nội dung: logo đổi thành logomark SVG gradient (`#3B62FF→#20BDFD`), KHÔNG có approval banner và Needs Attention trong bản này (rút gọn demo), section Personal không icon sort.

**2. Token mapping (điểm chính của màn)**:
- bg `#F3F3F7 → #0F1015`; card `#fff → #1B1D24` và **bỏ shadow** (dark tách lớp bằng màu).
- Accent: solid `#1544FD → #3B62FF` (nút +, toggle…); **text/icon accent dùng hue riêng sáng hơn `#6E8FFF`** (link View All, sao favorite, tab active) — 2 hue accent khác nhau cho fill vs text trên dark.
- Accent-soft tile: `rgba(21,68,253,.09) → rgba(75,116,255,.13)` (tăng alpha trên dark).
- Semantic: đỏ `#FF5A60`, vàng/amber `#E9B23B`, xanh `#2BB56F`, teal `#14B0BA`, tím `#8A66FF`, cam TOTP `#F0741F`.
- Badge bell border đổi theo bg (`border:2px solid #0F1015`).
- TOTP ring track `#E7E8EF → #2A2D37`; monogram neutral bg `rgba(23,24,28,.08) → rgba(242,243,247,.1)`.
- Tab bar glass: `rgba(251,251,253,.72) → rgba(30,32,40,.72)`; active tint `rgba(110,143,255,.18)`.
- Bottom fade gradient theo bg đêm.

**3–5**: copy/states/tương tác = 1a.

**6. Ghi chú designer**: "Home — theme Night (token màu chuyển hệ tối)".

**7. Điểm đáng học**: dark không phải invert — **mỗi màu chức năng có hue dark riêng, sáng + bão hoà hơn**; alpha của soft-tint tăng nhẹ; bỏ shadow trên dark. App đã có `AppTheme` + derived tokens → cần đối chiếu palette Night này khi retune.

---

## 9e · Watchtower — Night (data-screen-label: "Watchtower — Night")

**1. Mục đích + flow**: 1c bản Night, "gauge cùng dữ liệu với 1c" (label). Bản rút gọn demo: To fix chỉ còn 3 row (Compromised/Reused/Missing 2FA — bỏ Weak), không có HIBP card.

**2. Token mapping thêm ngoài 9d**: gauge tick chưa fill `#2A2D37`; tick fill cùng công thức hue nhưng lightness 48% (thay 42%) cho dark; strength bar dùng bộ màu Night (`#2BB56F/#7BB93F/#E9B23B/#FF5A60`); `72%` màu `#2BB56F`; badge count bg alpha ~.13–.14 trên dark.

**3–5**: = 1c.

**6. Ghi chú designer**: "Watchtower — Night, gauge cùng dữ liệu với 1c".

**7. Điểm đáng học**: gauge dark chỉ đổi 2 tham số (unfilled color + lightness fill) — thiết kế gauge nên tham số hoá theo theme ngay từ đầu.

---

## 9f · Lock Screen — Night (data-screen-label: "Lock — Night")

**1. Mục đích + flow**: Màn khoá vault (cold launch / auto-lock) theme Night. Ra: unlock thành công → Home; fallback → nhập Master Password.

**2. Layout**:
1. Nền: `#0F1015` + **radial glow** rất nhẹ phía trên (tint cyan/blue 5–10%) — tạo chiều sâu, không phải wallpaper.
2. Giữa màn: **app icon tile** 112px radius 30 (card dark, shadow glow accent) chứa logomark gradient · góc dưới-phải tile: **badge Face ID tròn accent 44px** (viền 3.5px màu nền tạo hiệu ứng đục lỗ).
3. Title `Unlock your vault`.
4. **Status pill** (card dark): spinner arc nhỏ accent + `Checking Face ID…` (xám).
5. Đáy màn: link `Use Master Password instead` (màu accent text `#6E8FFF`).

**3. Copy**: `Unlock your vault` · `Checking Face ID…` · `Use Master Password instead`.

**4. States**: đang check Face ID (spinner). Ngụ ý các state khác: idle/failed/slide-to-unlock (app hiện có deliberate-lock cần slide trước Face ID — mock không phủ nhận, chỉ show state checking).

**5. Tương tác**: tap `Use Master Password instead` → password entry; Face ID tự chạy.

**6. Ghi chú designer**: "Lock Screen — Night".

**7. Điểm đáng học**: lock screen tối giản brand-first — icon + badge Face ID gắn vào icon (chỉ rõ phương thức unlock hiện hành); status dạng pill text thay vì alert; fallback Master Password luôn hiện sẵn ở đáy, không giấu sau lần fail.

---

## Ghi chú chung của designer (cuối 2 file, nguyên văn)

- Cuối Đợt 1: "Tiếp theo: «làm Đợt 2: Item Detail + Editor» · «chỉnh 1a: quick actions gọn hơn» · «cho xem bản Night của 1c»"
- Cuối Đợt 9: "Bộ mock giờ phủ trọn feature map + Night sample. Tiếp được: «Night cho các màn còn lại» · «export PNG từng màn» · «handoff cho dev»."

## Tổng hợp pattern xuyên suốt (cheat-sheet cho dev)

1. **Nút `+` accent tròn 38px** xuất hiện trên MỌI tab root header (Home/Items/Watchtower) — global Add Item.
2. **Card list** = container trắng radius 20, rows 11×14 padding, separator .5px, chevron xám; **row anatomy**: leading icon/monogram 34–38px radius 10–11 tint màu loại + title 15–15.5 semibold + subtitle 12.5–13 secondary + trailing (count/badge/chevron/star/button).
3. **Section label** uppercase 13px semibold xám, xuất hiện trước card (Spaces/Categories/Tags/To fix).
4. **Badge count màu semantic** (đỏ/vàng/accent, nền alpha ~.10–.16) — dùng nhất quán Home quick-actions, Watchtower, bell.
5. **Pill button** 2 cấp: solid accent (CTA chính) vs accent-soft (secondary: Change, Try Again, Search all Spaces).
6. **TOTP ring** = ngôn ngữ đếm ngược thống nhất (Home carousel, Approval countdown), chuyển cam khi sắp hết.
7. **Empty/blocked states luôn actionable**: icon tile + title + body giải thích lý do + 1 nút thoát (Add Item / Search all Spaces / Try Again).
8. **Copy chứa trust/security messaging tại chỗ**: k-anonymity (Watchtower), encrypted-on-device (empty Home), secrets-stay-sealed (gate), old-code-never-sent (approval).
9. Monogram chữ cái + màu brand thay favicon thật ở mock — app có favicon service, dùng monogram làm fallback.

## Unresolved questions

1. HIBP toggle OFF thì nhóm `Compromised` biến mất hay hiện disabled? Mock không chỉ rõ.
2. Công thức tính score 0–1200 (trọng số per issue) không có trong mock — cần define (mock chỉ có band: ≥1000 Fantastic / ≥750 Good / ≥450 Needs attention / <450 At risk).
3. Bell notification (badge 3) dẫn tới màn nào — Notification center chưa xuất hiện trong 2 đợt này.
4. Icon sort trên section Personal (1a): các sort option cụ thể chưa spec.
5. Tab bar mock là custom glass pill — CLAUDE.md yêu cầu GIỮ native TabView; chỉ lấy IA 4 tab (Home/Items/Watchtower/Search) + active tint, không port shell custom.
6. 9d/9e lược bớt section (approval banner, Needs Attention, Weak, HIBP) — coi là rút gọn demo, KHÔNG phải khác biệt theme.
