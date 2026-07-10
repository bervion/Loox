# Strings manifest — Phase 4 (Search superpower)

New/changed user-facing strings introduced by `SearchZeroStateView.swift` / `SearchScreen.swift`.
Coordinate with the P1 owner of `Localizable.xcstrings` — this phase does not edit that file
directly (per phase-04 file ownership).

| Key (EN source) | EN | VI |
|---|---|---|
| `Quick filters` | Quick filters | Bộ lọc nhanh |

## Context
- `Quick filters` is the section label above the zero-state chip row (Codes / Passkeys / Cards /
  Weak) in `SearchZeroStateView.swift`. The only genuinely new catalog key this phase needs.
- Every other displayed string in the new zero-state view **reuses an existing, already-translated
  catalog key verbatim** — no new entries needed for these:
  - `"Recently Used"` (section header) — existing key, VI `Dùng gần đây`.
  - `"Weak"` (chip label) — existing key, VI `Yếu`.
  - `"Passkeys"` (chip label) — existing key, VI `Passkey`.
  - `FieldKind.totp.title` = `"One-time Code"` (Codes chip label) — existing key, VI `Mã xác thực`.
  - `ItemCategory.card.title` = `"Payment Card"` (Cards chip label) — existing key, VI `Thẻ thanh toán`.
- Note for whoever reconciles the phase-03 manifest: that file proposes a *new* `Recently Used` →
  `Sử dụng gần đây` pair, but the catalog already carries `Recently Used` → `Dùng gần đây`
  (translated). Worth a decision (keep existing wording vs. update it) rather than adding a
  duplicate/conflicting translation for the same source key.

## Operator keywords (NOT catalog strings)
The local search-operator grammar (`SearchOperators.swift`) recognizes standalone EN + VI
keyword tokens typed into the search field (e.g. `weak` / `yếu`, `reused` / `trùng`). These are
match tokens, not displayed UI text, so they are hardcoded literals in `SearchOperators.swift`
(diacritic-/case-folded at compare time) rather than catalog entries — consistent with the phase
file's "Keyword→predicate map ... pure, testable, EN+VI synonyms" instruction. Full list:

| Operator | Keywords |
|---|---|
| has TOTP | `2fa`, `otp`, `mfa`, `totp`, `code`, `mã` |
| weak password | `weak`, `yếu` |
| reused password | `reused`, `reuse`, `duplicate`, `trùng`, `lặp` |
| has passkey | `passkey`, `passkeys` |
| category: login | `login`, `logins`, `đăng nhập` |
| category: note | `note`, `notes`, `ghi chú` |
| category: card | `card`, `cards`, `thẻ thanh toán` |
| category: identity | `identity`, `identities`, `danh tính` |
| category: sshKey | `ssh`, `sshkey`, `ssh key`, `khóa ssh` |
| category: recoveryCodes | `recovery`, `recoverycodes`, `recovery codes`, `mã khôi phục` |
| category: securityQuestions | `security`, `securityquestions`, `security questions`, `câu hỏi bảo mật` |
| category: custom | `custom`, `tùy chỉnh` |
