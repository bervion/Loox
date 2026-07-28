# Release Hardening — Plan (re-baselined v2)

- Created: 2026-07-28 · v2 10:40 (re-baseline theo red-team review của owner; v1 dependency graph sai, thiếu Phase 00)
- Base: `main` @ `3c5ef6a` (v1.43.0)
- Nguồn: `plans/reports/deep-audit-260728-0945-release-readiness-report.md` (v2) + appendix `deep-audit-260728-1040-medium-low-findings-appendix.md`
- Status: **PENDING — Phase 00 chưa khóa, KHÔNG bắt đầu phase code nào trước đó**

## Thứ tự thực thi

| Bước | Phase file | Nội dung | Gate |
|---|---|---|---|
| 0 | `phase-00-scope-freeze-and-gates.md` | Decisions: backup contract, Quick View, iPad AutoFill scope, support contact, SF-exception docs; CloudKit Production inventory đầy đủ | Chặn tất cả |
| 1 | `phase-01-data-safety-critical.md` | Transactional L2 disable, backup theo contract đã chốt, folder dangling | Sau 00 |
| 2 | `phase-05-security-hardening.md` | Domain matcher contract chung, CloudKit chunking, Watchtower snooze + L2 scoring | Sau 00; song song bước 1 (không chạm file chung) |
| 3 | `phase-02-owner-reported-bugs.md` | Watchtower CTA iPhone, share permission UX, theme mitigation + repro, name autocorrect, identity email (sau repro) | Sau 1 (đụng L2/Level2Settings) |
| 4 | `phase-06-localization-release-pipeline.md` | JA metadata/scripts/InfoPlist, VI/JA polish, docs sync | Sau 00 |
| 5 | `phase-07-ipad-parity-and-release-ops.md` | iPad AutoFill (nếu in-scope), release hygiene, **Signed RC** + full QA | Sau 1–4 |
| 6 (track riêng, feature-flag) | `phase-03-onboarding-polish.md` → `phase-04-tutorial-core.md` | Onboarding polish + TutorialKit | Không chặn RC trừ khi owner quyết ngược |

## Dependency thật (sửa từ v1)

- 01 ↔ 02: cùng chạm Level-2 (`VaultSession+Level2`, `Level2SettingsView`) → 02 mục identity-email đi SAU 01.
- 02 ↔ 03/04: pre-permission component dùng chung → component sống ở app layer (Sharing dùng trước; onboarding/tutorial tiêu thụ sau, không đảo).
- 02 ↔ 06: plural "Based on %lld items" sửa 1 nơi trong catalog — gán cho 06, bỏ khỏi 02.
- 03 ↔ 06: SF-exception phải vào `docs/design-guidelines.md` (Phase 00.5) trước; docs sync còn lại ở 06.
- Sync/CloudKit chunking (05) độc lập file với 01.

## Acceptance criteria (toàn plan)

1. Không còn đường mất dữ liệu ở L2-off / backup / deleteFolder; L2-off là transaction 2 bước có preflight + verify (test tự động từng case, gồm case crash giữa chừng).
2. 3 surface fill (OS AutoFill, QuickType, Safari) dùng CHUNG một matcher contract exact/label-boundary parent-child; bộ test thêm IDN/punycode, trailing dot, IP, sibling subdomain, public suffix; test cũ codify substring bị thay.
3. Watchtower CTA hoạt động trên iPhone + iPad; snooze hết hạn resurface; audit score loại field L2-sealed.
4. Share flow: pre-permission explainer → grant tự tiếp tục; denied có nút mở Settings; không dead-end.
5. Reviewer một thiết bị không gặp dead-end ở bất kỳ feature nào hiển thị; flow 2 thiết bị có mô tả + video ổn định trong Review Notes; không tạo bypass bảo mật cho reviewer.
6. JA đủ: metadata/apple/ja + generator/release.sh + InfoPlist EN/VI/JA; docs hết "iPhone-only / EN+VI".
7. Signed RC (Release config, TestFlight artifact) qua full QA: unit + Safari harnesses + recovery/import roundtrip + máy thật (Face ID, AutoFill, sharing 2 thiết bị).
8. Tutorial track: TutorialKit sau feature flag, 60fps iPhone 11, Reduce Motion, EN/VI/JA — nghiệm thu riêng, không gộp RC.

## Verification protocol

Narrow test trước, broaden khi chạm contract chung (ItemSecret codec, sync planes, extension router). Không đưa plan/audit label vào code artifact.
