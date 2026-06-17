---
name: vaultify-totp-home-privacy-model
description: How Vaultify protects sensitive on-screen secrets (TOTP codes, passwords) — two-layer model
metadata:
  type: project
---

Sensitive on-screen values (TOTP codes on Home, revealed passwords) are protected by TWO
independent layers — verify both when reviewing a new surface that shows secrets:

1. **Global app-switcher shield** — `RootView` shows an opaque `PrivacyShield` overlay when
   `scenePhase` is inactive/background AND `settings.hideInAppSwitcher` (default true). Covers
   the whole screen in the app-switcher snapshot.
2. **Per-view redaction** — `.privacySensitiveContents()` (`Typography.swift`, wraps
   `.privacySensitive(_:)`) marks the subtree for redaction in snapshots / screen recording.
   Defense-in-depth: still redacts if `hideInAppSwitcher` is off. Does NOT redact during normal
   foreground display (correct — an authenticator code must be visible).

**Lock-on-background:** `RootView.handleScenePhase(.background)` calls `session.lock()` when
`settings.lockOnBackground`, which triggers `repository.clear()`. Secrets are never persisted
— TOTP codes are computed live from the sealed field via `TOTPGenerator`; the in-memory
`items` array holds decrypted fields only while unlocked.

**How to apply:** A new screen showing secrets is compliant if it (a) carries
`.privacySensitiveContents()` on the secret subtree and (b) lives under the unlocked route
(so the global shield + lock-on-background apply). No need to add per-screen scenePhase
handling. Codes/passwords must never be logged. Related:
[[vaultify-localization-catalog-convention]].
