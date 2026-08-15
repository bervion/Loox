# Extension brand + vault-row alignment (AutoFill native + Safari web)

Owner feedback 260815: extension hiện logo dạng text "LOOX" thay vì logo animation/dots; Safari extension thiếu icon ở item gợi ý, không khớp UI Home/Search; UI web thô, corner quá tròn, thiếu tự nhiên. Yêu cầu rà soát tổng thể cả hai extension.

## Root causes

- `UnlockGate` render `BrandLogoMark` = ASSET WORDMARK "LOOX" (chữ), không phải symbol 6 vòng tròn; symbol + animation (`LooxLogoBreatheView`) nằm ở app target, extension (chỉ link VaultifyCore) không với tới.
- Row item ở popup + inline menu Safari chỉ có chữ (title/subtitle), không có avatar; AutoFill picker native cũng vậy.
- Web CSS: radius dùng số của token native nhưng CSS corner là cung tròn (không phải continuous curve của iOS) nên cùng giá trị nhìn tròn hơn — nguồn cảm giác "quá tròn, thiếu tự nhiên".
- Bug thật phát hiện qua preview: `.state { display: flex }` (author origin) ĐÈ `hidden` attribute (UA origin) — mọi section "ẩn" của popup thực ra vẫn chồng lên trang. Fix: `[hidden] { display: none !important }`.

## Changes

Native:
- `LooxAnimationGeometry.swift` + `LooxLogoBreatheView.swift` chuyển vào `VaultifyCore/` (git mv, cùng module — 5 file app dùng geometry không đổi gì).
- `UnlockGate`: trạng thái chờ Face ID = symbol thở 96pt; form mật khẩu = symbol 84pt + wordmark compact bên dưới (lockup như lock screen app).
- `VaultifyCore/MonogramAvatar.swift` mới: initials + màu hue ổn định (djb2 64-bit) — single source; app `ItemThumbnail` delegate sang (không đổi hành vi); `CredentialAvatarView` cho extension.
- AutoFill picker row: avatar monogram 36pt dẫn đầu row, cùng initials + hue với row ở Home.

Safari web:
- Popup header: symbol Loox 6 vòng THẬT làm SVG inline (trace từ LooxAnimationGeometry: centers/gradients/glow/star), breathe 4s CSS, tắt theo prefers-reduced-motion.
- Row icon: login = monogram tile (hue parity CHÍNH XÁC với native qua BigInt djb2 — verify Swift vs node: GitHub 296, Google Work 115, Máy chủ nhà 76, Vietcombank Visa 339, trùng 100%); identity/card = glyph duotone createElementNS tint theo VaultColors.category (giữ contract no-innerHTML).
- Corner scale mới (bù chênh circular vs continuous): row/card 10, control trong row 8, button đứng riêng 12; press states `:active`; title row 16.
- Inline menu: glyph category + layout flex + radius 8 + active state; save-overlay giữ nguyên (đã đúng scale: sheet 16, button 12 — có chủ đích, không phải bỏ sót).
- `[hidden]` fix ở popup.css.

Dev tooling (committed):
- `DevFixtures/popup-preview.html` + `inline-menu-preview.html`: stub `browser`/collaborators, load css/js THẬT → screenshot được ở browser thường; `?lang=vi`. Serve bằng `python3 -m http.server 8765 --directory VaultifySafari` (launch config `.claude/launch.json` là local-only, repo gitignore thư mục đó).

## Verification

- 4 node harness (inline-menu, fill-engine, field-classifier, signup-detector): pass.
- Hue parity Swift ↔ JS: pass (4/4 titles).
- Popup preview: light + dark + VI (ĐĂNG NHẬP/DANH TÍNH/THẺ, Sao chép/Điền, Ẩn trên trang này — không tràn). Inline menu preview: panel + glyph + footer đúng.
- `make check` (app + AutoFill appex iOS): pass. Localization: không thêm string user-facing mới (icon aria-hidden).

## Unresolved

- UnlockGate mới chưa chụp được runtime (Credential Provider cần host process thật); đã compile + cấu trúc từ component có sẵn của app. Owner thử trên TestFlight khi lên bản.
- Safari appex bundle (`com.bervion.vaultify.safari`) native slice không đổi; web bundle đổi — cần một lần build scheme Safari trong Xcode khi tiện để chắc resource copy (không có trong make check).
