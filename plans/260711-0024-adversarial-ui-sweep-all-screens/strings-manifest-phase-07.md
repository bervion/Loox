# Strings Manifest — Phase 7 (Watchtower + Generator)

Every existing copy string touched or read across `Watchtower/*`/`Generator/*` was checked against
`Vaultify/Localizable.xcstrings` first. All static UI strings (band labels, category titles, HIBP
copy, Generator mode/option labels, "Copied", "Close"/"Cancel"/"Regenerate"/"Use Password") already
have EN source + VI translation — nothing to change there.

The real gap: `detail:` strings built with plain Swift string interpolation (not
`appString`/`String.LocalizationValue`) never reach the catalog at all and always render in
English. Found one instance inside this phase's ownership (`WatchtowerScreen.runHIBP`) — fixed in
code (wrapped in `appString(...)`) and listed below. A second, identical instance exists in
`Services/Watchtower/PasswordAudit.swift` (`"Used by %@ items"`) but that file is outside this
phase's ownership (`Watchtower/*`/`Generator/*` under `Features/`) — flagged in
`reports/phase-07-findings.md` for a follow-up task, not fixed here.

## New keys (append-only)

| Key | EN | VI | Context |
| --- | --- | --- | --- |
| `Seen %lld times in breaches` | Seen %lld times in breaches | Đã thấy %lld lần trong rò rỉ dữ liệu | `WatchtowerScreen.runHIBP` — per-item detail on the "Exposed password" drill-down row, shown after a HIBP k-anonymity check finds a breach count > 0. Was previously a raw Swift string interpolation with **no catalog entry at all** (not just missing VI) — always rendered in English. |
| `Add a password to see your vault's security score.` | Add a password to see your vault's security score. | Thêm mật khẩu để xem điểm bảo mật của kho. | `WatchtowerScreen.emptyVaultView` — new empty-vault state (0 items), replacing what previously fell through to a hollow "To fix" card with zero rows. |

## Not fixed here (follow-up needed)

| Key | EN (current, unlocalized) | Suggested VI | Context |
| --- | --- | --- | --- |
| `Used by %lld items` | Used by %lld items | Dùng chung bởi %lld mục | `Services/Watchtower/PasswordAudit.swift:75` — reused-password detail string, raw Swift interpolation, zero catalog entry. Out of this phase's file ownership; needs a small dedicated fix (wrap in `appString`) by the orchestrator or a follow-up task. |
