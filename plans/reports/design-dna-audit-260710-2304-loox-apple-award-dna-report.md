# Loox × Apple Design DNA Audit (260710)

Scope: đối chiếu 10 DNA (protagonist, glass, concentricity, typography, motion, ergonomics, progressive disclosure, personality, physics, search) với code hiện tại trên `main` (P0-P5 pass 13 đợt, chưa commit). Mỗi mục: hiện trạng có bằng chứng → đề xuất.

---

## DNA #1 — One protagonist per screen

**Hiện trạng:** `HomeScreen.swift:170-207` — 8 tầng: profileRow → quickActionsGrid → pendingShares* → approval* → TOTP* → attention* → favorites* → allItems (*conditional). Credential đầu tiên user thấy nằm ở tầng 5+. Hero position = profile row (nói về danh tính user) + quick grid 4 ô (nói về feature app).

**Đề xuất (T2, đảo layout đã duyệt → cần user xác nhận):**
- Protagonist = "find & use credential instantly": đẩy nội dung sống lên đầu — TOTP đang chạy / recently-used / attention; profile row thu về header hoặc 1 hàng mỏng.
- Quick actions 4 ô → gọn (1 hàng nhỏ hoặc chỉ Add nổi); Watchtower/2FA count là secondary.

## DNA #2 — Glass = controls; đừng đóng mọi thứ vào card

**Hiện trạng tốt:** glass chỉ ở đúng control layer: QuickActionCard, tab bar (`VaultTabBarBackground`), screen header (`VaultScreenHeader`), 1 chỗ editor row. Scroll content chạy sau floating header (`HomeScreen.swift:105-128`) ✓ continuity chuẩn WWDC25.

**Hiện trạng xấu — card disease ở ItemDetail:** `ItemDetailScreen.swift` stack 6+ stroked cards: Space pill card, sharedBadge card (:406-416), fieldsCard, safetyCodeCard, sharingSection card, trashCard (:500-546), metadata. Mọi group đều `VaultColors.surface` + hairline stroke → đúng "generic SwiftUI settings app".

**Đề xuất (T2):**
- Card chỉ cho semantic grouping thật: fieldsCard (giữ), sharing list (giữ). sharedBadge → banner phẳng không stroke; metadata → plain text (đã gần đúng); trashCard → bỏ khỏi body (xem DNA #7).
- Home groupedCard hairline stroke (`HomeScreen.swift:627-637`): cân nhắc bỏ stroke, để elevation/spacing nói chuyện hierarchy.

## DNA #3 — Concentricity

**Hiện trạng:** `Radius.swift` scale 6/10/14/20/28/pill là token rời, không có quan hệ. Vi phạm cụ thể:
- ProfileRow (`HomeScreen.swift:329-355`): outer lg=20, padding s4=12 → inner concentric ≈ 8, avatar dùng 10 (:359) — hơi flared.
- QuickActionCard: card lg=20, glyph badge 34pt inset s4=12 → badge radius nên ≈ 8; kiểm tra `GlyphBadgeSurface`.
- fieldsCard md=14 (rows không bo) — OK.

**Đề xuất (T1, additive không phá token):**
- Thêm helper `Radius.concentric(outer:inset:)` = `max(outer - inset, xs)` vào `Radius.swift` + doc quy tắc "R_inner ≈ R_outer − inset" trong `docs/design-guidelines.md`.
- Audit pass các nested shape: ProfileRow avatar, QuickActionCard badge, editor rows, sheet-embedded tiles.

## DNA #4 — Typography là architecture

**Hiện trạng:** `Typography.swift` VaultType 10 roles — hợp lệ, nhưng bị bypass nhiều: `ItemDetailScreen.swift:306` `.font(.title2.bold())`, `DetailFieldRow.swift:47` `.font(.caption.weight(.medium))`, `:116` `.font(.subheadline)`, TOTPCodeView `.font(.body.weight(.bold))`. Architecture có, enforcement không.

**OTP:** đã group `381 942` (`TOTPFieldRow.swift:16-20`) ✓ nhưng render SF body 17pt — chưa phải typographic object.

**Mono discipline:** MonoLisa chỉ cho secrets ✓ đúng "tránh mono hóa toàn app".

**Đề xuất (T1):**
- Sweep thay raw `.font(...)` bằng `vaultType` ở ItemDetail/DetailFieldRow/Home (giữ đúng 10 roles, không thêm).
- OTP lên `vaultCode(.title3, weight: .semibold)` + tabular — credential as typography object.

## DNA #5 — Motion giải thích quan hệ không gian

**Hiện trạng:**
- Unlock: không có motion — success → view bị thay thế khô (`LockScreen.swift:187`). Logo là wordmark PNG asset (`BrandLogoMark.swift`) → KHÔNG làm được ∞-gate motion nếu chưa có vector mark. **Asset dependency → ADR.**
- Reveal: `DetailFieldRow.swift:127-131` `withAnimation { revealed.toggle() }` swap SpoilerText ↔ Text = whole-field crossfade — đúng anti-pattern DNA nêu.
- Copy: row flash accent + text swap "Copied" (`DetailFieldRow.swift:56,73`) — ổn nhưng chưa icon morph.
- Search→detail: push thường, không hero transition.

**Conflict:** DNA gợi ý SF Symbols animation — project CẤM SF Symbols (Polaris SVG only). Copy morph phải tự dựng (crossfade 2 Polaris icon + scale + haptic).

**Đề xuất:**
- (T2) Glyph-resolve reveal: per-character staggered resolve (dots → chars), component mới tái dùng cho mọi secret field. Reduce Motion → instant.
- (T2) Copy feedback: Polaris copy-icon → check-icon morph + `Haptics` tick, giữ row flash.
- (T3) ∞ gate unlock/lock motion — cần vector logo mark trước.
- (T3) Search→detail: `navigationTransition(.zoom)` iOS 18+ guard, fallback push.

## DNA #6 — One-handed ergonomics

**Hiện trạng khá tốt:** copy = tap cả row (`DetailFieldRow.swift:59`) — target lớn ✓. Search = tab dưới (thumb zone) ✓. Add: top-right header + quick card — F2 nên chấp nhận được.

**Gap:** ItemDetail login — dominant action (copy password) nằm giữa scroll; share/menu top-right.

**Đề xuất (T3, ADR):** bottom floating "Copy Password" cluster CHỈ cho login có password, chỉ khi field ngoài viewport; không áp mọi màn.

## DNA #7 — Progressive disclosure

**Hiện trạng:** ItemDetail stack đủ: header → tags → fields → passkeys → sharing → **trashCard luôn hiện** → metadata. Trash = Layer C nhưng chiếm body position; đồng thời Archive đã nằm trong "…" menu → destructive bị phơi 2 chỗ.

**Đề xuất (T1):** trashCard bỏ khỏi body cho item sống ("Move to Trash" vào "…" menu, đã có confirm dialog); item trong Trash giữ Restore/Delete card. Metadata gộp 1 dòng. Layer A (fields) nổi lên ngay sau header.

## DNA #8 — Personality ở micro-detail ("calm intelligence")

**Hiện trạng:** tone đã gần chuẩn: "Copied", "This can't be undone.", empty state "Everything is encrypted on this iPhone before it's stored." ✓. Lỗi còn:
- `OnboardingFlow.swift:91` "Welcome to Loox!" — exclamation duy nhất.
- Em-dash style AI: `ItemDetailScreen.swift:410` "Shared with you — you can use…" (user yêu cầu bỏ văn kiểu AI gạch dài) → sweep toàn `Localizable.xcstrings` EN+VI.
- DNA gợi ý "Copied securely." — KHÔNG khuyến nghị: clipboard không secure thật. Trung thực hơn: "Copied" hoặc "Copied · clears in 60s" nếu clipboard auto-clear đang bật (ClipboardService có `sensitive:`).

**Đề xuất (T1):** copy-tone pass toàn catalog: ngắn/tĩnh/tự tin, bỏ "!", bỏ "—", EN+VI đồng bộ.

## DNA #9 — Physics: "Controlled Reveal"

**Đánh giá:** metaphor đúng và app đã có nguyên liệu: SpoilerText, ProtectedFieldRow (Face-ID gate), SharedAccessGateView, privacy shield, LargeTypeView, slide-to-unlock. Thiếu: một ngôn ngữ motion thống nhất hidden↔visible.

**Đề xuất (T3, ADR đầu tiên):** viết "Loox Motion Language: Controlled Reveal" vào `docs/design-guidelines.md` — mọi trạng thái chuyển hidden↔visible dùng cùng resolve/blur vocabulary: glyph resolve (field), blur→clear (unlock), seal→expand (protected note), contract→∞ (lock). Code hoá dần: T2 glyph resolve là viên gạch đầu.

## DNA #10 — Search superpower

**Hiện trạng:** `SearchScreen.swift:80-85` zero-state = ContentUnavailableView chết. Không recents, không quick filters. Token search AND theo title/fields/tags — không có operator.

**Đề xuất (T2):**
- Zero-state: Recently used (repository đã có `markUsed`) + quick filter chips (Codes / Passkeys / Cards / Weak).
- Operator search local (không AI, không network): `2fa`→có TOTP, `weak`/`reused`→PasswordAudit, `passkey`, category tokens. Localize keyword EN+VI.

---

## Gói thực thi đề xuất

| Tier | Nội dung | Rủi ro |
|------|----------|--------|
| **T1 an toàn** | copy-tone pass (bỏ !, —); OTP typographic object; `Radius.concentric` + nested fix; vaultType sweep; ItemDetail trash→menu + metadata gọn | thấp, không đảo quyết định cũ |
| **T2 structural** | Home protagonist reorder (**đảo layout user vừa duyệt — cần confirm**); card-diet ItemDetail/Home; glyph-resolve reveal; copy icon-morph; search zero-state + operators | trung bình |
| **T3 brand/ADR** | ∞ gate motion (cần vector mark); Controlled Reveal doc + blur unlock physics; bottom action cluster; zoom transition iOS 18+ | cần quyết định user + asset |

## Ràng buộc kỹ thuật
- iOS 17.6 ceiling: zoom transition/`glassEffect` phải availability-guard (đã có pattern).
- Polaris SVG only — không dùng SF Symbols animation.
- Localize EN+VI mọi string mới/đổi.
- P0-P5 pass 13 đợt CHƯA commit — nên commit/ship trước khi mở DNA pass để diff sạch.

## Unresolved questions
1. Commit P0-P5 trước khi bắt đầu DNA pass? (khuyến nghị: có)
2. T2 Home reorder đảo layout DS-spec vừa làm — user confirm?
3. Vector ∞ mark có sẵn không (SVG/PDF path) hay cần vẽ? Block T3 gate motion.
4. Clipboard auto-clear interval thực tế — để chốt copy string "clears in Ns".
