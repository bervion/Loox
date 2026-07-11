# Phase 1 — Expiry: một TextField, không swap branch, autoformat có deletion-aware

Status: in progress · Priority: P0 (keyboard dismiss = data-entry blocker)

## Files

- Modify: `Vaultify/Features/ItemEditor/ExpiryFieldEditor.swift`
- Modify: `VaultifyCore/Models/PaymentCard.swift` (CardExpiryFormat.autoFormat thêm overload
  deletion-aware, pure/testable)
- Modify: `VaultifyTests/PaymentCardTests.swift` (tests mới)

## Steps

1. `CardExpiryFormat.autoFormat(_ input: String, previous: String)` mới:
   - Nếu `input.count < previous.count` (deletion) VÀ `previous` kết thúc "/" VÀ `input ==
     previous.dropLast()` (user vừa xoá dấu "/"): bỏ thêm digit cuối tháng → trả
     `String(input.dropLast())` đã qua format thường.
   - Ngược lại → format thường (giữ hàm cũ cho compat/call sites khác nếu có).
2. `ExpiryFieldEditor` viết lại:
   - `@State useFormatted: Bool?` — quyết định MỘT LẦN trong `.onAppear` =
     `matchesKnownPattern(value)`; không bao giờ đổi trong phiên → không swap view identity.
   - Formatted mode: 1 TextField + local `@State text`; `.onChange(of: text)`: newFormatted
     = autoFormat(new, previous: old); nếu ≠ new → text = newFormatted; value = newFormatted.
   - `.onChange(of: value)`: nếu value ≠ text (scan fill từ ngoài) → text = value.
   - numberPad, placeholder "MM/YY".
3. Tests: gõ tiến ("1"→"1", "12"→"12/", "123"→"12/3", "1234"→"12/34"), clamp ("13"→"12/"),
   xoá qua slash ("12/" prev, input "12" → "1"), paste "12/34"→"12/34", rỗng→rỗng.

## Success

- Không còn branch-swap theo content → keyboard giữ nguyên suốt phiên gõ.
- Xoá lùi tự nhiên qua "/". `make test` pass.

## Risks

- Giá trị legacy lạ đã lưu: vẫn về plain mode như cũ (freeze lúc appear) — hành vi cũ giữ.
- Scan fill khi đang plain mode: hiển thị đúng, không autoformat (case hiếm, ghi chú code).
