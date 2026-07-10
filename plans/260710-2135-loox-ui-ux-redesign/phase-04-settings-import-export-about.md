# Phase 4 — Settings · Appearance · Import/Export · secondary sheets · About Us

**Context:** research/design-spec-settings-autofill-profile.md (5a-5g,6a-6c), design-spec-secondary-screens-about.md (10a-10g,13). Depends: Phase 0.

## Overview
- Priority: P2
- Status: pending
- Phần lớn polish màn có sẵn. Màn MỚI duy nhất: About Us storytelling (13). Extra-Protection crypto = Phase 6.

## Key insights
- `SettingsScreen.swift` đã sheet + sections. Design (5a/5g): reorg nhóm, online-feature health status per-row (Available/Maintenance), composite value ("Day · Loox Blue", "3 addresses", version). Danger zone card cuối.
- `AppearanceSettingsView.swift` (5b) đã theme+7 accent (khớp). Thêm mini-preview theme card + composite value ở row cha.
- `ImportView.swift` (5d): thêm bước **preview** records trước ghi + CTA nêu số lượng ("Import 34 Records"). Verify parser có preview chưa.
- `ExportView.swift` (5e): segmented Encrypted|CSV + **banner đỏ** cho CSV + CTA đỏ "Create Unencrypted Export" + passkey "Never exported" dim.
- `ChangeMasterPasswordView.swift` (10b): info banner "Your Vault Key doesn't change…" + inline verify check.
- `Level2SettingsView.swift` (10c Extra Protection): polish UI setup (explainer + no-reset warning) — crypto scope KHÔNG đổi (Phase 6 ADR).
- `PasskeyDetailSheet.swift` (10a): backed-up badge + no-reset footnote.
- `AutoNightSettingsView.swift` (10d): Off/System/Scheduled radios + schedule chips. "Below brightness" = CẮT (Q10).
- `AboutView.swift` (10g) đã technical. **About Us (13)** = màn scroll dài mới — storytelling 3 section. Q7/Q9: nội dung + team thật cần user; KHÔNG ship placeholder.
- Cipher wording (Q8): verify code thật (Argon2id + AES-256-GCM vs ChaCha20) trước khi ghi copy.

## Requirements
- Settings: online-feature health status line; composite values; danger-zone card.
- Appearance: mini theme preview + composite parent value.
- Import: preview list + count CTA (nếu parser hỗ trợ; else defer preview, giữ import trực tiếp — verify).
- Export: Encrypted/CSV tabs + đỏ warning + passkey-never + confirm/Face ID trước tạo file.
- ChangeMP: Vault-Key-unchanged banner + inline verify.
- Passkey detail: backup badge + no-reset footnote.
- About Us (13): 1 ScrollView, 3 section; cipher copy verified; team/version dynamic hoặc ẩn nếu chưa có data thật.

## Related code files
- Modify: `Vaultify/Features/Settings/SettingsScreen.swift`
- Modify: `Vaultify/Features/Settings/Appearance/AppearanceSettingsView.swift`, `AutoNightSettingsView.swift`
- Modify: `Vaultify/Features/ImportExport/ImportView.swift`, `ExportView.swift`
- Modify: `Vaultify/Features/Settings/ChangeMasterPasswordView.swift`, `Level2SettingsView.swift`
- Modify: `Vaultify/Features/Passkeys/PasskeyDetailSheet.swift`
- Create: `Vaultify/Features/Settings/AboutUsScreen.swift` (storytelling 13) — hoặc extend `AboutView.swift`
- Modify: `Localizable.xcstrings` (EN+VI); `tuist generate` cho file mới
- Verify (crypto wording): `VaultifyCore/CArgon2/`, seal/cipher code

## Implementation steps
1. Settings: thêm status line online-features (nguồn CapabilityBanner/service state đã có), composite value rows, danger-zone card gộp Lock Now + Erase.
2. Appearance: mini-preview theme cards + parent composite value.
3. Import: READ parser → nếu có structured parse, thêm preview list + count CTA; else giữ trực tiếp + ghi rationale (YAGNI).
4. Export: segmented tabs + đỏ warning banner + CTA đỏ + passkey dim + confirm/Face ID.
5. ChangeMP: `VaultInfoBanner(.info)` Vault-Key-unchanged + inline verify check.
6. Level2 + PasskeyDetail: banner/footnote polish (no crypto change).
7. AutoNight: giữ Off/System/Scheduled; cắt brightness.
8. About Us: verify cipher wording trong code → build ScrollView 3 section. Team/version: version runtime; team = ẩn/placeholder-guard chờ user (Q9).
9. Localize EN+VI. `make check`.

## Todo
- [ ] Settings health status + composite + danger zone
- [ ] Appearance mini preview
- [ ] Import preview (nếu khả thi) / documented skip
- [ ] Export tabs + đỏ warning + passkey-never + confirm
- [ ] ChangeMP Vault-Key banner + inline verify
- [ ] Extra Protection + Passkey detail polish
- [ ] AutoNight (cắt brightness)
- [ ] About Us screen (cipher verified, no placeholder ship)
- [ ] EN+VI; compile pass

## Success criteria
- Export CSV có friction rõ (đỏ + confirm); passkey không bao giờ export.
- ChangeMP không phá Face ID/Emergency Kit (banner đúng kiến trúc — Vault Key bất biến).
- About Us cipher copy khớp code thật; không ship tên team/sample giả.
- Settings không đổi behavior toggle, chỉ hiển thị.

## Risk assessment
- **[TB]** Cipher wording sai → false security claim. Mitigation: verify code trước ship (Q8, blocking cho About Us copy).
- **[TB]** Import preview có thể cần refactor parser. Mitigation: chỉ thêm nếu parser đã trả structured list; else defer.
- **[Thấp]** About Us team = placeholder. Mitigation: guard — ẩn section nếu chưa có data thật (Q9 user).

## Rollback
- Per-file revert; About Us là file mới → xóa + revert Settings About row.

## Next
- Độc lập; song song Phase 1/2/3. About Us content chờ user (Q7/Q9).
