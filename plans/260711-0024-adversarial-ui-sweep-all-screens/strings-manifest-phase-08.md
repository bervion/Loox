# Strings Manifest — Phase 8 (Settings core + Security + Data)

Every copy string touched by this phase's fixes was checked against `Vaultify/Localizable.xcstrings`
first. The real gap was in `ImportView`: 8 error-path strings were assigned as raw Swift `String`
literals to a `@State private var error: String?`, then rendered via `Text(error)`. Because `error` is
a `String` variable (not a string literal), SwiftUI resolves the `StringProtocol` (verbatim) `Text`
initializer, not the `LocalizedStringKey` one — so these messages ignored the catalog entirely and
always rendered in English, independent of whatever the catalog happened to contain. Fixed in code by
wrapping every site in `appString(...)` (matching the established pattern already used elsewhere in
this same phase, e.g. `RegenerateKitView`).

## New keys (append-only)

| Key | EN | VI | Context |
| --- | --- | --- | --- |
| `Couldn’t open the file.` | Couldn’t open the file. | Không thể mở tệp này. | `ImportView` — the picked file's security-scoped resource failed to open. **Key already existed in the catalog with an EN comment but no VI value** — this fills the missing VI. |
| `Couldn’t read the file.` | Couldn’t read the file. | Không thể đọc tệp này. | `ImportView` — `Data(contentsOf:)` failed after the URL opened. **Key already existed with no VI value** — this fills it. |
| `No items found in that file.` | No items found in that file. | Không tìm thấy mục nào trong tệp này. | `ImportView` — CSV parsed successfully but yielded zero rows. **Key was entirely missing from the catalog** (new). |
| `Unsupported file format.` | Unsupported file format. | Định dạng tệp không được hỗ trợ. | `ImportView` — file is neither a valid encrypted backup JSON nor readable UTF-8 text. **Key was entirely missing** (new). |
| `Couldn’t decrypt, check the password.` | Couldn’t decrypt, check the password. | Không thể giải mã, hãy kiểm tra lại mật khẩu. | `ImportView.decrypt` — wrong backup password. Replaces the previous (also-unlocalized, also never-rendered-because-verbatim) source string `Couldn’t decrypt — check the password.`, which is **not in the catalog at all** and is now orphaned/unused — safe to prune on the next catalog reconciliation (Phase 15). |
| `Couldn’t generate a new recovery key. Please try again.` | Couldn’t generate a new recovery key. Please try again. | Không thể tạo khóa khôi phục mới. Vui lòng thử lại. | `RegenerateKitView` — surfaces a previously-silent failure: `generateRecoveryKit()` throwing was swallowed by `try?` with no user-visible error and no haptic. New string, new inline error state (`generateError`), no change to the underlying crypto call. |

## Existing keys reused (no catalog change needed — already EN+VI, just needed the `appString()` wrapper to actually be reachable at runtime)

| Key | Where |
| --- | --- |
| `Backup contained no records.` | `ImportView.decrypt` |
| `Unlock your vault before importing passkeys.` | `ImportView.performImport` |
| `Import failed before all records could be saved.` | `ImportView.performImport` |

## Not localized (intentional, pre-existing dev-tool exemption — unchanged by this phase)

`ShareDiagnosticsView`'s placeholder values (`"unknown"`, `"not set"`, `"No diagnostics yet."`) and
`SyncSettingsView`'s DEBUG-only diagnostic strings remain plain `Text(verbatim:)` / raw Swift strings,
consistent with the file's own existing comment ("Plain unlocalized strings on purpose — DEBUG-only,
deleted after the gate"). These are dev/QA-only surfaces gated behind `#if DEBUG` navigation, not
user-facing prose — not added to the catalog.

No other new or changed user-facing strings in this phase. All other fixes were token/typography/
haptics substitutions with no copy changes.
