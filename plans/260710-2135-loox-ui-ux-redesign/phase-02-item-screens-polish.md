# Phase 2 — Item Detail · 2FA · Generator · Trash · field tools

**Context:** research/design-spec-item-detail-editor-tools.md (2a/2c/2d/7a/7b/7d/7e). Depends: Phase 0.

## Overview
- Priority: P2
- Status: pending
- Màn đều đã tồn tại — flow polish + copy + colorized secret. Editor private-email chips = Phase 6 (infra).

## Key insights
- `ItemDetailScreen.swift` đã copy-first (tap row copy) + `DetailFieldRow`/`ProtectedFieldRow`/`TOTPFieldRow`. Thiếu: inline "Copied" flash chuẩn hoá, TOTP ring cam ≤5s.
- `TotpListScreen.swift` (2FA) đã grid TotpCardView; thiếu username-subtitle phân biệt nhiều account cùng service + orange ≤5s.
- `GeneratorScreen.swift` + `PasswordGeneratorView`: **cần verify** có Passphrase/PIN mode chưa (unresolved). Nếu chưa → thêm segmented `Password | Passphrase | PIN` + colorized output + "Avoid ambiguous".
- `TrashScreen.swift` (Recently Deleted): thêm swipe Restore/Delete + copy "still encrypted" + "gone in N days".
- `LargeTypeView.swift` đã có per-char grid tap-to-mark (7a) — chỉ verify copy/caption, coi như (c) done.
- `ProtectFieldSheet.swift` (7b) đã có — thêm warning banner "no reset" (Phase 0 banner) + verify tab Custom code.
- `WatchtowerCategoryScreen.swift` (7d Compromised) — copy k-anonymity banner + "Seen N times" + Change pill. HIBP live counts = (d) Phase 6.

## Requirements
- TOTP ring cam ≤5s ở Detail (2a) + 2FA list (2d) + colorized code.
- 2FA list: subtitle username per row.
- Generator: verify + (nếu thiếu) Passphrase/PIN segmented, colorized output, Avoid-ambiguous toggle; nút "Use" chỉ khi mở từ editor (đã có context).
- Trash: swipe Restore(success)/Delete(destructive) + copy trust + countdown "gone in N days".
- ProtectField: warning banner no-reset.
- Watchtower Compromised: k-anonymity info banner + Change pill.

## Related code files
- Modify: `Vaultify/Features/ItemDetail/ItemDetailScreen.swift`, `TOTPFieldRow.swift`, `DetailFieldRow.swift`
- Modify: `Vaultify/Features/Home/TotpListScreen.swift`
- Read then modify: `Vaultify/Features/Generator/GeneratorScreen.swift` (+`PasswordGeneratorView` — verify passphrase/PIN)
- Modify: `Vaultify/Features/Vault/TrashScreen.swift`
- Modify: `Vaultify/Features/ItemDetail/ProtectFieldSheet.swift`
- Modify: `Vaultify/Features/Watchtower/WatchtowerCategoryScreen.swift`
- Modify: `Localizable.xcstrings` (EN+VI)

## Implementation steps
1. Wire `nearExpiry` + `ColorizedSecretText` vào TOTPFieldRow (Detail) và TotpListScreen rows.
2. TotpListScreen: thêm username subtitle (nguồn item username/account).
3. Generator: READ trước → xác nhận passphrase/PIN. Nếu thiếu, thêm segmented + generator logic (diceware wordlist nếu chưa có = cân nhắc YAGNI, chỉ nếu design cần; else giữ Password + PIN). Colorized output + avoid-ambiguous.
4. TrashScreen: `.swipeActions` Restore/Delete + copy strings + "gone in N days" từ deletedAt+30.
5. ProtectFieldSheet: chèn `VaultInfoBanner(.warning, "no reset…")`.
6. WatchtowerCategoryScreen: `VaultInfoBanner(.info, k-anonymity)` + Change pill per row.
7. Localize EN+VI. `make check`.

## Todo
- [ ] TOTP orange+colorized (Detail + 2FA list)
- [ ] 2FA username subtitle
- [ ] Generator verify → Passphrase/PIN/colorized/avoid-ambiguous
- [ ] Trash swipe + trust copy + countdown
- [ ] ProtectField no-reset banner
- [ ] Watchtower Compromised k-anon banner + Change pill
- [ ] EN+VI; compile pass

## Success criteria
- TOTP ≤5s đổi màu cả ring+số ở mọi nơi.
- Trash swipe Restore/Delete hoạt động, không mất data ngoài ý muốn.
- Generator mode đúng design (hoặc documented lý do giữ nguyên nếu đã đủ).
- Không đổi crypto/data model.

## Risk assessment
- **[TB]** Generator passphrase cần wordlist → nếu app chưa có, đây là scope creep. Mitigation: Q — nếu design bắt buộc passphrase, thêm wordlist nhỏ (EFF) 1 file; nếu YAGNI, giữ Password+PIN, ghi rationale. Verify trước khi build.
- **[Thấp]** Trash swipe destructive: cần confirm cho "Delete permanently" (giữ pattern app).

## Rollback
- Per-file revert; Trash swipe không đổi persisted schema.

## Next
- Độc lập; song song Phase 1/3/4.
