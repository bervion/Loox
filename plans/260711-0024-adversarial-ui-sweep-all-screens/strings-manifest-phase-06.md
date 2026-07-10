# Strings Manifest — Phase 6 (Item Editor)

All copy touched by this phase's fixes was verified against `Vaultify/Localizable.xcstrings` first
(source = key text; localizations only present when overridden). Every existing string used across
`Features/ItemEditor/*` already has EN (source) + VI. Only one real gap found: two `AttachmentPickerSheet`
error strings were plain Swift literals (never routed through `appString()`), so they were **entirely
missing** from the catalog — not just missing VI. Fixed in code (wrapped in `appString(...)`) and listed
below for the orchestrator merge.

## New keys (append-only)

| Key | EN | VI | Context |
| --- | --- | --- | --- |
| `Couldn’t open the file.` | Couldn’t open the file. | Không thể mở tệp này. | `AttachmentPickerSheet` — the picked file's security-scoped resource failed to open (permission/URL issue) |
| `Couldn’t read the file.` | Couldn’t read the file. | Không thể đọc tệp này. | `AttachmentPickerSheet` — `Data(contentsOf:)` failed after the URL opened (corrupt/unreadable file) |

No other new or changed user-facing strings. All other fixes in this phase were token/typography/
hit-target/localization-wrapper substitutions with no copy changes.
