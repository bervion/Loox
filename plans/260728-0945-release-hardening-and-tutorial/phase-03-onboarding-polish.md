# Phase 03 — Onboarding polish (v2 — track riêng, sau RC trừ khi owner quyết ngược)

Gate: SF-exception phải vào `docs/design-guidelines.md` (authoritative, hiện ghi Polaris-only tại dòng ~19) TRƯỚC khi code — Phase 00 mục 5. CLAUDE.md sync theo, không thay thế.

## 1. Logo step align-left + SF Symbol theo step
- Files: `Vaultify/Features/Onboarding/` (BrandAnimation/ + StepViews) — shared step-header component.
- Dotted-ring mark `alignment: .leading` cùng leading edge với title (`Space.gutter`).
- Icon giữa ring theo step (SF Symbol — exception owner-approved 260728): Create password `key.fill`, Name `person.fill`, Emergency Kit `cross.case.fill`, Theme `paintbrush.fill`, Done `checkmark.seal.fill` — chốt bộ cuối ở PR.
- Cross-fade khi đổi step, collapse dưới Reduce Motion (`.vault()`).
- Test: screenshot light/dark iPhone + iPad; title VI/JA dài không đè icon.

## 2. Theme step: bỏ System, grid 2 mọi thiết bị
- `ChooseThemeView.swift`: options Light | Dark, `LazyVGrid` 2 cột fixed mọi size class; default Light (giữ forceLight gate). `ThemeStore.appearanceMode` case `.system` GIỮ cho Settings.
- Test: chọn Dark → dark ngay + `hasChosenAppearance` release; cả 2 sim.

## 3. Notification pre-permission
- Tiêu thụ component app-layer từ phase-02 mục 2 (không tạo bản thứ hai); context copy riêng cho onboarding/tutorial (3 mục đích: nhắc xoay mật khẩu, yêu cầu phê duyệt, cảnh báo bảo mật). Không bắn OS prompt trước khi user bấm "Cho phép"; không hỏi ở launch.
- Test: fresh install — 0 OS prompt cho tới khi user chạm feature/tutorial tương ứng.

## 4. Performance bar
- 60fps iPhone 11 cho mọi thay đổi onboarding; không tăng thời gian vào Home; Instruments khi nghi ngờ.

Reports: `plans/260728-0945-release-hardening-and-tutorial/reports/`
