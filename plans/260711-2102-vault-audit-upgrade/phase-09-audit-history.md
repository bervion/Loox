# Phase 09 — Audit history

**Priority:** P2 · **Status:** ☐ · **Ước lượng:** 0.5 ngày · **Phụ thuộc:** 05, 07

## Thiết kế (proposal §18 — V1 gọn)

`AuditHistoryScreen` push từ Security overview:

```
Today        874   +32
June 20      842   +11
May 12       831
```

- Data: `AuditStore.history(persona:)` (AuditReportRecord, đã sync CK). Delta = so report liền
  trước cùng persona.
- Tap row → `AuditHistoryDetailScreen`: Resolved (fingerprints có ở report trước, mất ở report
  này) / New (ngược lại) — group theo ruleID với count, ví dụ "3 reused passwords". KHÔNG hiện
  giá trị cũ nhạy cảm (payload vốn không chứa).
- Ngày format theo locale (`Date.FormatStyle`), số theo `.numericText` không animation dài.
- Empty state: "Run your first audit to start tracking progress" (EN+VI).
- Retention 50 report/persona đã prune ở phase 05.

## Files

- **Tạo:** `Features/Watchtower/AuditHistoryScreen.swift`, `AuditHistoryDetailScreen.swift`
- **Sửa:** Security overview (link row), `UIStateStore` route.

## Todo

- [ ] 2 screen + diff logic (pure func trong VaultifyCore/Audit, unit test)
- [ ] Localize EN+VI, design-dna check (list rows = PolarisListItem pattern tương đương SwiftUI)
- [ ] `make check`

## Success criteria

Sau 2+ lần audit thấy trend + diff đúng; persona switch tách lịch sử đúng.
