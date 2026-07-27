# Phase 08 — Localization strings, EN + VI

**Depends on:** phase-02, 04, 05, 06.
**Two destinations with different rules** — do not mix them up.

---

## The two surfaces

**A. iOS app strings → `Vaultify/Localizable.xcstrings`. MANDATORY EN + VI.**
The project rule is absolute: no user-facing text ships without a Vietnamese value, and a missing
VI value is a bug. New `LocalizedStringResource` titles use `.inAppLocalized`; runtime strings use
`appString()`. Design for the longest localized label, which is usually VI.

**B. `/open` page strings → the Cloudflare Worker, currently English-only.**
The document is hard-coded `lang="en"` and every string in `open-page.ts` and `TERMINAL_COPY` is
an English literal. The app's mandatory EN+VI rule is written for the app, not this worker, so
page localization is a **product decision, not a rule violation**.

But there is a real mismatch worth deciding on: `LooxLinkEnvelope.build` localizes field labels to
the **owner's** in-app language, so a Vietnamese owner's share already renders "Mật khẩu" inside
English page chrome — mispronounced by screen readers and visually mixed. Under decision A this
gets worse: a Vietnamese-labelled card would sit under an English "Payment Card" header.

**Open question (blocking for section B only):** does `/open` get a VI UI? If yes it needs an
`Accept-Language` or `?lang` switch and two copies of every string below. VI values are provided
either way so the decision is not blocked on translation work.

Copy style applies to both: no exclamation marks, no em dashes, no middot separators. Separate
ideas with layout or with words.

---

## A. App strings — `Localizable.xcstrings` (mandatory)

From phase-02.

| EN | VI | Where |
|---|---|---|
| Select at least one field to share. | Chọn ít nhất một trường để chia sẻ. | `QuickViewApprovalFieldsSection` — empty-selection hint |
| No fields were selected to share. | Chưa có trường nào được chọn để chia sẻ. | `.noFieldsSelected` compose error |

Reuse existing entries, do not duplicate: `Approve with Face ID` / `Phê duyệt bằng Face ID`,
`Current 2FA code` / `Mã 2FA hiện tại`.

## B. Page strings — the Worker

### B1. Existing strings that change (phase-01, 04)

| Slot | EN | VI |
|---|---|---|
| terminal `expired` title | Session expired | Phiên đã hết hạn |
| terminal `expired` body | Nobody approved this session in time. Nothing was sent to this page. | Không có ai phê duyệt phiên này kịp thời. Không có dữ liệu nào được gửi tới trang này. |
| terminal `locked` body | This view was locked after the tab was hidden. Start a new session to see the fields again. | Chế độ xem đã bị khóa sau khi thẻ bị ẩn. Hãy bắt đầu phiên mới để xem lại các trường. |
| terminal `closed` body | This session has been closed and the fields are cleared. | Phiên này đã đóng và các trường đã được xóa. |
| terminal `error` body | This Quick View could not be opened. Start a new session from the app. | Không thể mở Quick View này. Hãy bắt đầu phiên mới từ ứng dụng. |
| waiting sub | Scan this code with Loox on your iPhone and approve with Face ID. The fields appear here exactly once. | Quét mã này bằng Loox trên iPhone và phê duyệt bằng Face ID. Các trường chỉ hiện ra đúng một lần. |
| approved body | Approved on your phone. Verifying and decrypting. | Đã phê duyệt trên điện thoại. Đang xác minh và giải mã. |
| clipboard warning | Copied to this computer's clipboard. Clear it when you are done. | Đã sao chép vào bộ nhớ tạm của máy tính này. Hãy xóa khi bạn dùng xong. |
| done button | Done and close | Xong và đóng |

### B2. New terminal states (phase-04 R1, R2, R3, R6)

| Slot | EN | VI |
|---|---|---|
| `timeout` title | Fields cleared | Đã xóa các trường |
| `timeout` body | Your 5 minutes are up and the fields have been wiped from this page. Approve again from the app to see them once more. | Đã hết 5 phút và các trường đã bị xóa khỏi trang này. Hãy phê duyệt lại từ ứng dụng để xem thêm một lần nữa. |
| `rate_limited` title | Too many attempts | Quá nhiều lần thử |
| `rate_limited` body | Too many sessions were started from this network. Wait a few minutes and try again. | Quá nhiều phiên được bắt đầu từ mạng này. Hãy đợi vài phút rồi thử lại. |
| restart button | Get a new code | Lấy mã mới |
| restart hint | You will need to scan the new code and approve again on your phone. | Bạn sẽ cần quét mã mới và phê duyệt lại trên điện thoại. |

### B3. New waiting and rendered strings (phase-04 R1, R4, R5)

| Slot | EN | VI |
|---|---|---|
| QR fallback | The code image could not be drawn. Type the code above into Loox instead. | Không thể vẽ hình ảnh mã. Hãy nhập mã ở trên vào Loox. |
| autolock hint | Switch away from this tab for 2 minutes and these fields clear themselves. | Rời khỏi thẻ này trong 2 phút thì các trường sẽ tự xóa. |
| verifying slow | This is taking longer than usual. | Việc này lâu hơn bình thường. |
| QR accessible name | QR code for pairing with the Loox app | Mã QR để ghép nối với ứng dụng Loox |

### B4. Field presentation (phase-05, 06)

| Slot | EN | VI |
|---|---|---|
| Reveal | Reveal | Hiện |
| Hide | Hide | Ẩn |
| Copy | Copy | Sao chép |
| Copied | Copied | Đã sao chép |
| Hidden placeholder | Hidden | Đã ẩn |
| Show more | Show more | Xem thêm |
| Show less | Show less | Thu gọn |
| TOTP expired | This code expired. Approve again for a fresh one. | Mã này đã hết hạn. Hãy phê duyệt lại để lấy mã mới. |
| copy failed | Copying is not available in this browser. Select the value and copy it manually. | Trình duyệt này không hỗ trợ sao chép. Hãy chọn giá trị và sao chép thủ công. |

`Reveal` / `Copy` / `Copied` reuse the app's existing VI values verbatim so the two surfaces stay
consistent.

### B5. Category labels — decision A only (phase-03 R3)

Mirrors `ItemCategory.title` exactly. VI values are the app's existing translations, taken from
`Localizable.xcstrings` verbatim.

| rawValue | EN | VI |
|---|---|---|
| `login` | Login | Đăng nhập |
| `note` | Secure Note | Ghi chú bảo mật |
| `card` | Payment Card | Thẻ thanh toán |
| `identity` | Identity | Danh tính |
| `sshKey` | SSH Key | Khóa SSH |
| `recoveryCodes` | Recovery Codes | Mã khôi phục |
| `securityQuestions` | Security Questions | Câu hỏi bảo mật |
| `custom` | Custom | Tùy chỉnh |
| `_unknown` fallback | Shared fields | Các trường được chia sẻ |

**The `_unknown` fallback is required**, not optional — a future app version can send a category
this page has never heard of, and an unknown rawValue must never render raw.

---

## Files to modify

- `Vaultify/Localizable.xcstrings` — section A only, EN + VI, both mandatory
- `workers/loox-quick-view/src/open-page.ts` — static page copy
- `workers/loox-quick-view/src/open-page-script-render.ts` — `TERMINAL_COPY`, `CATEGORY_LABELS`,
  button and status strings
- `workers/loox-quick-view/src/open-page-script-markdown.ts` — Show more / Show less

## Tests and validation

- App: confirm no new key in `Localizable.xcstrings` has a missing or empty `vi` value. A missing
  VI value is a bug, not a warning.
- App: run the approval sheet in VI and confirm the empty-selection hint and the disabled Approve
  button fit without truncation at the largest Dynamic Type size.
- Page: if VI ships, assert both catalogs have identical key sets so a missing translation cannot
  silently fall through to English.
- Layout: VI strings here run 10–30% longer than EN. Re-check the 320px pass from phase-07 R5 with
  VI copy, especially the terminal bodies and the autolock hint.

## Risks

- **Mixed-language page.** Even with a VI UI, field labels still arrive in the owner's language,
  so a VI viewer reading an EN owner's share sees EN labels in VI chrome. Unavoidable without
  sending label kinds instead of strings, which is a much larger contract change. Not in scope.
- **Translating the page doubles the copy-review surface** for a page whose copy is
  security-sensitive. If VI ships, both languages need the same review.
