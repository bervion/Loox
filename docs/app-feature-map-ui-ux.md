# Loox Password — Sơ đồ tính năng & đặc tả màn hình (dành cho team Design)

> Tài liệu mô tả **toàn bộ tính năng, màn hình, và các trạng thái hiển thị** của app
> Loox Password (codename Vaultify) + AutoFill extension, để team design hiểu cần
> thiết kế UI/UX như thế nào. Baseline: khảo sát code ngày 2026-07-10;
> Private Email và Member được đồng bộ với native source ngày 2026-10-07.

## 0. Tổng quan sản phẩm

- **Loox Password** — vault mật khẩu & passkey mã hoá, hoạt động offline; CloudKit sync, sharing và Private Email là tính năng online tùy chọn. Tuist khai báo iPhone/iPad iOS 17.3+ và app macOS 15+, cùng extensions tương ứng.
- **Ngôn ngữ:** EN + VI + JA (toggle trong app). UI mới phải có đủ bản dịch trong catalog.
- **Nguyên tắc UI:** Apple-native SwiftUI, bộ icon **Polaris SVG** (không dùng SF Symbols, trừ ngoại lệ `faceid`), design token (Space/Radius/Metric/Elevation/Motion), semantic color theo theme (Day/Night + 7 accent preset), hỗ trợ Dynamic Type, Reduce Motion, Reduce Transparency, hit target 44pt.
- **Pattern lặp lại toàn app:**
  - *Tap-to-copy*: chạm field → copy, row nháy màu accent + label "Copied" ~1.2s, haptic.
  - *Empty state*: `ContentUnavailableView` (icon + title + mô tả ngắn).
  - *Error inline*: text đỏ ngay dưới form, không alert trừ khi nghiêm trọng.
  - *Busy*: spinner overlay hoặc spinner trong nút prominent, nút disable.
  - *Secure field*: `RevealableSecureField` (nút mắt reveal/ẩn), mật khẩu mới luôn kèm `PasswordStrengthMeter`.
  - *Sheet scaffold*: header có nút X (đóng) trái + action phải (Done/Save/Recover…).

## 1. Sơ đồ điều hướng tổng thể

```
App khởi động (RootView — 3 route)
├── ONBOARDING (chưa setup)
│   ├── Welcome ──"Get Started"──▶ Create Master Password ▶ Name ▶ Emergency Kit ▶ Theme ▶ [Biometric*] ▶ Done
│   └── Welcome ──"Sync from another device"──▶ Join Flow (Choice ▶ QR Pairing | Recovery Key ▶ Password ▶ [Biometric*])
├── LOCKED ▶ Lock Screen (Face ID / mật khẩu / slide-to-unlock) ── "Forgot password?" ▶ Recovery sheet
└── UNLOCKED ▶ MainTabView — 4 tab (icon-only)
    ├── HOME (dashboard) ─▶ Profile / Notifications / Item Detail / sheets (Editor, Generator, Settings, 2FA list, Space picker)
    ├── ITEMS (tổ chức) ─▶ Space / Category / Tag / Shared with Me / Archive / Recently Deleted ─▶ Item Detail
    ├── WATCHTOWER (bảo mật) ─▶ danh mục issue ─▶ Item Detail
    └── SEARCH ─▶ Item Detail
    Item Detail ─▶ Editor (sheet) / Share Access / Open on Computer / Passkey detail
    Settings (sheet) ─▶ ~12 màn con (xem mục 8)
```

*\* Bước Biometric chỉ xuất hiện khi máy có Face ID/Touch ID.*

**Deep link / event toàn cục:** `otpauth://` (mở editor tạo login kèm 2FA), link mời chia sẻ `invite.looxpassword.com/i/…` (alert "Invitation accepted"/lỗi), push approval request (mở sheet phê duyệt).

**Privacy Shield:** khi app vào App Switcher (nếu bật "Hide contents in App Switcher") — phủ toàn màn hình material mờ + logo, fade in/out.

---

## 2. Onboarding & Unlock

### 2.1 Welcome (bước đầu onboarding)
- Layout: logo hero → tiêu đề "Password Manager" + subtitle → 3 feature card (E2E encryption / Passwords, cards, notes / Unlock with Face ID). Cuộn được trên màn nhỏ.
- Nút: **Get Started** (prominent); **Sync from another device** (bordered) — *chỉ hiện khi iCloud đã cấu hình*.
- Nền: gradient accent mờ từ trên xuống.

### 2.2 Create Master Password
- Logo compact → tiêu đề → field mật khẩu (reveal + strength meter) → field xác nhận (+ lỗi inline đỏ "Passwords don't match" khi lệch) → **card cảnh báo vàng**: quên mật khẩu chỉ khôi phục được bằng Emergency Kit, không có reset.
- Nút Continue: disable đến khi ≥8 ký tự & khớp; có spinner khi đang xử lý; lỗi hiện text đỏ + haptic.
- Được tái dùng trong Join Flow với copy khác ("Vault received — protect this device").

### 2.3 Name step ("What should we call you?")
- 2 field nổi bật có icon: Tên (bắt buộc, auto-focus) + Email (tuỳ chọn). Nút Continue đáy màn.
- Tạo Identity mặc định + login "Loox Account (Tên)" phía sau.

### 2.4 Emergency Kit (bắt buộc lưu trước khi tiếp tục)
- Key card: đang tạo → spinner; xong → recovery key font mono chia 2 dòng, chọn-copy được.
- Hàng action: **Copy** (hiện toast "Copied") + **Share** (chỉ hiện khi có key).
- **Save Emergency Kit (PDF)** card: mặc định (icon shield + mô tả) ⇄ đã lưu (check xanh "Emergency Kit saved"). Mở `fileExporter`; lỗi export hiện text đỏ.
- Continue **disable đến khi đã lưu PDF**.
- PDF in được (A4, luôn light): logo + "EMERGENCY KIT", tài khoản iCloud (nếu có), recovery key mono, **QR Setup Code**, banner cảnh báo vàng, hướng dẫn 3 bước, footer "Created for {tên} on {ngày}".

### 2.5 Choose Theme
- Card gồm 3 hàng System / Light / Dark, swatch tròn + check accent khi chọn; preview live toàn app.

### 2.6 Enable Biometric (tuỳ chọn)
- Icon Face ID/Touch ID 72pt accent → tiêu đề động theo loại biometric → **Enable {Face ID}** + **Not now**.

### 2.7 Done
- Check tròn xanh 72pt + "You're all set" + nút **Open Loox**.

### 2.8 Join Flow (thiết lập từ máy khác)
- **Choice**: 2 option card — *Pair with QR Code* / *Use Recovery Key* + nút Back.
- **Pair with QR** (máy mới hiện QR): QR ≤260pt + trạng thái bên dưới: *chờ* (spinner "Waiting for your other device…") / *lỗi* (text đỏ + nút **Start Over**).
- **Recovery Key**: 1 field key (mono khi có chữ) + lỗi đỏ; nút **Scan Setup Code** (mở camera scan QR trong PDF kit) + **Continue** (spinner khi busy). Lỗi: "That recovery key didn't work."
- Sau đó → Create Password (bản join) → Biometric → vào app.

### 2.9 Lock Screen
- Logo hero + **badge biometric** góc dưới-phải logo (icon Face ID; đang xác thực → spinner; tap để thử lại).
- Tiêu đề "Unlock your vault" + subtitle động (có/không biometric).
- **3 chế độ hiển thị:**
  1. *Biometric*: tự prompt Face ID khi mở/foreground; fail 3 lần → chuyển sang mode mật khẩu.
  2. *Password*: field bảo mật bo tròn (icon khoá, placeholder "Enter password", giá trị gõ = font mono) + nút mũi tên inline (spinner khi busy, mờ 45% khi trống); lỗi đỏ dưới field.
  3. *Slide-to-unlock*: **chỉ khi người dùng chủ động khoá** (lắc máy / Settings "Lock Now") — capsule "Slide to unlock" + knob accent kéo ≥90% mới mở; ngăn Face ID tự mở lại vault vừa chủ động khoá.
- "Forgot password?" (footnote, đáy màn, chỉ ở mode password) → **Recovery sheet**: nhập recovery key + đặt mật khẩu mới (strength meter + confirm); nút Recover disable đến khi hợp lệ; busy overlay; lỗi đỏ.

---

## 3. Tab shell (MainTabView)

- 4 tab cố định **Home · Items · Watchtower · Search**, thanh tab **chỉ icon** (không label; VoiceOver có label bản địa hoá).
- Icon outline ⇄ filled khi active (search không có bản filled).
- iOS 18+: tab Search mang `role: .search` (iOS 26: ô search nằm ngay tab bar/trên bàn phím). iOS 17.3: tab thường.
- Tab nhớ trạng thái điều hướng riêng; app khôi phục tab + độ sâu nav + draft editor dở dang sau khi unlock (UI-state restoration).

---

## 4. Home (dashboard)

Header **kính nổi (floating glass)** đè lên nội dung khi cuộn: wordmark "Loox" trái; phải: **chuông Notifications** (badge đỏ = lời mời + yêu cầu phê duyệt, hiện "9+" khi >9) + **nút Add** (menu chọn loại item) + **Settings**.

Nội dung cuộn, từ trên xuống (mục nào không có dữ liệu thì ẩn):
1. **Profile row** — avatar 44pt + tên persona đang hoạt động + subtitle (loại persona · email, hoặc "Set up your identity") + chevron → Profile.
2. **Quick actions** (lưới 2×2, card màu, kính tint trên iOS 26): **Add Item** (accent, mở menu loại item) · **Generate Password** (teal → Generator sheet) · **2FA Codes** (tím, badge số lượng → sheet danh sách TOTP) · **Watchtower** (xanh lá, badge số issue → chuyển tab Watchtower).
3. **Approval needed row** *(chỉ khi có yêu cầu phê duyệt chờ)* — chấm xanh + shield + số lượng; 1 yêu cầu → mở thẳng sheet phê duyệt, nhiều → màn Notifications.
4. **Authenticator Codes** *(chỉ khi có item TOTP)* — scroller ngang các **TOTP card** (158pt: favicon + vòng đếm ngược + mã 6 số "123 456"; tap = copy + nháy "Copied"; vòng chuyển cam khi ≤5s; Reduce Motion → hiện số giây thay vòng). Header có "View All".
5. **Needs Attention · N** *(khi có, tối đa 4)* — cell: favicon + tên + lý do (quá hạn xoay mật khẩu = đỏ, mật khẩu yếu = đỏ, sắp đến hạn = vàng) + nút **Change** (mở editor). Tap row → detail.
6. **Favorites** *(khi có)* — card nhóm các row item.
7. **All items** (luôn hiện) — header là **Space switcher** (tên Space · số item · chevron → sheet chọn Space) + nút **Sort** (Recently Updated ⇄ Title). Item pin nổi lên đầu; item được chia sẻ với mình luôn gộp vào.

**Trạng thái đặc biệt:**
- **Vault trống**: emblem khoá giữa màn + "Your vault is empty" + mô tả + nút **Add Item** prominent.
- Bộ lọc Space: nil = "All Spaces"; tự chọn Space duy nhất nếu chỉ có 1; nhớ Space theo từng persona qua các lần mở.

**Space picker sheet**: hàng "All Spaces" + từng Space kèm số item + check; phần quản lý: "Create New Space" + "Manage Spaces & Members".

**Sheet 2FA Codes**: lưới TOTP card; trống → "No 2FA codes" + hướng dẫn.

---

## 5. Items (tab tổ chức)

Header kính "Items" + nút Add. Danh sách dạng card nhóm dọc:
1. **Spaces** — mỗi Space 1 row (badge màu/icon + tên + số item + chevron); row **Unfiled** *(chỉ khi có item chưa xếp)*; row **Shared with Me** *(khi có chia sẻ)*; row **Create Space** (accent).
2. **Categories** *(chỉ các category có item)* — tile màu + tên + số.
3. **Tags** *(khi có tag)* — tile `#` + tag + số.
4. Card riêng: **Archive** (số item lưu trữ) + **Recently Deleted** (số item trong thùng rác).

Badge số ẩn khi = 0. Màn không bao giờ trống hoàn toàn (luôn có Create Space).

**Màn con:**
- **Danh sách theo category/Space/tag** — list item + menu Sort; trống → "No items here" + icon category.
- **Archive** — swipe trái = Unarchive, phải = Trash; trống → "No archived items" + giải thích.
- **Recently Deleted** — footnote "Items in Trash are still encrypted. Deleting them is permanent."; swipe = Restore / Delete vĩnh viễn; nút **Empty** (chỉ khi có item) → dialog xác nhận "Empty Trash"; trống → "Trash is empty".

**Quản lý Spaces (từ Settings/Home):** list Space kéo-thả sắp xếp (EditButton), nút +; trống → "No Spaces yet". **Editor Space (sheet)**: tên + picker icon (24 icon tuyển chọn) & màu (preview badge 64pt live); bản edit có **Delete Space** (dialog "Items move to Unfiled"). **Folder picker sheet** (chọn Space cho item): "None" + list + "New Space…".

---

## 6. Search

- NavigationStack riêng + `.searchable`; **ô search tự kích hoạt khi vào tab** (gõ được ngay). Prompt "Search vault". Tìm theo token AND trên tên/field/tag/tên Space.
- **Scope chips** (chỉ hiện khi >1 scope): *This Space* (tên Space hiện tại) / *All Spaces* / *Shared with Me*. Chip active = nền accent nhạt. Persona "strictly anonymous" bị chặn All Spaces (fail-closed).
- **4 trạng thái:** chưa gõ → "Search your vault" + mô tả; có kết quả → list row item; không có kết quả trong scope hẹp → "No results in {scope}" + nút **Search all Spaces** (mở rộng 1 chạm); không có kết quả toàn cục → empty search chuẩn hệ thống.

---

## 7. Watchtower (giám sát bảo mật)

Header kính "Watchtower" + Add; kéo-refresh chạy audit lại.

Từ trên xuống:
1. **Score ring** — gauge 270° kiểu đồng hồ tốc độ (0–100), kim + gradient đỏ→vàng→xanh; animation intro quét hết dải rồi về điểm số, số đếm theo (Reduce Motion → hiện ngay). Nhãn theo band: **≥80 "Fairly secure"** (xanh) / **≥50 "Needs attention"** (vàng) / **<50 "At risk"** (đỏ).
2. Subtitle *(khi có issue)*: "Fix N issues below…".
3. **Strength card** — "Overall password strength" + thanh % (fill xanh + phần spectrum mờ; animation mọc vào).
4. **"To fix"** — mỗi danh mục chỉ hiện khi count > 0, thứ tự cố định:
   - **Compromised** (đỏ, shield-alert) — lộ trong data breach *(chỉ khi HIBP bật và có kết quả)*.
   - **Reused** (vàng, icon copy) — dùng chung mật khẩu.
   - **Weak** (vàng, khoá) — mật khẩu dễ đoán.
   - **Missing 2FA** (accent, check) — site hỗ trợ 2FA nhưng chưa bật.
   - Mỗi row: icon tile + tiêu đề + mô tả + badge số + chevron → **màn danh mục** (list item + chi tiết như "Seen N times in breaches" → tap mở item detail).
5. **All clear** *(khi audit xong và 0 issue)*: card check xanh "Every password is strong and unique." thay cho list.
6. **HIBP section** — toggle "Check for known breaches" + footnote giải thích k-anonymity. Đang check → overlay spinner "Checking breaches…". Tắt HIBP → không có danh mục Compromised, không gọi mạng.

---

## 8. Settings

Trình bày dạng sheet (title "Settings", nút Done). Các section theo thứ tự:

| Section | Nội dung |
|---|---|
| **Security** | Toggle "Unlock with Face ID/Touch ID" *(ẩn hẳn nếu máy không có biometric)*; Picker Auto-Lock (Immediately/1m/5m/15m/1h); Toggle "Shake to lock"; → Change Master Password; → Emergency Kit; → Extra Protection; Toggle "Automatic passkey upgrades" |
| **AutoFill** | "Set up password AutoFill" (iOS 18+: prompt hệ thống trong app; cũ hơn: deep-link Settings); "Set up verification codes" |
| **Organization** | → Spaces |
| **Online Features** | Toggle "Private Email" + Toggle "Share Links" — mỗi row có **subtitle trạng thái** (Available/Offline/Maintenance/Unavailable…); *sự cố chỉ đổi subtitle, KHÔNG tự gạt toggle* |
| **Privacy** | Toggle "Hide contents in App Switcher"; Picker "Clear clipboard" (15s/30s/1m/Never) |
| **Icons** | Toggle "Show website icons" (footer cảnh báo Google thấy site) |
| **Appearance** | → Theme & Wallpaper; Picker Language (System/English/Tiếng Việt) |
| **Watchtower** | Toggle HIBP |
| **Data** | → iCloud Sync; → Passkeys; → Import; → Export |
| **Lock/Erase** | "Lock Now"; **"Erase Vault"** (đỏ) → dialog "Erase Everything" ("This permanently deletes every item and key…"); nếu còn alias email đang hoạt động mà offline → alert **"Network needed"** chặn xoá |
| **About** | → About (logo, version, 4 dòng "How your data is protected", privacy) |

**Màn con đáng chú ý:**
- **Extra Protection (Level-2)** — đặt/đổi mật khẩu phụ bảo vệ field siêu nhạy cảm. Có L2: thêm field mật khẩu hiện tại, nút "Change"; chưa có: "Set". Cảnh báo không khôi phục được. Busy overlay, lỗi inline.
- **Change Master Password** — current + new (strength meter) + confirm; Save disable đến khi hợp lệ; đổi mật khẩu không đổi Vault Key (biometric & Emergency Kit vẫn dùng được).
- **Emergency Kit (regenerate)** — trạng thái "đã có kit" / "chưa có"; nút Generate/Regenerate (có kit → dialog "Your previous recovery key will stop working."); sau khi tạo: key mono + Copy/Share/**Save PDF** ("shown only once").
- **Appearance** — lưới **2 theme card** Day/Night (mini preview vault, check khi chọn); lưới **7 accent swatch** (blue/indigo/teal/purple/pink/graphite/mono, ring khi chọn, apply tức thì); → Automatic Dark Mode; Picker Text Size (6 mức); Toggle Reduce Motion.
- **Automatic Dark Mode** — mode Off/System/Scheduled/Brightness (row check); *Scheduled* → 2 DatePicker From/To (mặc định 22:00–07:00); *Brightness* → slider ngưỡng % (mặc định 40%); mode ≠ off → Picker Night theme (Night/Night Tinted).
- **iCloud Sync** — Toggle chính (footer: chỉ ciphertext lên iCloud); *chưa cấu hình iCloud* → info amber hướng dẫn; khi bật: nút **Sync Now** + dòng trạng thái (Syncing… spinner / "Last sync {giờ}" / lỗi đỏ) + nút **Pair New Device** (chỉ khi unlock) → **Pair Device sheet** 5 bước: *scanning* (camera quét QR máy mới) → *confirm* ("Add this device to your vault?" — Approve/Cancel, không bao giờ tự gửi key khi chỉ mới scan) → *publishing* (spinner) → *done* (check "Device Paired") → *failed* (Try Again).
- **Import** — "Choose File…" (CSV 1Password/Bitwarden/Chrome hoặc `.vaultify`); nếu là backup mã hoá → hiện field "Backup password" + nút Decrypt; parse xong → **Preview (N)**: 6 item đầu + "and X more…" + số passkey → nút **Import N Records**. Lỗi rõ ràng từng case: không mở được file / format không hỗ trợ / sai mật khẩu / backup rỗng / phải unlock trước khi import passkey.
- **Export** — segmented **Encrypted / CSV**; Encrypted → field mật khẩu + confirm (footer Argon2id + AES-GCM); CSV → **cảnh báo đỏ "not encrypted… Passkeys are never included"**; nút Create Export (disable khi chưa hợp lệ) → hiện **Share Export** khi xong.

---

## 9. Item Detail (xem 1 item)

Vào từ mọi list. ScrollView nền grouped:
1. **Header**: hàng 1 = pill Space (tap → sheet "Located in" đổi Space) *hoặc* pill "Shared with Me" (item được chia sẻ) + nút **pin/favorite** (chỉ item của mình; filled ⇄ outline); hàng 2 = favicon/thumbnail chữ cái + tiêu đề + category.
2. **Badge chia sẻ** *(item nhận chia sẻ)*: shield + "Shared with you — you can use what's listed here, but not edit it."
3. **Tag chips** ngang *(khi có)*.
4. **Fields card** — mỗi field 1 row (xem 9.1). Item chia sẻ: bọc trong **cổng xác thực online** (9.4).
5. **Passkeys section** *(khi có passkey khớp domain)*.
6. **Sharing section** (item của mình: list người nhận + trạng thái Active/Pending) *hoặc* **Safety code card** (item nhận: mã an toàn mono + "so sánh với máy chủ sở hữu").
7. **Action card**: item sống → "Move to Trash" (đỏ, dialog xác nhận); trong thùng rác → "Restore" (xanh) + "Delete Permanently" (đỏ, "This can't be undone."); item nhận chia sẻ → "Leave Share" (đỏ, dialog).
8. **Metadata**: Created / Modified.

**Toolbar**: nút **Share** (item của mình, chưa trash) + menu "…": Edit / **Open on Computer** *(khi tính năng Quick View mở)* / Share Website Link / Archive-Unarchive. Item chia sẻ: menu chỉ có Leave Share.

**Trạng thái đặc biệt**: item không tồn tại → "Item not found"; item chia sẻ đang tải → spinner; chặn trash identity cuối cùng → alert "Keep at least one identity".

### 9.1 Field row (thành phần quan trọng nhất)
- Tap bất kỳ đâu → copy + nháy accent + "Copied".
- **Kiểu hiển thị theo loại**: TOTP → mã sống 6 số + **vòng đếm ngược** (≤5s đỏ, ≤10s vàng); URL → scheme mờ + domain accent; secret chưa reveal → hiệu ứng **SpoilerText** (che hạt); đa dòng → wrap font mono; mật khẩu → badge độ mạnh (chữ + chấm màu).
- Menu "•••": Copy / **Large Type** / Reveal-Conceal / Open Website / **Protect…** (khoá field bằng Level-2 hoặc mã riêng).
- **Field được bảo vệ thêm (Protected)**: hiển thị "Protected — tap to reveal" + icon khoá; reveal cần Extra Password hoặc mã riêng (sheet nhập mã, lỗi sai mã inline); menu có "Remove Protection".
- **Attachment**: tile icon loại file + tên + "EXT · size"; tap → Quick Look; lỗi "Attachment unavailable".
- **Large Type** (full-screen): lưới ký tự ô màu đánh số, tap ô để đánh dấu đã nhập; nút Copy; TOTP có vòng đếm trên header + pill TOTP nổi đáy màn.

### 9.2 Protect Field sheet
Segmented "Extra Password" / "Custom code". Level-2 chưa đặt → cảnh báo "Set an Extra Protection password in Settings first"; Custom → mã ≥4 + confirm + footer "không khôi phục được".

### 9.3 Passkey trong item
- Item của mình: card row (userName + "Created {ngày}" + icon person-lock tím) → **Passkey detail sheet**: favicon + site + **badge trạng thái backup** ("Backed up" xanh / "Backup eligible" / "This device only"), thông tin Username/Created/Last used/Credential ID, nút **Delete Passkey** (đỏ, dialog "permanently destroys the private key").
- Item nhận chia sẻ: row chỉ hiện site + chế độ ("Ready to use" / "Ask owner each time" / "Off"), không bao giờ lộ private key.

### 9.4 Cổng truy cập item chia sẻ (SharedAccessGate) — **6 trạng thái**
| Trạng thái | Hiển thị |
|---|---|
| Thiết bị không được cấp | "The owner limited this item to a different device." |
| Đã xác thực | Hiện giá trị field |
| Offline | "You need an internet connection to view this shared item." |
| Đang xác minh | Spinner "Verifying access…" |
| Không xác minh được | "Couldn't verify access right now." + nút **Try Again** |
| Bị thu hồi | "The owner has revoked access to this item." |

Giá trị bí mật **không bao giờ render** trước khi qua cổng. Tự xác minh lại khi mở màn / mạng đổi / app active.

---

## 10. Item Editor (tạo/sửa item)

Sheet Form; title = tên category. 3 mode: tạo mới / sửa / khôi phục draft (draft dở dang được seal và mở lại sau unlock).

**Layout:**
1. **Header**: pill dropdown chọn Space; thumbnail (favicon theo URL, hoặc menu "Choose icon"/"Letter avatar") + field tiêu đề bold ("Enter a title").
2. **Suggested email** *(chỉ Login mới, khi bật Private Email)*: chips ngang — "Create private email" ("Unique for {host}") / alias có sẵn / gợi ý username.
3. **Fields** theo category (bảng dưới).
4. **Tags**: chips `#` có nút xoá + field "Add tag" (commit bằng return/phẩy, tự dedup).
5. **Rotation reminder**: Picker Off / 15 / 30 / 90 ngày.

**Form theo category:**
| Category | Field mặc định |
|---|---|
| Login | Username, Password (protected) — chia section **Credentials / Websites (nhiều URL) / Custom Fields / Notes**; hàng passkey liên kết hiện trong Credentials |
| Secure Note | 1 field đa dòng |
| Payment Card | Cardholder, Card Number (protected, mono), Expiry, Security Code (protected) |
| Identity | Full Name, Email, Phone, Address (đa dòng), Date of Birth, ID Number (protected) |
| SSH Key | Private Key (protected, đa dòng), Public Key |
| Recovery Codes | 1 field protected đa dòng |
| Security Questions | cặp Hỏi/Đáp (đáp protected) |
| Custom | 1 field tự do |

**Hành vi & trạng thái:**
- Field mật khẩu/TOTP: che 16 chấm khi mất focus, hiện mono khi focus; field TOTP có nút **scan QR** (full-screen camera, luôn tối, hint "Point the camera at the 2FA QR code", kèm "Choose a screenshot" + "paste setup key"; lỗi: "That doesn't look like a 2FA setup code.").
- **GenerateChip nổi** "Generate strong password" bám dưới field mật khẩu đang focus → mở Generator sheet, giá trị đổ ngược lại.
- Website row: gõ domain trần → chip gợi ý URL https đầy đủ kèm favicon.
- Save (icon check): disable khi chưa có tiêu đề & mọi field trống. Nút Edit (chỉ iOS): bật chế độ sắp xếp/xoá field.
- Có thay đổi → chặn kéo-đóng sheet + dialog **"Discard changes?"**.
- Sheet phụ: Icon picker (lưới 5 cột toàn bộ icon Polaris), Attachment picker (Choose File / Choose Photo), Generator.
- ⚠️ *Gap UX hiện tại: field kiểu Date đang là ô text thường, chưa có date picker.*

---

## 11. Generator (mật khẩu / passphrase / PIN)

- **Output card**: giá trị tap-to-copy (số/chữ/ký hiệu tô màu khác nhau) + strength meter (ẩn với PIN).
- **Type menu**: Password / Passphrase / PIN.
  - Password: slider Length 8–64 + toggle Uppercase/Lowercase/Digits/Symbols/Avoid ambiguous.
  - Passphrase: slider Words 3–10 + Separator (Hyphen/Period/Space/Underscore) + Capitalize + Include number.
  - PIN: slider Length 4–12.
- Toolbar: **Regenerate** luôn có; **Use** (check accent) chỉ khi mở từ editor. Tự sinh lại khi đổi bất kỳ option nào; slider có haptic.

---

## 12. Profile & Personas

### 12.1 Profile (từ avatar trên Home)
1. **Avatar** (ảnh hoặc chữ cái, badge camera → PhotosPicker đổi ảnh; ảnh được thu nhỏ + mã hoá).
2. **Persona section**: icon loại + tên + meta; menu **Switch** (chỉ khi >1 persona, check ở persona active); "Manage personas"; "Private Email".
3. **Identity card** + 4. **Payment card** — cùng cấu trúc: header (title + Edit khi có lựa chọn) / các field tap-to-copy (giá trị protected hiện "••••••••" nhưng copy giá trị thật) / empty state ("No identity yet" / "No payment card yet" + "Choose one below or add a new one") / hàng chọn (menu item trong pool + "Create new").

### 12.2 Personas (quản lý danh tính)
- **Danh sách**: row icon loại + tên + caption policy (nếu khác Standard) + check ở active; tap = chuyển active; swipe Edit/Delete. Alert chặn xoá: "You need at least one identity." / "Make another identity the default first."
- **Editor sheet**: Name + Type (Personal/Professional/Pseudonymous/Anonymous/Custom) + Privacy (Standard / Isolated / **Strictly anonymous** — footer mô tả động; strictly anonymous: không bao giờ gợi ý/tìm kiếm chéo danh tính khác).

### 12.3 Private Email (alias) — theo persona
- **Màn Private Email**: nhóm **Địa chỉ theo dịch vụ** / **Địa chỉ dùng nhiều nơi**, trạng thái và một CTA tạo; lối vào **Dịch vụ liên kết**, hộp thư nhận, domain và notice chỉ nhận thư phía dưới nội dung chính.
- **Row alias**: địa chỉ xuống dòng khi dài, tên gợi nhớ/website hoặc chưa liên kết và trạng thái chữ riêng.
- **Chi tiết alias**: copy/activate/resume phù hợp trạng thái; actual forwarding checkpoint tách desired recipient. Management menu có sửa tên, liên kết Login, pause/delete với xác nhận.
- **Tạo email riêng**: chọn loại, tên gợi nhớ/website/Login tùy chọn, domain và inbox xác minh. Chưa có Login vẫn tạo được; lỗi giữ input và reservation, retry cùng địa chỉ/inbox. Domain mất eligibility trước mint yêu cầu chọn lại rõ ràng.
- **Dịch vụ liên kết**: global/per-alias list, mở Login và gỡ đúng association có xác nhận. Một alias dùng cho nhiều Login; gỡ chỉ thay canonical Private email field/pointer tại vault-local, giữ email/username thật và forwarding. Legacy Email/username match chỉ xuất hiện trong review riêng.
- **Forwarding inboxes**: list hộp thư nhận (email che + chip xác minh: "Verified" xanh / "Awaiting confirmation" vàng / "Not verified") + tag "Default"; menu Check verification / Resend / Set as default / Delete; section **rotation** khi cần cập nhật alias hàng loạt (progress "x of y").
- **Inbox detail**: mở có chủ đích trong vault unlocked để đọc/copy email local đầy đủ, có Ẩn/Hiện. Background/lock/exit conceal tức thời; foreground không tự reveal lại. Coordinator chung refresh pending visible, chỉ ghi verified từ server cho đúng email/destination/generation.
- **Domain picker**: accepted signed registry hiển thị cả domain chưa cho tạo với readiness reason; current `loox.pw` chưa được native patch bật. Aliases đã mint giữ suffix; unknown nonlegacy không được copy nhầm domain legacy.
- Lỗi local field/ownership, CloudKit, App Attest và mạng giữ nguyên nguyên nhân/recovery phù hợp. Native/device acceptance xem implementation report nội bộ.

### 12.4 Capability banner (component dùng chung cho tính năng online)
Banner bo tròn accent nhạt (KHÔNG đỏ — đỏ dành cho destructive): **Offline** ("No Internet Connection…") / **Temporarily unavailable** (+ nút Try Again) / **Maintenance** / **Currently unavailable** (operator tắt) / **No longer available** (retired). Available/user-off → không render banner.

---

## 13. Chia sẻ (Sharing)

### 13.1 Share Access sheet (chủ sở hữu, mở từ nút Share trên detail)

**Nguyên tắc: chủ sở hữu chỉ quyết định MỘT lần.** Phạm vi chia sẻ được đóng băng vào
`ItemShareRecord` (`plannedCapabilities` + `plannedAllowMultipleDevices`) ngay khi bấm Create.
Grant chỉ niêm phong được sau khi có khoá công khai của bên nhận, nhưng đó là ràng buộc của
crypto chứ không phải của người dùng — nên `ShareActivationService` phát grant tự động khi khoá
tới, cả trong sheet lẫn ngoài sheet (`OwnerShareRefresher`). Không còn bước cấu hình lần hai.

**Máy trạng thái 8 bước:**
1. **Choose**: 2 lựa chọn — **Quick Link** vs **Share with a Loox user**.
2. **Checking**: spinner kiểm tra điều kiện.
3. **Blocked**: fail-closed — chưa đăng nhập iCloud hoặc chưa cấp quyền notification + **Check Again**.
4. **Config** (form chính):
   - Section **"Share with"** *(chỉ hiện khi đã có người)* — danh sách người từng chia sẻ trong
     persona đang hoạt động, chạm để điền; lọc theo persona vì việc tái dùng zone là
     persona-scoped (`SpaceShareZoneDedupe`), đề xuất sai persona sẽ âm thầm đẻ zone mới.
   - Field email người nhận (footer: gắn với tài khoản iCloud).
   - **"What they can use"** — field thường → Toggle; **TOTP** → *Off / Ask each time / Hand over secret…*;
     **passkey** → *Off / Ask each time / Hand over key…*; field extra-protected & attachment → "not shareable".
   - Toggle **"Allow use on multiple devices"** (mặc định ON).
   - **"Shared with N"** + swipe-to-revoke.
   - Nút **Create Share** (disable đến khi email hợp lệ + ≥1 quyền).
5. **Creating**: spinner. Tái dùng zone của người nhận nếu đã có → bên nhận không phải accept lại.
6. **Waiting**: "Waiting for them to accept…" + Nudge via Messages / Share invite link / Check now.
7. **Publishing → Done**: khi profile của bên nhận tới, grant phát **tự động**, không hỏi gì thêm.
8. **Failed**: `VaultStatusScreen` + Try Again.

Màn **"Ready to activate"** (so mã an toàn) đã **bị xoá** cùng `TrustFingerprintView`: nó yêu cầu
so mã với máy bên kia, trong khi mã bên nhận suy ra từ grant và grant chỉ tồn tại SAU khi chủ sở
hữu bấm Activate — tại thời điểm hỏi, bên nhận chưa có mã nào. Xem 13.3 cho cơ chế thay thế.

**Dialog quan trọng:** "Stop sharing this item?" (chỉ mục này, các mục khác giữ nguyên; giá trị đã
giao không rút lại được); **"Hand over this secret/passkey?"** → "Hand Over — Can't Be Taken Back".

### 13.2 Quick Link (link mã hoá cho bất kỳ ai)
- **Loox Member → Share Links**: root riêng theo active persona, chọn item trước khi mở flow Quick Link bên dưới; chỉ quản lý metadata link còn hạn trên thiết bị này. Historical rows không copy lại working URL vì key fragment không lưu.
- **Config**: toggle từng field (preview che "••••••••" với secret; TOTP & extra-protected không bao giờ chia sẻ được) + Toggle **One-time link** (OFF → Picker hạn: 5/10/15/30 phút, 1h, 24h, 7 ngày, 30 ngày; footer copy khác nhau cho one-time vs có hạn) + **Active links** (ngày tạo + badge "One-time" + hạn còn lại; swipe revoke + dialog "Anyone who has the link loses access immediately."; footnote "chỉ revoke được từ máy này").
- Nút Create theo trạng thái capability: Available → "Create Link"; Offline / Maintenance / Retired / User-off → thông điệp thay nút (lịch sử link vẫn hiển thị).
- **Result** (nơi duy nhất key giải mã tồn tại): check xanh "Link ready" + URL rút gọn giữa + cảnh báo phạm vi + dòng hạn ("disappears after it's opened once" vàng, hoặc "Expires …") + **Copy Link** / Share Link / **Shorten Link** *(khi backend cấp token)* / Done. Shorten lỗi → "Short links are temporarily unavailable" (share vẫn thành công).

### 13.3 Nhận chia sẻ (recipient)

**Quyết định tin cậy nằm ở bước ACCEPT, kèm danh tính người gửi.** Trước đây link universal
được accept **im lặng, không xác nhận gì**, còn bên nhận không thấy tên người gửi ở đâu cả — dòng
lời mời chỉ ghi "Share invitation" + thời gian. Nay cả hai đường (link của Loox và rendezvous)
đều resolve `CKShare.Metadata.ownerIdentity` (vốn đã được fetch rồi vứt đi) và hiện
"*<người gửi>* muốn chia sẻ với bạn" trước khi gọi `container.accept`. Không resolve được tên thì
nói thẳng là chưa xác nhận được, và vẫn bắt buộc chạm để đồng ý.

Hệ quả: `OwnerKeyVerification` có thêm case `.accepted` — accept đã là "người dùng đồng ý với
người gửi này", nên lần pin đầu ghi `.accepted` thay vì `.pending`, và **bức tường so mã chặn
lần dùng đầu đã bị gỡ**. Giữ nguyên: marker thiếu vẫn đọc là `.pending` và không vào AutoFill
(fail-closed), pin vẫn **từ chối** khoá đổi thay vì pin lại (mạnh hơn so mã tay và miễn phí), và
quyết định chỉ đi LÊN theo `supersedes` nên marker tự động không bao giờ ghi đè việc ai đó thật
sự đã so mã. So mã an toàn còn lại dạng **tuỳ chọn, không chặn, kèm nút sao chép**.

- **Notifications** (chuông trên Home): dòng lời mời hiện **tên người gửi**; sections **Share
  invitations** · **Approval requests** · **Shares you sent** · **Recent**.
- Alert nhanh toàn cục khi có lời mời mới, cùng câu chữ với đường link (dùng chung `InvitePrompt`).
- **Shared with Me** (trong Items): trống → "Nothing shared with you yet"; có → list item mở detail chuẩn (bản read-only, xem mục 9 + 9.4).
- **Request Code row** (field TOTP dạng ask-each-time trong detail): *idle* → nút "Request Code" → *requesting* (spinner) → *waiting* (spinner + **"Match code: NNNNN"** khớp mã trên máy chủ sở hữu; chờ lâu → "This is taking longer than usual." + Request Again) → *approved* (mã tap-to-copy + vòng 30s + menu Copy/Large Type + "Use it now — it expires with the current window.") / *rejected* ("Request declined") / *interrupted* / *expired* / *failed*. Trạng thái cuối luôn có "Request Again".

### 13.4 Phê duyệt (chủ sở hữu) — Approval Request sheet
- *Idle*: shield + "Code requested"/"Sign-in requested" + tên người & item + **card mã đối chiếu 5 số** ("It should match the code on their screen.") + **Approve with Face ID** / Reject.
- *Authenticating* → "Confirming it's you…"; ***Waiting for fresh window*** → "Preparing a fresh verification code…" (không bao giờ gửi trước mã của chu kỳ sau); *Issuing* → "Sending the code…".
- *Finished*: approved → "Code sent" (tự đóng 1.5s) / rejected → "Request rejected". *Failed* → thông điệp + Close. Không đóng được sheet khi đang xử lý.

### 13.5 Quản lý người nhận (Share Details sheet)
Info (**Item** kèm icon category + Recipient/Status/ngày) + chỉnh quyền trên grant sống ("What they
can use") + chế độ cập nhật ("Update automatically") + **Stop sharing this item** (nút đỏ chữ trắng,
`destructiveFill` + `onDestructive`). Một nút **Apply** duy nhất trên toolbar (phải), chỉ bật khi có
thay đổi chưa gửi: đổi quyền, hoặc item đã sửa sau lần publish cuối mà "Update automatically" đang tắt.

- **Một nút Apply thay cho hai.** "Send update now" (re-seal giá trị hiện tại) và "Apply changes"
  (publish lại grant) trước đây cùng một việc: publish grant đã re-seal giá trị hiện tại kèm theo.
  Apply đi qua `SharedGrantComposer` nên giữ đúng device scope và blob passkey đã giao.
- **Giao hẳn (hand over) có bước xác nhận riêng** (`ShareHandOverConfirmView`, chiếm cả sheet):
  hậu quả, nút đỏ "Hand over", rồi trạng thái đang giao / đã giao / lỗi + thử lại. Không dùng
  dialog hệ thống vì dialog mở từ trong sheet làm mất state (xem `InlineConfirm`). Mọi lựa chọn chế
  độ đi qua `ShareCapabilityDraft.select`, nên không còn hàng nào "nuốt" lựa chọn giao hẳn (lỗi cũ:
  giao hẳn → hỏi mỗi lần → giao hẳn lại không có tác dụng với TOTP).
- Đọc bản ghi share **sống** từ `SharingStore` (không dùng bản chụp lúc mở sheet): công tắc tự cập
  nhật phản hồi ngay, và Apply lưu `grantId` mới.

- Sheet **nêu tên mục**: nó mở được từ cả một MỤC lẫn một NGƯỜI, và khi mở từ Family thì trước đây
  không có gì trên màn nói đang cấu hình mục nào.
- **Thu hồi theo từng mục**: trước đây gọi `revoke(zoneName:)` = xoá cả zone, nên thu hồi 1 mục
  kéo theo **mọi mục khác** đã chia sẻ với người đó, trong khi dialog chỉ nói họ hết xin được mã.
  Nay dùng `revokeGrants(forItemId:)` (theo item, không theo `grantId` đã lưu: mỗi lần Apply sinh grant
  mới nên id cũ có thể không còn) + `remove(zoneName:itemId:)`, chỉ xoá zone khi đó là mục cuối cùng.
- Không đọc được grant sống (offline/throttle) → banner cảnh báo, thay vì sheet trông như share
  chẳng cấp quyền gì với mỗi nút Revoke.

### 13.7 Family (Profile → Family, hub tile cùng tên)
Không có thực thể "nhóm gia đình" trong code: thành viên là phép gom `SharingStore.shares` theo
người nhận — **lời mời CHÍNH LÀ quan hệ**, không có gì để "tham gia" trước. Màn hình vì thế có
hành động **"Share with family"** làm primary, mở scope chooser một item hoặc Space.
Item đi vào Approval Mode sharing rõ ràng, không vòng qua Quick Link. Counts/list dùng
current persona ownership; thiếu folder hoặc item mồ côi không gán sang persona mặc định.

- Row người: avatar chữ cái + email + phụ đề tách bạch "đã chia sẻ" và "đang chờ" (trước là một
  con số trần, đọc như badge chưa đọc và gộp cả lời mời chưa accept).
- Màn chi tiết người: danh sách **vault item** đọc trực tiếp từ store (trước là snapshot chụp lúc
  push, revoke xong quay lại vẫn thấy row đã mất), kèm icon category; row đang chờ mở
  `ShareResumeStepperSheet`, row active mở `ShareRecipientDetailSheet`; có empty state.

### 13.6 "Open on Computer" (Quick View — giao field 1 lần cho trình duyệt)
- **Loox Member → Send to Browser**: root riêng có hướng dẫn viewer, item chooser và lịch sử local attempts. History không giữ fields/codes/keys hay mô tả hoạt động từ browser; entry vẫn theo signed rollout/capability/commerce gates hiện có.
- **Chooser**: "Scan QR Code" / "Enter Code" (footer "You'll pick exactly what to share on the next screen.").
- **Scan**: camera tối, hint "Point the camera at the code on your computer".
- **Enter Code**: ô `XXXX-XXXX` mono tự format; lỗi định dạng: "That code doesn't look right."
- **Approval sheet** (máy trạng thái): *resolving* ("Connecting to your computer…") → *verified*: globe + "A browser wants to view fields from {item}" + **card Safety phrase (SAS)** ("Make sure this matches the phrase shown on your computer.") + đếm ngược "Expires in N seconds" + toggle từng field (bật Password → cảnh báo "Password will be visible on this computer."; toggle "Current 2FA code" nếu có) + **Approve with Face ID** + nút đỏ **"They don't match"** (không có đường "continue anyway") → *approving* → *done* ("Sent to your browser… once.") / *error* (mọi lỗi gom về 1 thông điệp chung "Start again on the computer.").

---

## 14. AutoFill extension (điền vào app khác / Safari)

Extension dùng material hệ thống (không dùng token app). Mọi luồng đi qua **Unlock Gate**:
- Face ID tự chạy (logo + spinner) → fail/không đăng ký → **form mật khẩu** (logo + SecureField "Master password" + lỗi đỏ "Incorrect master password." + nút Unlock + nút "Unlock with Face ID" nếu có) + Cancel.
- Đã unlock từ bước trước (passkey → fallback password) thì **không hỏi Face ID lần 2**.

**Các màn:**
1. **Danh sách đăng nhập**: hàng "＋ Create new login" → sections **"For this app"** (khớp domain) / **"Other logins"**; trống → "No logins found". Item nhận chia sẻ đánh dấu **"· Shared"**; **offline → ẩn toàn bộ hàng shared** + footnote "Shared items need an internet connection." Chọn item shared → spinner xác minh grant; bị revoke/lỗi → alert tương ứng. Context menu "Use private email" (khi login có alias).
2. **Create new login**: Website (điền sẵn host) + Username (từ identity mặc định) + Password (tự sinh, mono) + Regenerate → **Save & fill**. Lỗi: "Couldn't save the login."
3. **Save password** (iOS 26.2 native): xác nhận Website/Username → Save.
4. **One-time code (2FA)**: tự điền khi chỉ có 1 khớp; ngược lại picker "For this app"/"Other codes" (mã KHÔNG hiện trong list, chỉ sinh khi tap); trống → "No 2FA codes found".
5. **Passkey — đăng ký**: card xác nhận Website/Username + nút **Create Passkey** (spinner khi xử lý; lỗi giữ sheet + footer đỏ).
6. **Passkey — đăng nhập**: >1 tài khoản → picker "Choose a passkey" (userName + lần dùng gần nhất); 1 tài khoản → tự ký (spinner); **passkey chia sẻ ask-each-time** → spinner "Waiting for the owner to approve…" + Cancel (từ chối → "The owner declined this sign-in."; quá hạn → "No answer from the owner yet."); không có passkey → fallback sang picker mật khẩu (không Face ID lại) hoặc lỗi "No passkey for this site."

---

## 15. Checklist trạng thái khi thiết kế mỗi màn hình

1. **Empty / Loading / Error / Success** — mỗi màn phải có đủ (xem pattern mục 0).
2. **Item của mình vs item được chia sẻ** — chia sẻ = read-only, thêm cổng online 6 trạng thái, hành động Leave thay Delete.
3. **Online vs Offline** — giá trị chia sẻ, tạo Quick Link, alias email, erase vault khi còn alias: tất cả có trạng thái offline riêng.
4. **Có biometric vs không** — ẩn hẳn row/bước liên quan, đổi copy theo Face ID/Touch ID.
5. **Khoá chủ động vs tự động** — chủ động thêm bước slide-to-unlock.
6. **Light/Dark + 7 accent + Reduce Motion/Transparency + Dynamic Type 6 mức** — mọi màn phải kiểm tra.
7. **Hành động không hoàn tác** — luôn có dialog xác nhận với nút đỏ, copy nói rõ hệ quả ("Can't Be Taken Back", "cannot be undone", "previous recovery key will stop working").
8. **Bí mật trên màn hình** — spoiler/che mặc định, tap-to-copy có toast, clipboard tự xoá, privacy shield trong App Switcher, không render secret trước khi qua cổng xác thực.

## 16. Shell đa nền tảng (Mac/iPad — bổ sung sau registry sweep 260711)

`AdaptiveRootView` chọn shell theo size class: iPhone dùng `MainTabView` (native TabView,
icon-only, Search tab role .search trên iOS 18+); regular-width (iPad/Mac) dùng sidebar
(`VaultSidebarView`/`VaultSidebarList`). macOS có chrome riêng: `MacRootView` (3 cột),
`MacHeaderBar` (search suggestions panel), `MacSidebarList`, `MacItemListColumn`,
`MacSettingsView` (native Settings window qua openSettings). `VaultTabBar`/`VaultTabBarBackground`
là shell cũ đang dormant có chủ đích (giữ code, không dùng runtime — xem design-guidelines).
Mac hiện là trải nghiệm review-light: iPhone-first, sync đa thiết bị chưa hoạt động
(Vault Key không sync — xem plan iPad+Mac).

## Ghi chú cho team design (gap hiện tại đáng cân nhắc)

- ~~Field kiểu **Date** trong editor đang là ô text thường~~ — đã có DatePicker (follow-up 260711).
- ~~**Approval Mode** không có toggle trong Settings~~ — đã surface toggle (follow-up 260711).
- Theme chỉ surface **Day/Night**; wallpaper picker + custom theme editor có sẵn code nhưng đang tắt (có thể bật lại sau).
- ~~Không có màn Settings riêng cho Notifications~~ — đã có surface Notifications (follow-up 260711).
