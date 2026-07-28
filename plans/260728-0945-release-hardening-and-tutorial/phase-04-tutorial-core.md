# Phase 04 — TutorialKit + coverage + App Review readiness (v2 — track riêng, feature-flag)

Owner vision: spotlight/focus-hole + tooltip + mũi tên; guide dạng sheet nhúng view thật; max performance. KHÔNG chặn RC (review 260728-1040) — toàn bộ tutorial sau flag `TutorialFeature.enabled` (pattern như `WallpaperFeature`), tắt = zero surface.

## 1. Layering (sửa từ v1 — không nhét hết vào Design System)
- **DS layer** (`Vaultify/DesignSystem/Tutorial/`): visual primitives THUẦN — spotlight overlay (1 Canvas + `.blendMode(.destinationOut)` hole, scrim token, spring morph giữa anchors, collapse dưới Reduce Motion), tooltip card (ThemedCard + vaultType), arrow Path, `.tutorialAnchor(_ id:)` PreferenceKey modifier. Không state, không analytics, không UserDefaults.
- **App layer** (`Vaultify/Services/Tutorial/` + `Features/Tutorial/`): `TutorialStore` (persistence per-flow: notStarted/seen/completed/skipped), trigger points, flow definitions, analytics (typed catalog `tutorial_step`: flow id + index, không user content), feature flag.

## 2. API phác thảo
```swift
TutorialFlow(id: "first-item") {
    TutorialStep(anchor: .id("home.addItem"), style: .spotlight(.capsule), tooltip: "…")
    TutorialStep(style: .sheet { AutofillGuideEmbed() },   // nhúng LIVE view (row setting thật)
                 arrows: [.init(from: .tooltip, to: .id("row.autofill"))])
}
```
Passthrough tap vào hole cho step "bấm thật", hoặc chặn + nút Next. VoiceOver đọc theo step. Mọi copy qua catalog EN/VI/JA.

## 3. Coverage đợt đầu (flag on)
1. First-run Home tour 3 step (Add Item, Search, Security).
2. AutoFill setup guide (sheet nhúng row thật + deep link nếu khả dụng).
3. Watchtower score tooltip sau audit đầu.
4. Share/Approval Mode: pre-permission + 2 tooltip.
5. Rotation reminder tooltip ở editor.
Mỗi flow skippable, không lặp sau completed, reset trong Settings (DEBUG).

## 4. App Review readiness (nằm trong RC track, KHÔNG phụ thuộc tutorial flag)
- Acceptance (sửa từ v1): **reviewer trên MỘT thiết bị không gặp dead-end ở bất kỳ feature nào hiển thị**; flow 2 thiết bị (Approval Mode/sharing) có mô tả + demo video ổn định trong Review Notes; KHÔNG tạo reviewer bypass cho cơ chế bảo mật.
- Review Notes (metadata/apple/*/review_notes): tạo vault không cần account (zero-backend), Emergency Kit, AutoFill enable path, Watchtower, 3 ngôn ngữ, Face ID fallback password, notification pre-permission context, tính năng cần iCloud/2-thiết-bị.
- Feature dark (Quick View nếu ship dark, tutorial nếu flag off) không được có đường UI dẫn tới.
- Checklist trước submit: chạy hết coverage trên máy sạch, EN.

## Validation
- Unit TutorialStore state machine; snapshot overlay light/dark; 60fps iPhone 11 (đo); VoiceOver + Reduce Motion pass; flag off = 0 thay đổi hành vi (diff test).

Reports: `plans/260728-0945-release-hardening-and-tutorial/reports/`
