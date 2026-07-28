# Phase 07 — iPad parity + release ops + Signed RC (v2)

CloudKit Production inventory đã CHUYỂN sang Phase 00 (gate, không phải hạng mục cuối). Quick View decision cũng ở Phase 00; phase này thực thi kết quả.

## 1. iPad AutoFill (nếu Phase 00.4 chốt in-scope)
- `Project.swift:182` extension `destinations` += iPad; kiểm `CredentialProviderViewController` regular width (sheet size, hit targets); test password + passkey fill iPad sim. Nếu out-of-scope: docs + metadata nói rõ known-gap.

## 2. Thực thi Quick View decision (từ Phase 00.3)
- Ship dark: verify 0 đường UI user thường; `publishSecondaryMirror` gắn operator script có chủ đích hoặc gỡ khỏi build.
- Hoàn thành: rollout ladder + wire payload category/title.

## 3. Release hygiene
- Emergency Kit PDF: địa chỉ support thật (Phase 00.5).
- Sharing failure sheets: map CloudKit error → message localize, không raw error.
- App Privacy label ASC: "Product Interaction, not linked to you".
- Plan statuses cũ: cập nhật để không bỏ sót 2-device QA gates.

## 4. Signed RC + full QA (exit gate của cả plan)
- Artifact: Release configuration, ký thật qua fastlane match, TestFlight build (không phải Debug sim).
- Suite: full unit + Safari node harnesses + recovery flow bằng Emergency Kit thật + import/export roundtrip theo contract mới + archive/trash/restore + theme dark toàn màn + Dynamic Type XL.
- Sim self-test script như report §4 trên iPhone 11 + iPad Air (fresh install; **backup group container iPad trước install** — memory `sim-group-container-reset`).
- Máy thật (owner): Face ID onboarding + unlock, AutoFill thật trong Safari/app thứ ba, sharing/Approval Mode 2 thiết bị, case mạng (memory `never-toggle-mac-network`).
- 3 embedded targets đều trong artifact và chạy (app, AutoFill, Safari extension).

Reports: `plans/260728-0945-release-hardening-and-tutorial/reports/`
