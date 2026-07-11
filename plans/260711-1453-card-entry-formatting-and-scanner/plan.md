# Card entry formatting + scanner polish

User bugs (260711, VI device): expiry không tự thêm "/", bàn phím dismiss giữa chừng; số thẻ
không tự group space; brand icon (SF không có visa/master); camera scan: nút chìm màu, thiếu
khung placeholder thẻ.

## Root causes (verified by reading code, file:line)

| Bug | Root cause | Evidence |
| --- | --- | --- |
| Expiry mất "/" + keyboard dismiss | `ExpiryFieldEditor` chọn 1 trong 2 `TextField` theo `matchesKnownPattern(value)` MỖI LẦN render. Field mới rỗng → matches=true (formatted). Gõ "1" → "1" không match → **swap sang TextField khác → mất focus, keyboard dismiss**, từ đó về sau nằm ở branch plain → không bao giờ autoFormat | `ExpiryFieldEditor.swift:13-20`; `CardExpiryFormat.matchesKnownPattern` trả true cho chuỗi rỗng (`PaymentCard.swift:176`) |
| Số thẻ không group | Pattern reformat-qua-Binding (`get` trả formatted, `set` ghi digits) không tin cậy trên iOS 17+: UITextField giữ text đang gõ, push-back từ binding giữa keystroke bị nuốt trong nhiều case | `CardNumberFieldEditor.swift:64-69` |
| Routing mong manh (phát hiện thêm khi đối kháng) | Card editors match theo `field.label == "Card Number"` (English source) nhưng label là `TextField` user SỬA ĐƯỢC, hiển thị bản dịch VI — user đổi label 1 ký tự là mất toàn bộ treatment thẻ, âm thầm | `EditorFieldRow.swift:30,67-74` |
| Brand icon | SF không có logo hãng; DNA standard đã CHỐT "brand identification stays a text badge, never a third-party logo asset" (trademark) — mâu thuẫn với yêu cầu mới | `design-dna-standard.md` exemptions; `PaymentCard.swift:3-4` |
| Scanner chìm/thiếu khung | Sheet chỉ có preview đen + 1 dòng text; nút Cancel ăn theo accent tint trên nền đen tối → chìm; không có reticle khung thẻ | `CardScannerSheet.swift:33-58` |

## Phases

Status 260711: phases 1-3 DONE (impl + 487 tests pass, 2 target compile sạch); decision
gate brand icon còn chờ user.

1. [phase-01-expiry-single-field-no-branch-swap.md] — expiry: 1 TextField duy nhất, mode
   quyết định MỘT LẦN lúc appear; autoformat qua local state + onChange (xử lý cả xoá ngược
   qua dấu "/"). Unit tests cho delete-across-slash.
2. [phase-02-card-number-grouping-local-state.md] — số thẻ + CVV/PIN: chuyển sang local
   `@State` text + `onChange` sync 2 chiều (typing → format lại; scan fill → refresh).
   Hardening routing: match label theo cả EN source lẫn bản dịch đã biết (EN+VI).
3. [phase-03-scanner-reticle-and-buttons.md] — camera: khung placeholder tỷ lệ thẻ
   (1.586:1) với dim mask + góc bo sáng, guidance text trong khung, Cancel trắng rõ trên
   nền camera (exempt theme theo DNA).

## Decision gate (KHÔNG tự quyết)

- **Brand icon**: DNA đã chốt text badge (trademark risk khi ship logo Visa/MC). Options:
  (a) giữ text badge, tinh chỉnh visual (chip màu brand); (b) vẽ mark generic tự thiết kế
  (không phải logo thật); (c) vendor logo thật — rủi ro trademark, cần user chấp nhận rõ.
  → hỏi user, KHÔNG làm trước.

## Adversarial findings đã gộp vào phases

- A1: freeze-mode lúc appear + scan fill "12/28" vào field đang plain-mode → vẫn hiển thị
  đúng, chỉ mất autoformat cho case hiếm (chấp nhận, ghi chú code).
- A2: autoFormat cũ khiến KHÔNG THỂ xoá qua "/" ("12/"→xoá→"12"→re-format "12/" kẹt vĩnh
  viễn). Phase 1 phải nhận biết deletion (so old/new) và bỏ luôn digit cuối của tháng.
- A3: gán lại @State trong onChange(of:text) tái-entry đúng 1 lần (formatted==new → dừng) —
  không loop.
- A4: label-corruption làm rơi routing → hardening phase 2; đồng thời label TextField giữ
  nguyên hành vi (không đổi model, không thêm cột sync).
- A5: cursor nhảy về cuối khi push formatted text — tradeoff chuẩn của as-you-type mask
  (Stripe/1P đều vậy khi sửa giữa chuỗi số); không chặn.
- A6: VisionKit regionOfInterest theo khung reticle — SKIP (YAGNI, rủi ro lệch toạ độ);
  chỉ overlay visual.

## Success criteria

- Gõ expiry: "1"→"1", "12"→"12/", "128"→"12/8"; xoá lùi thoát được qua "/"; keyboard KHÔNG
  dismiss trong suốt phiên gõ. Số thẻ: "4111111111111111" hiển thị "4111 1111 1111 1111",
  Amex nhóm 4-6-5; xoá/paste đều re-group. Scan fill cập nhật text đang mở.
- `make test` pass (PaymentCardTests + tests mới). Compile 2 target sạch.
- Scanner: khung thẻ rõ, Cancel đọc được trên mọi theme.
