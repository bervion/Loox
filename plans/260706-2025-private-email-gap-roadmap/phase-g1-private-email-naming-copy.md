# G1 — Private Email naming & copy

Priority: high (cheap, unblocks consistent copy for later phases). Status: pending.

## Scope

Rename user-facing surface per proposal terminology table. Internal names (`EmailAlias`,
`AliasStatus`) unchanged — user-facing strings only.

| Internal | EN | VI |
|---|---|---|
| feature name | Private Email | Email riêng tư |
| persona-tier alias | Reusable address | Địa chỉ dùng lâu dài |
| perSite alias | Private address for this site | Địa chỉ riêng cho trang này |
| destination | Forwarding inbox / Forwards to | Hộp thư nhận |
| disabled | Forwarding paused | Đã tạm dừng chuyển tiếp |
| disable action | Pause forwarding | Tạm dừng chuyển tiếp |

## Tasks

- [ ] `PersonaAliasesScreen`: title "Private Email"; section names; "Disable" → "Pause";
      status labels ("Active" → "Forwarding active", "Disabled" → "Forwarding paused").
- [ ] `AliasDetailScreen`: same terminology; permanent-delete modal copy per proposal §16.2
      (address shown, "can never be restored", password-reset warning) EN+VI.
- [ ] Pause confirmation (non-destructive): "Pause forwarding? … You can turn forwarding
      back on later." (resume itself lands in G5).
- [ ] `ProfileScreen` entry row: "Private Email".
- [ ] Masked email helper `EmailMask.masked("chinh@gmail.com") → "ch***@gmail.com"` (pure,
      VaultifyCore, unit-tested). Use for destination in overview surfaces; full email only in
      explicit forwarding settings.
- [ ] All strings EN+VI in `Localizable.xcstrings`.

## Success

- `make check` + `make test` green; no user-visible "alias/Disable" terminology left on
  Private Email surfaces; masked destination in list/detail overview.
