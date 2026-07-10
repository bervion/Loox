# Design Spec — Onboarding · Lock Screen · Personas · Space Editor

Nguồn: mockup HTML `loox-design-unpacked/turns/t3.html` (Đợt 3) + `t8.html` (Đợt 8).
Mục tiêu: spec flow/IA/copy/state cho dev SwiftUI — KHÔNG port pixel CSS. Màu/size chỉ ghi để hiểu ngữ nghĩa (accent = brand blue `#1544FD`, success green `#1F9D5B`, destructive red `#E5484D`, warning amber `#B87D0E`, purple `#7451EB`, teal `#0E9BA4`). Map sang token app: accent, success, warning, destructive, textPrimary, textSecondary.

## Thứ tự flow onboarding tổng hợp (ghép Đợt 3 + Đợt 8)

```
3a Welcome → 3b Create Master Password → 3c Emergency Kit (bắt buộc lưu)
→ 8a Name step (tạo Identity mặc định) → 8b Choose Theme → 8c Enable Face ID (chỉ khi máy có biometric)
→ 8d Done → vào app
```
Lock screens (3d/3e/3f) là runtime, không thuộc onboarding. Personas (8e) + Space editor (8f) là màn in-app.

Pattern chung onboarding: logo Loox nhỏ (16px) góc trên trái mỗi step (trừ Welcome dùng logo lớn 34px), title lớn đậm, subtitle xám, nội dung, CTA pill full-width accent ở đáy (disabled = opacity ~0.4).

---

## 3a · Welcome

1. **Mục đích / vị trí**: màn đầu tiên khi chưa có vault. Entry point 2 nhánh: tạo vault mới hoặc sync từ máy khác. Label designer: "Welcome — hero + 3 feature card; **Sync chỉ hiện khi có iCloud**".
2. **Layout trên→xuống**:
   - Nền gradient nhẹ accent từ trên xuống (hero mood).
   - Logo Loox lớn, căn giữa.
   - Title: app-name line "Password Manager" (27px, 800).
   - Subtitle căn giữa, max-width ~300.
   - 3 feature card (card trắng bo 18, icon 38×38 nền tint màu riêng + title đậm + caption xám):
     1. Icon ổ khoá (accent blue) — "End-to-end encrypted" / "No servers. No accounts. Zero knowledge."
     2. Icon grid 4 ô (teal) — "Passwords, cards, notes" / "Plus passkeys and 2FA codes, in one vault."
     3. Icon Face ID (purple) — "Unlock with Face ID" / "Fast, private, on-device."
   - Đáy: 2 nút pill full-width: primary accent "Get Started" (shadow accent), secondary trắng chữ accent "Sync from another device".
3. **Copy (EN)**: "Password Manager" · "Every password, card and note — encrypted on this iPhone, nowhere else." · 3 card như trên · "Get Started" · "Sync from another device".
4. **State/biến thể**: nút "Sync from another device" CHỈ hiện khi iCloud khả dụng (`VAULTIFY_ICLOUD` + account signed-in). Không iCloud → chỉ còn "Get Started".
5. **Tương tác**: Get Started → 3b. Sync → join/restore flow (QR pairing — designer nhắc "bản Join Flow (QR pairing)" ở dv-next, chưa vẽ trong 2 file này).
6. **Ghi chú VI của designer**: "Welcome — hero + 3 feature card; Sync chỉ hiện khi có iCloud".
7. **Điểm mới đáng học**: value-prop 3 card thay vì slide carousel; conditional CTA theo capability iCloud; feature card thứ 3 chuẩn bị tâm lý cho step Face ID sau này.

## 3b · Create Master Password

1. **Mục đích / vị trí**: step 2, tạo Master Password. Label: "strength, lỗi inline, cảnh báo Emergency Kit".
2. **Layout**:
   - Logo nhỏ → Title "Create your Master Password" → subtitle.
   - **Field 1 (password)**: card trắng bo 16; text nhập font mono (mockup hiển thị passphrase rõ chữ "correct-horse-battery-st" + caret accent); icon mắt (reveal toggle) bên phải. Bên dưới trong cùng card: **strength meter = 4 đoạn thanh** + label chữ; mockup: 3/4 đoạn xanh lá đậm, đoạn 4 xanh nhạt 25% + label "Strong" xanh (12px, 700).
   - **Field 2 (confirm)**: card riêng, hiển thị dots `••••••••••••`, icon mắt. Trạng thái lỗi: **border đỏ 1.5px** quanh card + dòng lỗi đỏ 13px ngay dưới card: "Passwords don't match".
   - **Warning banner** (nền amber 13%, bo 16, icon tam giác chấm than amber): "If you forget it, the only way back in is your **Emergency Kit**. There is no reset — that's what keeps your vault yours." ("Emergency Kit" in đậm).
   - Đáy: CTA "Continue" **disabled** (opacity .4) — chỉ enable khi password đủ mạnh + confirm khớp.
3. **Copy (EN)**: title + "The one password that protects everything. Make it long and memorable." · strength label "Strong" (suy ra thang: Weak/Fair/Good/Strong hoặc tương đương 4 mức = 4 đoạn) · "Passwords don't match" · warning banner như trên · "Continue".
4. **State**:
   - Strength meter 4 mức, fill dần theo độ mạnh, màu theo mức (mockup chỉ vẽ mức Strong = xanh; suy ra mức thấp dùng đỏ/cam theo convention).
   - Confirm mismatch → border đỏ + inline error (không alert).
   - Continue disabled mặc định, enable khi valid.
   - Passphrase gợi ý style dấu gạch nối (mockup example khuyến khích passphrase dài dễ nhớ).
5. **Tương tác**: eye toggle reveal từng field; nhập real-time cập nhật strength + validate match; Continue → 3c.
6. **Ghi chú VI**: "Create Master Password — strength, lỗi inline, cảnh báo Emergency Kit".
7. **Điểm mới**: cảnh báo "no reset" đưa NGAY tại màn tạo password (giáo dục sớm về Emergency Kit trước khi thấy nó); strength meter nằm trong cùng card với field; lỗi inline dưới field thay vì alert.

## 3c · Emergency Kit

1. **Mục đích / vị trí**: step 3, ngay sau tạo Master Password. **Bắt buộc lưu kit thì mới Continue được** (gate cứng).
2. **Layout**:
   - Logo nhỏ → Title "Save your Emergency Kit" → subtitle "The only way back in if you ever forget your Master Password."
   - **Kit document card** (preview PDF thu nhỏ, card trắng bo 22, shadow accent lớn — trông như tài liệu):
     - Header band gradient accent (blue→cyan): chữ "EMERGENCY KIT" (caps, letter-spacing rộng) + logo Loox trắng bên phải.
     - Body: 2 cột meta — "VAULT OWNER" / "Minh Anh" (trái) · "CREATED" / "Jul 10, 2026" (phải). Label caps xám nhỏ, value đậm.
     - **Recovery key box**: khung dashed accent, nền tint accent 4%, label caps "RECOVERY KEY", key mono đậm 2 dòng: `HXK4-9PLM-22QD` / `7VNC-8RTB-5KWY` (format nhóm 4 ký tự, gạch nối, letter-spacing).
   - **CTA chính giữa nội dung** (không ở đáy): pill accent "Save as PDF" kèm icon download/share-down.
   - Hàng link phụ 2 text-button accent: "Copy key" · "Share…".
   - Caption xám nhạt căn giữa: "Print it. A drawer beats the cloud."
   - Đáy: "Continue" **disabled** (opacity .4) + caption dưới nút: "Save your kit to continue".
3. **Copy (EN)**: toàn bộ như trên. Đáng chú ý tone: "Print it. A drawer beats the cloud." (khuyên in giấy > lưu cloud).
4. **State**: Continue disabled cho tới khi user thực hiện ít nhất 1 hành động lưu (Save as PDF / Share / có thể cả Copy key — mockup chỉ nói "Save your kit to continue"; đề xuất: PDF hoặc Share mới count, Copy key thì cân nhắc). Sau khi lưu → Continue enable, caption đổi/ẩn.
5. **Tương tác**: Save as PDF → render PDF (app đã có Emergency Kit PDF engine — xem memory `vaultify-emergency-kit-pdf`) → share sheet lưu file; Copy key → clipboard (nên auto-clear); Share… → share sheet; Continue → 8a.
6. **Ghi chú VI**: "Emergency Kit — bắt buộc lưu PDF trước khi Continue".
7. **Điểm mới**: preview kit dạng "document" ngay trên màn (thấy trước chính xác thứ mình sẽ in — kiểu 1Password); gate Continue theo hành vi lưu; owner name trên kit lấy từ Name step — LƯU Ý mockup đặt Emergency Kit TRƯỚC Name step nhưng kit hiển thị "Minh Anh" ⇒ hoặc đổi thứ tự (Name trước Kit) hoặc kit ghi owner rỗng/generic. Xem Unresolved Q1.

## 3d · Lock — Face ID (auto)

1. **Mục đích / vị trí**: lock screen mặc định khi mở app đã có vault + Face ID bật. Face ID **tự chạy** khi màn xuất hiện.
2. **Layout**:
   - Nền radial glow accent nhẹ phía trên.
   - Giữa màn: **app icon tile** 112×112 (bo 30, trắng, shadow accent, logo Loox gradient bên trong) + **badge tròn accent 44px đè góc dưới-phải** (viền 3.5px màu nền tách khỏi tile) chứa icon Face ID trắng — badge biểu thị phương thức unlock đang chạy.
   - Title "Unlock your vault" (23px, 800).
   - **Status pill** (nền trắng mờ .8, bo pill): spinner nhỏ accent + text "Checking Face ID…" (xám, 600).
   - Đáy: text-button accent "Use Master Password instead".
3. **Copy (EN)**: "Unlock your vault" · "Checking Face ID…" · "Use Master Password instead".
4. **State**: pill status là vùng phản ánh tiến trình (checking / fail có thể đổi text + cho retry — mockup chỉ vẽ state checking). Chỉ hiện màn này khi biometric enabled; fail/cancel → fallback 3e.
5. **Tương tác**: Face ID tự trigger on-appear; tap "Use Master Password instead" → 3e; (theo lock UX hiện tại của app: deliberate lock thì KHÔNG auto Face ID → 3f).
6. **Ghi chú VI**: "Lock Screen — Face ID tự chạy, badge góc logo".
7. **Điểm mới**: badge method ở góc logo (ngôn ngữ thị giác: logo tile + badge = trạng thái khoá + phương thức); status pill thay vì text trần — có chỗ cho spinner/error mà không xô layout.

## 3e · Lock — Password

1. **Mục đích / vị trí**: lock screen mode mật khẩu — khi không có Face ID, user chọn "Use Master Password instead", hoặc Face ID fail.
2. **Layout**:
   - Nền phẳng, logo Loox 32px giữa màn.
   - Title "Unlock your vault" · subtitle "Enter your Master Password".
   - **Password field dạng pill full-width**: icon ổ khoá xám trái + dots mono letter-spacing + **nút submit tròn accent 38px (mũi tên lên) nằm TRONG field bên phải** (kiểu chat-input).
   - Inline error đỏ dưới field: "That password didn't work. Try again."
   - Đáy: text-button accent "Forgot password?".
3. **Copy (EN)**: như trên.
4. **State**: error inline khi sai password (không shake-only, có text rõ); field secure mặc định.
5. **Tương tác**: submit bằng nút tròn trong field hoặc return key; "Forgot password?" → recovery flow bằng Emergency Kit (scan/nhập recovery key — app đã có scan-to-recover).
6. **Ghi chú VI**: "Lock Screen — mode mật khẩu, lỗi inline, Forgot password?".
7. **Điểm mới**: submit button nhúng trong pill field (một tay thao tác nhanh); "Forgot password?" hiện diện thường trực trên lock screen → dẫn về Emergency Kit thay vì bế tắc.

## 3f · Lock — Slide to unlock

1. **Mục đích / vị trí**: CHỈ xuất hiện sau khi user **chủ động khoá** app (deliberate lock). Face ID bị tạm dừng — cần cử chỉ chủ đích trước.
2. **Layout**:
   - Logo Loox 32px giữa màn.
   - Title "Vault locked".
   - Subtitle 2 dòng giải thích: "You locked Loox yourself, so Face ID is paused.\nSlide when you're ready."
   - Đáy: **slider track pill** cao 60 (trắng, inner shadow) + label giữa "Slide to unlock" (xám nhạt) + **knob tròn accent 52px sát trái** chứa icon mũi tên phải.
3. **Copy (EN)**: "Vault locked" · "You locked Loox yourself, so Face ID is paused. Slide when you're ready." · "Slide to unlock".
4. **State**: chỉ 1 state; sau khi slide xong → chạy Face ID/password bình thường (khớp memory `vaultify-lock-ux-redesign`: deliberate lock yêu cầu slide trước Face ID).
5. **Tương tác**: drag knob hết track → unlock tiếp tục sang bước xác thực.
6. **Ghi chú VI**: "Lock Screen — slide-to-unlock (chỉ sau khi chủ động khoá)".
7. **Điểm mới**: copy giải thích LÝ DO Face ID pause ("You locked Loox yourself") — minh bạch hành vi, giảm confusion; hợp thức hoá cơ chế slide đã có trong app bằng ngôn ngữ thị giác rõ (inner-shadow track — lưu ý app cấm `BlurStyle.inner` cho shadow chung, nhưng đây là track well hợp lệ về ý đồ, implement bằng cách khác).

---

## 8a · Onboarding — Name step

1. **Mục đích / vị trí**: sau Emergency Kit (theo t8; xem Unresolved Q1 về thứ tự). Nhập tên (+ email optional) — **âm thầm tạo Identity mặc định** phía sau (map với default-identity invariant đã có trong app).
2. **Layout**:
   - Logo nhỏ → Title "What should we call you?" → subtitle "Used to prefill logins and your Emergency Kit. Stays on this iPhone."
   - **Field Name**: card trắng bo 16, icon person accent, **border accent 1.5px = focused state**, text "Minh Anh" + caret.
   - **Field Email (optional)**: card thường không border, icon envelope xám, placeholder "Email (optional)" màu placeholder.
   - Đáy: "Continue" enabled (accent + shadow).
3. **Copy (EN)**: như trên.
4. **State**: focused field có border accent; Continue — mockup vẽ enabled sẵn (suy ra name required, email optional; hoặc cho phép trống name? Mockup không vẽ disabled ⇒ đề xuất require name không rỗng).
5. **Tương tác**: Continue → 8b. Dữ liệu: tạo `IdentityRecord` mặc định (name, email) — tái dùng onboarding seed hiện có (memory `vaultify-identity-profile-feature`).
6. **Ghi chú VI**: "Name step — tạo Identity mặc định phía sau".
7. **Điểm mới**: giải thích rõ dữ liệu dùng để làm gì + đi đâu ("Stays on this iPhone") — privacy copy ngay tại field; 1 step gánh 2 việc (profile + prefill Emergency Kit owner).

## 8b · Onboarding — Choose Theme

1. **Mục đích / vị trí**: sau Name step. Chọn appearance, **preview live toàn app** (đổi theme ngay khi chọn — app đã hỗ trợ live theme switch).
2. **Layout**:
   - Logo nhỏ → Title "Pick your look" → subtitle "You can change this — and the accent color — anytime in Settings."
   - **List card 3 hàng** (card trắng bo 20, separator mảnh):
     1. Swatch tròn 36px nửa sáng/nửa tối — "System" — checkmark tròn accent (selected).
     2. Swatch tròn sáng — "Light" — vòng tròn rỗng viền xám (unselected).
     3. Swatch tròn tối — "Dark" — vòng rỗng.
   - Đáy: "Continue".
3. **Copy (EN)**: "Pick your look" · subtitle trên · "System" / "Light" / "Dark" · "Continue".
4. **State**: single-select radio, default System; chọn hàng nào → toàn màn đổi theme ngay (live preview).
5. **Tương tác**: tap hàng = select + apply; Continue → 8c (hoặc 8d nếu máy không có biometric).
6. **Ghi chú VI**: "Choose Theme — preview live toàn app".
7. **Điểm mới**: chỉ hỏi appearance mode ở onboarding (accent color để dành cho Settings — subtitle nói rõ); pattern radio-list với swatch tròn + check tròn accent.

## 8c · Onboarding — Enable Face ID

1. **Mục đích / vị trí**: sau Theme. **Chỉ hiện khi máy có biometric** (LAContext canEvaluate); không có → skip thẳng 8d.
2. **Layout** (centered, không logo nhỏ góc):
   - Icon tile lớn 104×104 (bo 32, nền tint accent 9%) chứa icon Face ID accent lớn.
   - Title "Unlock with Face ID".
   - Subtitle "Skip typing your Master Password every time. Your face never leaves this device."
   - Đáy: primary "Enable Face ID" + secondary text-button xám "Not now".
3. **Copy (EN)**: như trên.
4. **State**: nếu device chỉ có Touch ID → đổi copy/icon tương ứng (mockup không vẽ, suy ra theo convention). Tap Enable → prompt hệ thống; deny → vẫn đi tiếp.
5. **Tương tác**: Enable Face ID → set biometric unlock + sang 8d; Not now → 8d (Face ID off, bật lại trong Settings).
6. **Ghi chú VI**: "Enable Face ID — chỉ hiện khi máy có biometric".
7. **Điểm mới**: privacy reassurance ngay subtitle ("Your face never leaves this device"); opt-out mềm "Not now" (không phải "Skip").

## 8d · Onboarding — Done

1. **Mục đích / vị trí**: màn kết onboarding.
2. **Layout** (centered):
   - Nền radial glow **success green** nhẹ phía trên.
   - Circle 104px nền tint green chứa checkmark green lớn.
   - Title "You're all set" (26px, 800).
   - Subtitle "Vault created, kit saved, Face ID on. Time to move your passwords in."
   - Đáy: primary "Open Loox".
3. **Copy (EN)**: như trên. LƯU Ý subtitle là recap 3 việc đã làm — cần **dynamic theo lựa chọn thực tế** (nếu user "Not now" Face ID thì không nói "Face ID on"). Mockup chỉ vẽ happy path.
4. **State**: 1 state; subtitle nên compose theo flags (kit saved luôn true vì gate; Face ID theo 8c).
5. **Tương tác**: Open Loox → main app (Home/My Vault — khớp fix onboarding seed→My Vault trong memory). CTA gợi mở việc tiếp theo: import passwords ("Time to move your passwords in") — có thể deep-link import.
6. **Ghi chú VI**: "Done — 'You're all set'".
7. **Điểm mới**: recap checklist trong 1 câu; CTA "Open Loox" (brand voice) thay vì "Done"; hint next-action import.

---

## 8e · Personas (màn in-app)

1. **Mục đích / vị trí**: màn quản lý Personas — "Separate identities with their own suggestions and privacy rules." Child screen (có back button), push từ Settings/Profile. Tap hàng = **chuyển persona active**.
2. **Layout**:
   - Nav row: nút back tròn (trắng mờ, blur) trái · nút **+** tròn accent phải (tạo persona mới).
   - Large title "Personas" (31px, 800) + caption xám dưới title: "Separate identities with their own suggestions and privacy rules."
   - **List card** 3 hàng, mỗi hàng: icon tile 38×38 bo 11 nền tint màu riêng + name đậm + caption + selector (check tròn accent = active / vòng rỗng):
     1. Icon person (accent blue) — "Personal" — caption "minh.anh@icloud.com" — **active**.
     2. Icon cặp táp (teal) — "Work" — caption "minh.anh@work.vn · Isolated".
     3. Icon dấu hỏi tròn (purple) — "Ẩn danh" — caption **màu purple** "Strictly anonymous — never suggested elsewhere".
   - Footer caption xám nhạt giữa màn: "Swipe a persona for Edit / Delete · at least one must remain".
3. **Copy (EN)**: như trên. Caption policy xuất hiện **khi persona khác policy Standard**: "Isolated" (đính sau email, ngăn cách " · ") và "Strictly anonymous — never suggested elsewhere" (thay hẳn email, đổi màu theo persona). Persona Standard chỉ hiện email.
4. **State**:
   - Selector: đúng 1 persona active (radio).
   - 3 mức policy suy ra: **Standard** (không caption) / **Isolated** / **Strictly anonymous** — caption + màu nhấn tăng dần theo mức riêng tư.
   - Ràng buộc: **tối thiểu 1 persona** — không cho xoá persona cuối.
5. **Tương tác**: tap hàng → switch active persona; swipe hàng → Edit / Delete; nút + → tạo persona; back → pop.
6. **Ghi chú VI**: label "Personas — tap để chuyển, caption policy khi khác Standard"; footer trong màn: "Swipe a persona for Edit / Delete · at least one must remain" (EN nhưng là chú thích hành vi của designer).
7. **Điểm mới**: policy được hiển thị như caption trạng thái ngay trong list (không cần vào detail); persona ẩn danh có brand màu riêng (purple) nhấn tính chất; switch nhanh bằng 1 tap; ràng buộc min-1 nói thẳng trên UI. Map với PersonaRecord của Persona/Relay Proposal V3.

## 8f · Space editor (sheet in-app)

1. **Mục đích / vị trí**: sheet edit/tạo Space (bo góc trên 28, grabber, đè trên background mờ tối). Vào từ màn quản lý Spaces.
2. **Layout trên→xuống**:
   - Grabber → header sheet: nút X tròn trái · title giữa "Edit Space" · text-button phải "Save" (accent, 700).
   - **Preview badge live**: tile 64×64 bo 18, nền tint theo màu đang chọn, icon đang chọn (mockup: cặp táp teal) — cập nhật ngay khi đổi icon/màu.
   - **Field tên**: card trắng, value "Work" (16.5px, 600).
   - Section label caps "ICON" → **icon grid 6 cột** trong card trắng: ô 1:1 bo 11; ô chưa chọn nền xám nhạt icon xám; **ô đang chọn**: nền tint màu space + ring 2px màu space + icon theo màu. Bộ icon: lock, briefcase, home, person, card, shield.
   - Section label caps "COLOR" → card trắng hàng **7 swatch tròn 32px**: blue `#1544FD`, teal `#0E9BA4`, green `#1F9D5B`, purple `#7451EB`, pink `#D6479B`, orange `#E8590C`, gray `#5D6069`; **swatch đang chọn** có ring: khoảng trắng 2.5px + vòng màu 2px (double-ring).
   - **Delete Space**: card trắng riêng, text đỏ căn giữa.
   - Caption dưới cùng: "Items move to Unfiled — nothing is deleted."
3. **Copy (EN)**: "Edit Space" · "Save" · "ICON" · "COLOR" · "Delete Space" · "Items move to Unfiled — nothing is deleted."
4. **State**: icon selected-ring theo màu space (đổi màu → ring icon đổi theo); preview badge live sync icon+màu; mode Create vs Edit (Create: title khác + không có Delete — suy ra); Save enable khi name không rỗng (suy ra).
5. **Tương tác**: đổi icon/màu → preview cập nhật tức thì; Save → persist + dismiss; X → dismiss (nếu dirty → confirm discard theo pattern app); Delete Space → confirm destructive → items chuyển về "Unfiled", KHÔNG xoá item.
6. **Ghi chú VI**: label "Space editor — icon + màu, preview badge live, Delete"; caption "Items move to Unfiled — nothing is deleted." là quyết định hành vi quan trọng (delete space = soft, non-destructive với items).
7. **Điểm mới**: preview badge live ở đầu sheet (thấy kết quả trước khi Save); selection ring của icon nhuộm theo màu space (icon picker và color picker liên đới); khái niệm "Unfiled" làm nơi hứng items khi space bị xoá; palette 7 màu cố định (khớp tinh thần 7 accent presets của app).

---

## Cross-cutting notes cho dev

- **Ngôn ngữ thị giác chung**: nền `#F3F3F7`-tương-đương (systemGroupedBackground), card trắng bo 16–22, CTA pill full-width accent có shadow accent, disabled = opacity .4, inline error đỏ dưới field, warning banner amber tint, caption xám nhạt căn giữa cho phụ chú. Map hết sang token/theme hiện có, không hardcode.
- **Radio/check pattern thống nhất**: check tròn accent 22px (checkmark trắng) vs vòng rỗng viền xám — dùng ở Theme, Personas.
- **Icon tile pattern**: 38×38 bo ~11, nền tint 9–13% màu chức năng — dùng ở Welcome cards, Personas, Space editor.
- **Localize**: toàn bộ copy EN trên phải có bản VI trong `Localizable.xcstrings` (quy tắc repo).
- **Mockup dùng tên riêng "Minh Anh"** và email mẫu — chỉ là sample data.
- Trang t3 footer designer: "Tiếp theo: «làm Đợt 4: Sharing / Approval» · «xem Name step + Theme + Done của onboarding» · «bản Join Flow (QR pairing)»". Trang t8 footer: "Feature map đã phủ trọn các luồng chính. Tiếp được: «bản Night toàn bộ» · «Privacy Shield + Approval waiting states» · «export PNG từng màn để đưa vào Figma»." → dark mode versions + Privacy Shield/Approval waiting states CHƯA có mockup.

## Unresolved questions

1. **Thứ tự Name vs Emergency Kit**: t3 xếp Kit ở Đợt 3 (trước Name step ở Đợt 8) nhưng kit preview đã in "Vault owner: Minh Anh" → hoặc Name step phải đứng trước Kit, hoặc kit render owner sau. Cần chốt thứ tự thực tế: đề xuất Welcome → Master Password → Name → Emergency Kit → Theme → Face ID → Done.
2. "Copy key" có được tính là "đã lưu kit" để enable Continue không, hay chỉ Save as PDF / Share?
3. Nút "Sync from another device" dẫn tới flow nào (QR pairing chưa được vẽ trong 2 file này)?
4. Done subtitle recap có dynamic theo lựa chọn Face ID không (mockup chỉ vẽ happy path)?
5. Personas: policy levels chính xác (Standard/Isolated/Strictly anonymous?) và semantics từng mức chưa được định nghĩa trong 2 file này — cần đối chiếu Persona V3 proposal.
