# Phase 1 — Home + Search flow quick wins

**Context:** research/design-spec-core-tabs-night.md (1a/1d/1e/1f/1c). Depends: Phase 0.

## Overview
- Priority: P1 (giá trị hằng ngày cao nhất, rủi ro thấp)
- Status: pending
- Chỉ tinh chỉnh màn có sẵn — KHÔNG đổi tab bar / Home header (ràng buộc cứng).

## Key insights
- App đã có đủ khối Home (profile row, quick actions 2×2, approval row, TOTP scroller, Needs Attention, Favorites, All-items + Space switcher + sort) — `HomeScreen.swift`. Chỉ thiếu: badge counts trên quick actions, TOTP ring cam ≤hết-chu-kỳ, Needs-Attention nút "Change" per-row, empty-state trust copy.
- Search: `SearchScreen.swift` đã auto-activate `.searchable`. Thiếu: scope chips (Personal/All Spaces/Shared with Me), highlight substring, empty-state actionable "Search all Spaces".
- SpaceScope đã tồn tại (`Features/Search/SpaceScope.swift` per inventory).

## Requirements
- Home quick actions: badge count trên 2FA (số TOTP) + Watchtower (số issue) — dùng `VaultStatusBadge`.
- Needs Attention row: nút pill `Change` (accent-soft) → mở editor/website đổi password; dùng RotationStatus label (`VaultifyCore/Models/RotationStatus.swift`).
- TOTP carousel: ring cam khi ≤5s (Phase 0 `nearExpiry`).
- Empty Home (1f): tile khoá + title "Your vault is empty" + body trust ("encrypted on this iPhone before it's stored") + CTA `+ Add Item`. Ẩn các section rỗng (không skeleton).
- Search scope chips + highlight + actionable empty ("No results in {Space}" + nút "Search all Spaces" → đổi scope + re-run).

## Related code files
- Modify: `Vaultify/Features/Home/HomeScreen.swift`
- Modify: `Vaultify/Features/Home/Components/QuickActionCard.swift` (badge slot)
- Modify: `Vaultify/Features/Home/Components/AttentionCell.swift` (Change pill)
- Modify: `Vaultify/Features/Home/Components/TotpCardView.swift` (nearExpiry wiring)
- Modify: `Vaultify/Features/Search/SearchScreen.swift` (scope chips + highlight + empty)
- Read: `Vaultify/Features/Search/SpaceScope.swift`, `VaultifyCore/Models/RotationStatus.swift`
- Modify: `Localizable.xcstrings` (EN+VI cho mọi string mới)

## Implementation steps
1. QuickActionCard: thêm optional `badge: Int?` → render `VaultStatusBadge` góc phải. Wire count ở HomeScreen (TOTP count, Watchtower issue count — đã có nguồn).
2. AttentionCell: thêm trailing `Change` pill (accent-soft, `ThemedButtonStyles`) → action đổi password (reuse editor sheet target hiện có).
3. TotpCardView: truyền `nearExpiry` (≤5s) xuống TotpRingView + `ColorizedSecretText` cho mã.
4. Home empty-state: thay/expand empty branch hiện có với copy trust + CTA (dùng string catalog).
5. SearchScreen: thêm hàng scope chips (FilterChip có sẵn) trên results; highlight substring khớp trong title; empty-in-scope state với nút "Search all Spaces".
6. Localize toàn bộ (EN source + VI). `tuist generate` nếu thêm file. `make check`.

## Todo
- [ ] Quick action badges (2FA + Watchtower)
- [ ] AttentionCell "Change" pill
- [ ] TOTP orange ≤5s + colorized code
- [ ] Home empty-state trust copy + CTA
- [ ] Search scope chips + highlight + actionable empty
- [ ] EN+VI strings; compile pass

## Success criteria
- Badge counts đúng số thật; ẩn khi 0.
- Empty Home không render section rỗng; CTA mở Add Item.
- Search: gõ trong scope Personal không khớp → thấy "No results in Personal" + 1 tap mở rộng All Spaces re-run ngay.
- Không đổi tab bar/header. Light+dark+Reduce Motion OK. VI đủ.

## Risk assessment
- **[Thấp]** Badge count nguồn dữ liệu: verify HomeScreen đã có sẵn issue/TOTP count (inventory xác nhận có). Nếu tính lại gây cost → reuse count có sẵn, không query mới.
- **[Thấp]** Highlight substring với AttributedString: iOS 17.6 OK.

## Rollback
- Revert per-file; không schema/persisted change.

## Next
- Độc lập Phase 2-5 (khác file). Song song được sau Phase 0.
