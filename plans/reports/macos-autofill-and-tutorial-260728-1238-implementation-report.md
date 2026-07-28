# macOS AutoFill + TutorialKit + Quick View GA — Implementation Report

- Date: 2026-07-28 · Branch `feat/release-hardening-260728` (20 commits tổng, 5 commit của đợt này)
- Verify: iOS compile PASS · **macOS compile PASS (app + appex embed đúng `Contents/PlugIns/`)** · **943/943 unit tests PASS** · 4/4 Safari harness PASS · self-test tour trên iPhone 11

## 1. Quick View — GA path (backend đã set `ga` + assertion REQUIRED)

Không cần đổi code: `QuickViewConfig.assertionRequired = true` đã khớp server, manifest exposure chảy qua `CapabilityStore` → `ItemDetailScreen` entry. Đã **thêm test pin đúng tổ hợp production** (`ga` + assertion required + non-beta cohort → entry hiện), vì mọi tổ hợp lân cận đều fail-closed nên case mở cửa đáng được assert riêng.

## 2. macOS AutoFill extension (mới)

- Sources dùng chung với iOS; khác biệt nằm trong `#if canImport(UIKit)`:
  - `ASCredentialProviderViewController` là **UIViewController trên iOS, NSViewController trên macOS** → `host(_:)` branch `UIHostingController`/`NSHostingController`, và appearance đọc `NSApp.effectiveAppearance` thay `traitCollection`.
  - Block save/generate (iOS 26.2 API) gate thêm `#if os(iOS)`.
- **Platform helpers chuyển vào `VaultifyCore/Platform/`** (Navigation, TextInput, Pasteboard) để appex với tới; `PlatformAppearance` **ở lại app target** — `UIApplication.shared` bị cấm trong extension (phát hiện khi compile).
- 6 call site iOS-only trong extension chuyển sang helper (`platformNavigationBarTitleDisplayMode`, `platformAutocapitalization`, `PlatformPasteboard.copySensitive`, `Color.platformSystemGray5`).
- Target **riêng** `VaultifyAutoFillMac` (không multiplatform): appex chỉ mang 1 Info.plist, mà capability set khác nhau — macOS không có save/generate request types, khai sai là hỏng cả provider chứ không phải lỗi build. Capabilities macOS: passwords + passkeys + conditional passkey registration + one-time codes.
- Entitlements macOS riêng: **App Sandbox (bắt buộc trên macOS)**, app group, shared keychain group, CloudKit, `network.client` (không có thì mọi shared-item fill + ask-each-time passkey fail closed).
- rpath macOS 4 cấp (`@executable_path/../../../../Frameworks`) vì appex nằm sâu hơn trong bundle.

**Verify được**: compile + embed + Info.plist capabilities + principal class + LSMinimumSystemVersion 15.0.
**CHƯA verify (cần Mac ký thật)**: App Group container resolve, Touch ID unlock, fill thật. Máy này chỉ có distribution cert nên không chạy được.

## 3. TutorialKit (mới, sau feature flag)

Tách layer đúng như review yêu cầu:
- **DS layer** `Vaultify/DesignSystem/Tutorial/`: `tutorialAnchor(_:)` (PreferenceKey + Anchor<CGRect>), `TutorialSpotlightOverlay` (1 Canvas + `blendMode(.destinationOut)`, tooltip card, placement) — không state, không analytics, không persistence.
- **App layer** `Vaultify/Services/Tutorial/` + `Features/Tutorial/`: `TutorialFlow` (data), `TutorialStore` (UserDefaults per-flow), `TutorialCoordinator` (state machine + analytics), `TutorialHost` (bridge anchors → overlay).
- Flag `TutorialFeature.enabled` trong VaultifyCore theo đúng pattern `WallpaperFeature`.
- Analytics: 2 event mới `tutorial_step_shown` / `tutorial_flow_ended` (flow id + index/outcome, không nội dung user), đã vào `auditSamples`.
- Flow đầu: 3 bước (Add Item → Security → closing beat). Anchor gắn ở Quick Actions tile (iPhone) **và sidebar row (iPad)** nên tour chạy đúng ở cả 2 size class.
- Strings EN/VI/JA đầy đủ (7 chuỗi mới + Next/Skip).

**2 bug layout tìm ra khi test thật trên simulator (đã fix):**
1. **Hole lệch 44pt** — overlay `ignoresSafeArea` trong khi GeometryReader phân giải anchor ở không gian có safe area → 2 hệ toạ độ khác nhau. Fix: host sở hữu 1 không gian duy nhất.
2. **Tooltip che spotlight** — placement tính theo phân số màn hình. Fix: đặt card theo cạnh thật của hole, chọn phía còn nhiều chỗ hơn.
Ngoài ra: step cuối đổi nút "Next" → "Done" và bỏ "Skip".

Tests: `TutorialFlowStateTests` (7 case: complete/skip không hỏi lại, suspend vẫn eligible, không chồng flow, anchor hợp lệ).

## 4. Docs sync
CLAUDE.md / README / codebase-summary: bỏ "iPhone-only", "EN + VI", cập nhật 4 target + ghi rõ macOS runtime chưa verify.

## Unresolved questions

1. **App Group trên macOS**: entitlements dùng id không team-prefix (`group.com.bervion.vaultify`); macOS thường yêu cầu prefix team id. `SharedConfig.containerURL` đang `preconditionFailure` trên macOS nếu không resolve → app + appex crash ngay lần chạm vault đầu. Cần verify trên Mac ký thật; nếu fail thì thêm fallback team-prefixed hoặc đổi entitlement + portal.
2. Có ship Safari extension cho macOS luôn không (hiện iOS-only)?
3. Tutorial: bật flag ngay ở RC này hay để off tới sau khi có thêm flow (AutoFill setup guide, Watchtower, share)?
4. Signed RC + QA máy thật vẫn là gate cuối chưa chạy.
