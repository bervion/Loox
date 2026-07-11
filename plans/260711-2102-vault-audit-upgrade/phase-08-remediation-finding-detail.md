# Phase 08 — Remediation queue, finding detail, ignore/accepted risk

**Priority:** P1 · **Status:** ☐ · **Ước lượng:** 1.5-2 ngày · **Phụ thuộc:** 07

## Fix queue (proposal §14)

`AuditFixQueueScreen` — queue deterministic, thứ tự cứng:
1. leaked+reused → 2. leaked → 3. veryWeak+reused → 4. veryWeak → 5. conflicting duplicates
→ 6. reused → 7. invalid OTP → 8. passkey/2FA opportunities → 9. cleanup.
Trong nhóm: sort theo category weight rồi title. `[Next issue]` đi tuần tự, progress "3 of 9".

## Finding detail screen

`AuditFindingDetailScreen`:
- Title + giải thích (localized key theo ruleID) + affected items list (tap → ItemDetail)
- Recommended action + actions theo `RemediationType`:
  - `changePassword`: [Open website] (URL item), [Generate replacement] (mở Generator sheet,
    copy/điền vào editor), [I changed it] → đánh dấu chờ recheck (KHÔNG "fixed" — chỉ re-audit
    xác nhận resolved; verify-first như phase 07)
  - `removeDuplicate`: side-by-side 2 item + updatedAt, [Keep this] → trash item kia qua
    `PolarisModal.destructive` (không auto-delete)
  - `addTOTP`/`addPasskey`: mở editor đúng section; catalog có `securitySettingsURL` → [Open
    security settings]
  - `fixData`: mở editor field liên quan
- Dismiss options (proposal §15): Remind me later (snooze 30 ngày) / Ignore this finding /
  This is not an account password / I no longer use this account. Ignore ghi reason +
  ruleVersion vào `FindingStateRecord` (phase 05). Critical ignore → confirm modal với copy
  "Loox will stop reminding you about this password" (EN+VI, không "!").
- Rule version bump / data đổi → state `needsRecheck`, hiện lại với badge "Needs review again".

## Score delta

Sau khi user xử lý và re-audit: `AuditResultScreen` hiện `874 → 912 (+38)` bằng
`.contentTransition(.numericText)`; KHÔNG cộng optimistic khi mới bấm "I changed it".

## Files

- **Tạo:** `Features/Watchtower/AuditFixQueueScreen.swift`, `AuditFindingDetailScreen.swift`,
  `AuditDismissSheet.swift`; `VaultifyCore/Audit/FixQueuePlanner.swift` (pure sort logic, test được)
- **Sửa:** `AuditResultScreen` ([Fix important issues] wiring), coordinator (recheck-on-demand
  1 item sau "I changed it": re-run rules scoped cho item đó, rẻ)

## Todo

- [ ] FixQueuePlanner + unit tests thứ tự
- [ ] Detail screen per RemediationType + actions
- [ ] Dismiss flow + FindingState wiring + needsRecheck badge
- [ ] Scoped recheck 1 item (strength/reuse/HIBP cache-first)
- [ ] Localize EN+VI, PolarisModal cho destructive, design-dna check
- [ ] `make check`

## Success criteria

Đi hết queue không dead-end; ignore không mất vĩnh viễn (rule bump gọi lại); mọi thay đổi score
chỉ sau re-audit.
