---
name: vaultify-localization-catalog-convention
description: How to correctly verify EN+VI coverage in Vaultify's Localizable.xcstrings (key IS the English source)
metadata:
  type: project
---

`Vaultify/Localizable.xcstrings` has `sourceLanguage: en`. The **string key itself is the
English source** (standard Xcode String Catalog behavior). So an entry needs only a `vi`
localization to be complete — `en` localization absent is NORMAL, not a bug. A few legacy
entries (e.g. "Spaces") carry an explicit `en` value, but that's incidental.

**Why:** A naive check that flags "en=None as missing" produces false positives. Only flag a
key as a localization gap if (a) the key is absent entirely, or (b) it has no `vi` value.

**How to apply:** When reviewing localization, look up each user-facing key; PASS if `vi`
exists. Interpolated keys use `%lld` (Int) / `%@` (String) — `appString("Foo \(intVar)")`
compiles to catalog key `"Foo %lld"`, and `appString("Foo \(strVar)")` → `"Foo %@"`.

**Known trap — clipboard toast labels are NOT localized:** the copy toast renders
`appString("Copied \(label)")` → key `"Copied %@"` (localized), but `label` is passed as a
raw English literal at the call site (e.g. `clipboard.copy(code, label: "2FA code")`), so the
substituted `%@` stays English for VI users. This is a pre-existing pattern across the app
("Password", "Recovery key", "2FA code") — flag as Low, not a new regression. Related:
[[vaultify-totp-home-privacy-model]].
