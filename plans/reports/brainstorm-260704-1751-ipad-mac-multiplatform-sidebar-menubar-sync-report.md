# Brainstorm — Vaultify (Loox) đa nền: iPad + Mac, sidebar, menu bar, phím tắt, sync

- Date: 2026-07-04
- Branch: main · Version base: v1.12.0
- Terminal: `/ck:plan` (default) — phasing iPad trước

## Problem statement

App hiện thuần iPhone (`destinations: [.iPhone]`, `TARGETED_DEVICE_FAMILY = "1"`). Muốn mở rộng:
- **iPad**: sidebar + layout adaptive tối ưu.
- **Mac**: app native macOS, **icon Loox ở menu bar** (quick access kiểu 1Password), phím tắt/keyboard nav.
- Đa thiết bị ⇒ vault phải đồng bộ (nếu không thì vô nghĩa).

## Quyết định user đã chốt (không tự đảo)

1. **Mac approach = Native macOS (SwiftUI multiplatform)** — không Catalyst, không "Designed for iPad".
2. **Sync = bật CloudKit ngay trong đợt này** (kích cờ `VAULTIFY_ICLOUD` + iCloud container + provisioning).
3. **Scope = cả 4**: iPad sidebar + Mac app + menu bar quick access + phím tắt/keyboard nav.
4. **Phasing = iPad trước** (v1.13 = P0+P1+P2), Mac sau (v1.14 = P3+P4).
5. **Plan mode = `/ck:plan` default.**

## Scout findings (grounded)

- 208 file Swift (~17K LOC). `VaultifyCore/` shared vào app + AutoFill ext.
- **Zero code adaptive**: không `NavigationSplitView` / `horizontalSizeClass` / `keyboardShortcut` / `MenuBarExtra`. Nav = custom `MainTabView` (4 tab, mỗi tab 1 `NavigationStack`, dùng chung `vaultNavigationDestinations()`). Single scene `WindowGroup`, `UIApplicationSupportsMultipleScenes: false`.
- **UIKit coupling vừa phải**: 21/208 file `import UIKit`. Điểm nóng: `UIImage` 10, `UIColor` dynamic 6, `UIApplication` 5, `PhotosPicker` 4 (chạy cả macOS), `LAContext` 2 (Touch ID chạy macOS), pasteboard/haptics/representable ~6, `overrideUserInterfaceStyle`/`UIWindow`/AppDelegate mỗi thứ 1–3.
- **VaultifyCore shared chỉ dính UIKit ở 3 file**: `AppTheme.swift`, `ColorHex.swift`, `Mesh/MeshGradientRenderer.swift`.
- **Sync đang TẮT**: CloudKit sau cờ `VAULTIFY_ICLOUD` (`CloudSyncService.isConfigured`); CLAUDE.md cảnh báo thêm entitlement iCloud vào app **crash lúc launch** nếu chưa provisioning. Sync LWW whole-record theo `updatedAt` (memory `vaultify-sync-lww-updatedat-gate`).
- AutoFill ext hiện iOS-only (`ASCredentialProvider`); vault file trong App Group shared container.

## Chi phí thật (không phải UI)

UI sidebar rẻ. Đắt nằm ở: (1) **AutoFill trên macOS** = cần extension target macOS riêng, QA máy thật; (2) **menu bar global hotkey + quick access**; (3) **CloudKit provisioning + fix crash entitlement + test LWW**.

## Kiến trúc — 5 phase, có phụ thuộc

**P0 — Platform Abstraction (nền, chặn tất cả)**
- Shim cross-platform: `PlatformImage` (UIImage/NSImage), `PlatformColor` (UIColor/NSColor), pasteboard, haptics no-op trên Mac; biometric qua `LAContext` (dùng chung).
- `#if canImport(AppKit)` / `#if os(macOS)` guard trong VaultifyCore 3 file.
- Tuist `Project.swift`: **1 multiplatform target** `destinations: [.iPhone, .iPad, .mac]`, `TARGETED_DEVICE_FAMILY = "1,2"`, deployment macOS 14; AppKit-specific sau `#if os(macOS)`.

**P1 — iPad Sidebar / adaptive (rẻ, ship trước)**
- `horizontalSizeClass == .regular` (iPad + Mac) ⇒ `NavigationSplitView` 3 cột (sidebar: Home/Items/Watchtower/Search + Spaces · content · detail). `.compact` (iPhone) giữ `MainTabView` nguyên trạng.
- Tái dùng `vaultNavigationDestinations()`.

**P2 — CloudKit Sync (song song P1, blocker giá trị multi-device)**
- Bật `VAULTIFY_ICLOUD` + iCloud container + provisioning; xử lý crash entitlement; test LWW `updatedAt`. Chú ý cột synced (isDefaultIdentity, avatarSealed, folders) phải bump `updatedAt`.

**P3 — Mac Shell (phụ thuộc P0)**
- Cửa sổ macOS native; `MenuBarExtra` quick access (search + copy password/TOTP không mở app chính); AutoFill Credential Provider **extension target macOS**; Touch ID unlock.

**P4 — Keyboard & Commands (phụ thuộc P1+P3)**
- `CommandMenu`, `.keyboardShortcut` (⌘F search, ⌘C copy, ⌘N new item…), focus-based nav, global hotkey mở Quick Access.

## Quyết định kiến trúc tự chốt (confidence cao)

- **1 multiplatform target** thay vì macOS target tách rời → tái dùng ~90% code, 1 nguồn sự thật.
- **Sidebar dùng chung iPad + Mac** (đều regular size class) → viết 1 lần.

## Phasing → mốc ship

- **v1.13** = P0 + P1 + P2 → iPad sidebar + sync bật; iPhone↔iPad dùng thật ngay (~80% giá trị, ~40% công sức).
- **v1.14** = P3 + P4 → Mac app + menu bar + phím tắt.

## Rủi ro

- AutoFill macOS + global hotkey **phải QA máy Mac thật** (sim không cover — bài học Credential Exchange dormant).
- CloudKit cần **thao tác thủ công** ngoài code (Apple Developer portal + đăng nhập iCloud).
- Passkey CloudKit sync vẫn deferred — giữ nguyên, đừng ôm thêm.
- Tuân thủ trần API iOS 17.6 / macOS 14 + guard `#available` cho API mới (CI dùng Xcode stable).

## Success criteria

- iPad: sidebar 3 cột, xoay ngang/dọc ổn, không vỡ iPhone TabView.
- Mac: build `.mac` chạy, menu bar quick access copy được password/TOTP, Touch ID unlock, AutoFill trình duyệt Mac.
- Sync: sửa ở 1 thiết bị → hiện thiết bị khác (LWW), không mất dữ liệu.
- Phím tắt: ⌘F/⌘C/⌘N + global hotkey hoạt động.
- EN + VI đầy đủ; light/dark/Reduce Motion/contrast ok mọi nền.

## Unresolved questions

- iCloud container id + capability đã bật ở Apple Developer portal chưa? (P2 chặn tới khi có.)
- macOS deployment target 14 chấp nhận được? (MenuBarExtra cần 13+, một số API sync/Touch ID muốn 14.)
- Menu bar Quick Access: chỉ read (search+copy) hay cả create item nhanh? (ảnh hưởng phạm vi P3.)
- Global hotkey cần dùng khi app chưa mở (background agent) không? (ảnh hưởng LSUIElement/login item.)
