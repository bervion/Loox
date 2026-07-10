# Phase 3 — Onboarding · Lock · Personas · Space editor

**Context:** research/design-spec-onboarding-lock-personas.md (3a-3f, 8a-8f). Depends: Phase 0.

## Overview
- Priority: P2
- Status: pending
- Toàn màn đã tồn tại — polish copy/state/order + banner. Thứ tự Name/Kit = unresolved Q3.

## Key insights
- `OnboardingFlow.swift` state machine đã: welcome→join→create→name→emergencyKit→theme→biometric→done. Design (8) xếp Name TRƯỚC Kit (kit in owner name). **Verify thứ tự thật** — app hiện có vẻ create→name→emergencyKit (name trước kit) = KHỚP design. Xác nhận, không đảo mù.
- `CreateMasterPasswordView.swift`: thêm inline error "Passwords don't match" (không alert) + warning banner Emergency Kit "no reset" (Phase 0).
- `EmergencyKitView.swift`: gate Continue theo hành vi lưu (Save PDF/Share) — Q4 default chỉ Save/Share count. Kit preview "document" style + owner name.
- `LockScreen.swift` đã 3 mode (biometric/password/slide). Design: badge Face ID góc icon, status pill "Checking Face ID…", inline password error, slide copy "You locked Loox yourself". Polish visual bằng token.
- `PersonaSwitcherScreen.swift` (8e): thêm policy caption inline (Standard=none / Isolated / Strictly anonymous — màu purple), min-1 constraint đã có? verify. Map PersonaRecord V3.
- `FolderEditorSheet.swift` (Features/**Folders**/, 8f Space editor): live preview badge + icon grid + 7-color palette + copy "Items move to Unfiled". Verify đã có phần nào.

## Requirements
- CreateMasterPassword: inline mismatch error + no-reset warning banner + strength (đã có meter) + Continue disabled tới khi valid.
- EmergencyKit: gate Continue theo save action; owner name từ Name step.
- Lock: Face ID badge trên icon tile + status pill + inline error + slide copy (dùng token, KHÔNG BlurStyle.inner).
- Onboarding Done: recap subtitle **dynamic** theo lựa chọn Face ID (không hardcode "Face ID on").
- Personas: policy caption + màu theo mức; min-1 enforce.
- Space editor: live preview badge + icon/color pickers + Unfiled copy.

## Related code files
- Modify: `Vaultify/Features/Onboarding/OnboardingFlow.swift`, `CreateMasterPasswordView.swift`, `NameStepView.swift`, `EmergencyKitView.swift`, `ChooseThemeView.swift`, `EnableBiometricView.swift`
- Modify: `Vaultify/Features/Unlock/LockScreen.swift` (+ `LockPasswordField`, `SlideToUnlock`, `BiometricBadge` nếu tách file)
- Modify: `Vaultify/Features/Personas/PersonaSwitcherScreen.swift`, `PersonaKindStyle.swift`
- Modify: `Vaultify/Features/Folders/FolderEditorSheet.swift`
- Read: `VaultifyCore` PersonaRecord model
- Modify: `Localizable.xcstrings` (EN+VI)

## Implementation steps
1. Verify onboarding step order thật (READ OnboardingFlow enum). Nếu Name trước Kit → giữ; nếu ngược → chỉ đổi nếu an toàn (kit owner name), else để owner generic. Không đảo mù.
2. CreateMasterPassword: inline mismatch error + `VaultInfoBanner(.warning)` Emergency Kit.
3. EmergencyKit: gate Continue theo flag đã-lưu (Save/Share).
4. LockScreen: badge Face ID (overlay trên icon), status pill, inline error, slide copy — token-driven.
5. OnboardingDone: compose subtitle theo flags (kit saved luôn true; Face ID theo chọn).
6. Personas: policy caption + màu (PersonaKindStyle) + min-1 guard verify.
7. Space editor: live preview badge + icon grid + 7 swatch + "Items move to Unfiled" copy.
8. Localize EN+VI. `make check`.

## Todo
- [ ] Verify + (nếu cần) fix onboarding order
- [ ] CreateMP inline error + no-reset banner
- [ ] EmergencyKit gate Continue
- [ ] Lock badge + status pill + inline error + slide copy
- [ ] Done recap dynamic
- [ ] Personas policy caption + min-1
- [ ] Space editor live preview + palette + Unfiled copy
- [ ] EN+VI; compile pass

## Success criteria
- Onboarding không cho Continue khi chưa lưu kit / password chưa match.
- Lock hiển thị đúng phương thức + trạng thái; deliberate-lock vẫn cần slide (không phá lock UX hiện có).
- Personas: policy đọc được không cần mở detail; không xoá được persona cuối.
- Space delete → items về Unfiled, KHÔNG xoá item.

## Risk assessment
- **[TB]** Đảo thứ tự onboarding có thể phá seed default-identity/My-Vault (memory). Mitigation: verify trước, ưu tiên KHÔNG đảo — chỉ tinh chỉnh copy/gate.
- **[Thấp]** Lock badge overlay không được che nút fallback.

## Rollback
- Per-file revert; onboarding order revert nếu regression seed.

## Next
- Độc lập; song song Phase 1/2/4.
