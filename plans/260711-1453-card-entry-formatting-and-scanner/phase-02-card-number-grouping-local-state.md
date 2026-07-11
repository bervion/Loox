# Phase 2 — Số thẻ/CVV/PIN: local-state formatter đáng tin + routing hardening

Status: pending · Priority: P0

## Files

- Modify: `Vaultify/Features/ItemEditor/CardNumberFieldEditor.swift`
- Modify: `Vaultify/Features/ItemEditor/CardCodeFieldEditor.swift`
- Modify: `Vaultify/Features/ItemEditor/EditorFieldRow.swift` (routing match)
- Modify: `VaultifyCore/Models/PaymentCard.swift` (template-label matcher nếu đặt ở Core)

## Steps

1. `CardNumberFieldEditor`: bỏ `formattedBinding`; thêm `@State text`;
   - `.onAppear { text = PaymentCard.formattedForInput(value) }`
   - `.onChange(of: text)`: formatted = formattedForInput(new); nếu ≠ new → text=formatted
     (re-entry 1 lần rồi dừng); value = normalizedForStorage(new).
   - `.onChange(of: value)`: nếu digitsOnly(text) ≠ value (scan fill) → text =
     formattedForInput(value).
2. `CardCodeFieldEditor`: cùng pattern (cap digits) — sửa cho đồng nhất, tránh quirk push-back.
3. Routing hardening (`EditorFieldRow`): thay `field.label == "Card Number"` bằng
   `PaymentCardFieldMatch.isTemplateLabel(field.label, english: "Card Number")` — so với EN
   source VÀ bản dịch catalog của mọi ngôn ngữ app hỗ trợ hiện có label đó (EN+VI, resolve
   qua `String(localized:locale:)` từng locale — KHÔNG hardcode chuỗi VI). Đặt helper trong
   app target (cần catalog), file mới nhỏ hoặc gắn vào EditorFieldRow.
4. Giữ nguyên mask/Controlled-Reveal + brand badge + Luhn hint hiện có.

## Success

- Gõ 16 số → group live "4444 4444 ...", Amex 4-6-5; paste có space/dash → chuẩn hoá;
  backspace re-group; scan fill hiển thị ngay.
- Đổi label field (hoặc label đã bị ghi đè bản dịch) KHÔNG làm mất treatment thẻ.

## Risks

- Cursor về cuối khi push formatted (tradeoff chuẩn — chấp nhận, A5).
- Locale mới thêm sau này: matcher resolve theo danh sách locale runtime của catalog —
  thêm ngôn ngữ là tự cover (chỉ cần locale nằm trong list duyệt; note trong code).
