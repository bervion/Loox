# Phase 0 — Shared UI primitives

**Context:** research/design-spec-*.md ("Tổng hợp cross-cutting" của mọi file). Blocker cho Phase 1-5.

## Overview
- Priority: P1 (nền tảng, blocking)
- Status: pending
- DRY: các đợt lặp lại 4 pattern chưa có component dùng chung. Tạo 1 lần, consume nhiều nơi. Tránh mỗi phase tự vẽ lại → drift.

## Key insights
- Đã có sẵn (KHÔNG tạo lại): `ThemedCard`, `ThemedDivider` (DesignSystem/Components/ThemedComponents.swift), `CategoryBadge`+`FilterChip` (Features/Components/VaultComponents.swift), `PasswordStrengthMeter`, `TotpRingView` (Home/Components), `WatchtowerScoreRing`, `CopyToastOverlay`, `RevealableSecureField`, `SpoilerText`.
- CHƯA có: info/warning banner tint (chỉ có `CapabilityBannerView` chuyên biệt), status-dot language (cam=chờ họ / xanh lá=chờ mình), colorized secret text (digit accent / symbol destructive), TOTP ring state "cam ≤5s".

## Requirements
- `VaultInfoBanner`: variant `.info` (tint accentSoft, icon shield/info) + `.warning` (tint warning) + `.danger` (tint destructive). Nhận icon (Polaris SVG), text (LocalizedStringResource), optional inline action link. Dùng ThemeRole, không hardcode.
- `VaultStatusBadge` + `StatusDot`: enum `.active`(success) / `.pending`(warning) / `.action`(accent) / `.disabled`. Pill nền tint alpha + chấm. Copy nhãn tự truyền.
- `ColorizedSecretText`: nhận String → `Text` với digit = accent, symbol = destructive, chữ = primary; font `Font.vaultCode`. Dùng ở generator/editor password/large type/create-login.
- `TotpRingView`: THÊM param `nearExpiry: Bool` → track+code chuyển warning/orange khi ≤5s (đổi cả màu số ở call-site qua `ColorizedSecretText` hoặc modifier). KHÔNG hardcode cam — dùng ThemeRole `.warning`.

## Related code files
- Create: `Vaultify/DesignSystem/Components/VaultInfoBanner.swift`
- Create: `Vaultify/DesignSystem/Components/VaultStatusBadge.swift`
- Create: `Vaultify/DesignSystem/Components/ColorizedSecretText.swift`
- Modify: `Vaultify/Features/Home/Components/TotpRingView.swift` (thêm nearExpiry)
- Modify: `Localizable.xcstrings` (nhãn badge nếu có literal)
- Chạy `tuist generate` sau khi thêm file mới.

## Implementation steps
1. Tạo `VaultInfoBanner` — 3 variant, API `VaultInfoBanner(.info, icon:, text:, action:)`. Preview light+dark.
2. Tạo `VaultStatusBadge`+`StatusDot` — map enum → ThemeRole color, alpha ~.12 nền.
3. Tạo `ColorizedSecretText` — parse ký tự, build `Text` concatenation, `.monospacedDigit()` optional.
4. Sửa `TotpRingView` thêm `nearExpiry` (default false) — không đổi call-site cũ (backward compat).
5. `tuist generate` + compile (`make check`).

## Todo
- [ ] VaultInfoBanner (3 variant) + preview
- [ ] VaultStatusBadge + StatusDot
- [ ] ColorizedSecretText
- [ ] TotpRingView.nearExpiry (backward-compat default)
- [ ] tuist generate + compile pass

## Success criteria
- 3 file mới compile trong cả app + extension target (VaultifyCore không cần — đây là UI app-side; nếu extension cần ColorizedSecretText, đặt file dùng chung ở target-shared vị trí phù hợp — verify import).
- Không đổi hành vi call-site TotpRingView cũ (default nearExpiry=false).
- Không hardcode màu (chỉ ThemeRole). Light+dark preview OK.

## Risk assessment
- **[Thấp]** ColorizedSecretText cần chạy trong AutoFill extension (Phase 4/6 create-login) → nếu vậy đặt trong source glob của cả 2 target. Mitigation: check `VaultifyAutoFill` có dùng không; nếu có, đặt file nơi cả `Vaultify/**` lẫn extension include (hoặc `VaultifyCore/**` nếu thuần SwiftUI-free — nhưng đây là View → giữ app-side + copy nhẹ cho extension). Quyết định khi Phase 4 chạm tới.

## Rollback
- Xóa 3 file mới + revert TotpRingView diff. Không có persisted state.

## Next
- Unblocks Phase 1-5.
