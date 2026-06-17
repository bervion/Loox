---
phase: 7
title: Localization
status: completed
priority: P2
effort: 2-3h
dependencies:
  - 2
  - 5
  - 6
---

# Phase 7: Localization

## Overview

Localize every new/changed user-facing string EN + VI in `Localizable.xcstrings`. The DS UI kit copy is
**already Vietnamese** — use it as the canonical VI source; a missing VI value is a bug (CLAUDE.md).

## Requirements

- Functional: no hard-coded user-facing text in the new Home/Watchtower/Appearance surfaces.
- Non-functional: titles use `.inAppLocalized`; runtime strings use `appString()`; both EN + VI present.

## Key Insights

- Canonical VI strings from the spec (reuse verbatim): Home — `Tìm trong kho`, `Thêm mục`,
  `Tạo mật khẩu`, `Mã 2FA`, `Giám sát`, `Mã xác thực`, `Xem tất cả`, `Cần chú ý`, `Yêu thích`,
  `Tất cả`, `Sắp xếp`. Rotation — `Nhắc đổi mật khẩu`, `Tắt`, `15/30/90 ngày`, `Quá hạn đổi %@ ngày`,
  `Đổi sau %@ ngày`, `Đổi`. Watchtower — `Khá an toàn`, `Cần chú ý`, `Rủi ro cao`,
  `Độ mạnh mật khẩu tổng thể`, `Cần xử lý`, `Mật khẩu bị lộ`, `Dùng lại mật khẩu`, `Mật khẩu yếu`,
  `Khắc phục %@ vấn đề bên dưới để nâng điểm bảo mật của kho.`. Appearance — `Chế độ`, `Màu nhấn`,
  `Màu nhấn áp dụng tức thì cho toàn bộ ứng dụng — không cần khởi động lại.`.

## Related Code Files

- Modify: `Localizable.xcstrings` (EN source + VI value for every new key).
- Verify: all Phase 2/4/5/6 views use localized resources (no `Text("literal")` user-facing without VI).

## Implementation Steps

1. Sweep new views for string literals; convert to `appString()` / `.inAppLocalized`.
2. Add each key with EN + VI (VI from the spec table above; translate any extras).
3. Build once so auto-extracted `Text` literals appear; fill their VI values.
4. `tuist generate --no-open` → compile; scan catalog for missing VI.

## Todo List

- [ ] All new Home strings keyed EN+VI
- [ ] All new Watchtower strings keyed EN+VI
- [ ] Appearance changes keyed EN+VI
- [ ] Rotation cadence + attention labels keyed EN+VI
- [ ] No missing VI values; `make check` passes

## Success Criteria

- [ ] In-app language toggle flips all new surfaces EN↔VI with no leftover literals.
- [ ] Plurals/interpolations (`%@ ngày`, `%@ vấn đề`) read naturally in both languages.

## Risk Assessment

- Auto-extracted `Text` literals can hide untranslated strings → audit the catalog after a build.

## Security Considerations

None.
