# Phase 06 — Localization (JA/VI) + release pipeline (v2)

In-app coverage đã gần 100%; gap ở pipeline + polish. (v1 claim "Fastfile hardcode EN/VI" SAI — `Fastfile:24` tự enumerate `metadata/apple/*`; chỉ generator/release script/metadata thiếu ja.)

## 1. JA vào pipeline release (HIGH)
- Tạo `metadata/apple/ja/` (name, subtitle, description, keywords, release_notes) — dịch từ en-US, review giọng marketing JA. Fastlane tự nhận nhờ enumerate.
- `scripts/generate-release-notes*` + `release.sh` + `Makefile`: thêm ja.
- `Project.swift`: `knownRegions` += ja (verify sau `tuist generate`).
- `Loox.storekit`: subscription localizations ja.
- Test: generator dry-run ra đủ 3 file notes.

## 2. InfoPlist localization (HIGH)
- `InfoPlist.xcstrings` cho cả 3 target (NSFaceIDUsageDescription, Camera, Photos) EN/VI/JA; wire trong `Project.swift`.
- Test: device locale vi/ja → prompt đúng ngôn ngữ.

## 3. JA polish
- 「ID」→「プロフィール」 cho identity (~28 chuỗi app + 4 Safari), cụm nhất quán.
- 2要素認証 thống nhất; thêm さん ở ShareResumeStepperSheet subtitle; badge Stale rút 「要更新」.
- Safari/AutoFill form classifier + signup detector thêm JA tokens (hiện EN+VI → form JA không autocomplete-token sẽ không fill/save-prompt); node harness case JA.
- Safari extension web UI + Face ID prompt theo in-app language toggle.

## 4. VI polish (10 finding — danh sách key trong appendix report 260728-1040)
- "Mật khẩu thứ hai" → "Mật khẩu cấp 2" (2 chuỗi); bỏ "nhé"; nhất quán hoa/thường "Nhóm/Thùng rác"; "đầu-cuối"→"đầu cuối"; sửa chuỗi dịch cứng.

## 5. String bugs
- `LooxPlanLandingScreen.swift:112` "computer approvals" → key "browser approvals".
- EN plural "Based on %lld items" — plural rule trong catalog EN/VI/JA (chuyển từ phase-02).

## 6. Docs sync
- `docs/design-guidelines.md` (SF exception nếu Phase 00.5 duyệt — sửa TRƯỚC phase-03), CLAUDE.md (EN+VI→EN+VI+JA), README, codebase-summary (bỏ "iPhone-only"), design-dna, deployment-guide, app-feature-map.

Validation: `make check`; chạy lại membership-test script (loc-completeness) = 0 miss; screenshot vi/ja màn chính.

Reports: `plans/260728-0945-release-hardening-and-tutorial/reports/`
