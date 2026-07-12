# Phase 02 — Unlock Bridge + Popup Read Path

## Context Links

- Research: `plans/reports/from-research-260712-1453-safari-web-extension-plan-report.md` §3 (messaging + unlock bridge), §5 (responsibility split)
- 1Password precedent: [Get to know 1Password for Safari on iOS](https://support.1password.com/getting-started-safari-ios/) — popup unlock via Face ID
- Prereq: Phase 01 gates G1 + G2 PASS

## Overview

- Priority: P1
- Status: code complete — `make check` + `make test` green (638/638); device gates pending (user): G1 (Face ID from headless handler, popup-initiated) and G3 (per-site grant + origin QA)
- Popup "Unlock with Face ID" → native message → `BiometricKeyStore.retrieve` → popup lists items matching the active tab's origin (logins metadata, identities, cards masked to last-4) + copy-username / copy-non-secret actions. Defines the full messaging protocol used by P3-P5.

## Key Insights

- Handler process is per-message and short-lived (report §3) → NO key caching across messages. Every operation needing the vault re-derives via Face ID keychain retrieval — same model as AutoFill today, fast (biometric-wrapped key, no Argon2). Repeated Face ID prompts per action are the accepted UX cost in v1; an "unlocked-recently" TTL flag (metadata only, shared defaults, NEVER key material) may soften popup UI state (report §5 "Unlock").
- Origin trust: background derives origin via `browser.tabs.query({active: true, currentWindow: true})` and passes it in the native message. Content-script-reported URLs are never used for matching (report §3.3). Native side cannot independently verify origin — trust boundary is the extension's own background page (Safari-isolated); acceptable because worst case = wrong metadata list shown in OUR popup, and fill payloads still require an explicit user tap on a specific item.
- Existing `VaultReader.logins(vaultKey:)` (`VaultifyCore/VaultReader.swift:28`) returns login category only; need a new reader for `.card` + `.identity` + host-scoped queries. Put it in `VaultifyCore/` so `VaultifyTests` covers it and AutoFill could reuse later.
- Host matching reuses `VaultItem.matchesAutoFill(serviceIdentifiers:)` (`VaultifyCore/Models/VaultItem.swift:131` region, surfaced via `autofillHosts`): registrable-domain-ish suffix matching, https-only enforced at fill (P3).

## Requirements

- Functional: popup states — locked (Unlock button) / unlocked (item lists per active origin: Logins [title+username, metadata only], Identities [title], Cards [title + brand + last-4]) / no-permission (explain per-site grant). Copy actions for non-secret values only (username, email). NO password/CC copy in v1 popup.
- Non-functional: message round-trip with vault query < 500ms after biometric; every new string EN+VI (`_locales` for popup, `Localizable.xcstrings` for `NSFaceIDUsageDescription`-adjacent native strings); popup UI approximates design-system tokens (colors/spacing mapped into `popup.css` custom properties — dark mode via `prefers-color-scheme`).

## Architecture

**Messaging protocol v1 (JSON over `sendNativeMessage`, versioned envelope):**

```
Request:  { v: 1, cmd: string, origin?: "https://host", itemId?: string, payload?: {...} }
Response: { v: 1, ok: bool, error?: code, data?: {...} }

cmds (this phase):
  status      → { locked: true }                      // always "locked"; unlock is per-op
  listItems   (origin) → { logins: [{id,title,username}], identities: [{id,title}],
                           cards: [{id,title,brand,last4}] }   // triggers Face ID
  copyValue   (itemId, fieldLabel) → { value }        // whitelisted non-secret kinds only
                                                       // (.username/.email/.text — FieldKind.swift:36 isSecret gate)
```

- `SafariMessageRouter` (P1) grows a `RouterContext` closure injection (`retrieveKey: () async throws -> [UInt8]`, `store: VaultStore`) so unit tests inject a fixed key + in-memory store (pattern: `VaultifyTests` memory `vaultify-test-target`).
- New `VaultifyCore/WebExtensionReader.swift`: `itemsMatching(origin:key:) -> WebExtItemLists` (decrypts titles/usernames/brand/last4 ONLY — full CC number never leaves this function's decrypt scope in this phase), `nonisolated` where possible, `@MainActor` where VaultStore requires.
- background.js: resolves origin from tabs API, attaches to every popup request, relays to native. popup.js renders lists; never persists anything to `browser.storage` except UI prefs (e.g. last-selected tab section).

**Data flow (listItems):** popup open → popup.js asks background → background `tabs.query` → origin → `sendNativeMessage({cmd:"listItems", origin})` → handler: Face ID → open store from App Group (`SharedConfig.appGroup`, `SharedConfig.swift:8`) → `WebExtensionReader.itemsMatching` → metadata JSON → popup renders. Key bytes zeroed after use (follow `SecretGuard.swift` conventions).

## Related Code Files

- Create: `VaultifyCore/WebExtensionReader.swift`; `VaultifyTests/WebExtensionReaderTests.swift`; `VaultifyTests/SafariMessageRouterTests.swift`
- Modify: `VaultifySafari/SafariWebExtensionHandler.swift`, `VaultifySafari/SafariMessageRouter.swift`, `Resources/background.js`, `Resources/popup.html|js|css`, `Resources/_locales/en|vi/messages.json`, `Vaultify/Localizable.xcstrings` (if native strings added)
- Read: `VaultifyCore/VaultReader.swift`, `VaultifyCore/Models/VaultItem.swift`, `VaultifyCore/Models/FieldKind.swift:36` (isSecret), `VaultifyCore/Keychain/BiometricKeyStore.swift`

## Implementation Steps

1. Define protocol structs (Codable) in `SafariMessageRouter.swift`; version field mandatory; unknown cmd → `{ok:false, error:"unsupported"}`.
2. Implement `WebExtensionReader.itemsMatching(origin:key:)`: parse origin → host; logins via `matchesAutoFill`; identities + cards are NOT host-scoped (global lists — identity/CC have no website field by default, `ItemCategory.swift:62-77`); mask card number to last-4 + brand detect (`PaymentCard.swift`).
3. Wire handler: `beginRequest` → decode → route → for vault cmds call `BiometricKeyStore.retrieve(reason:)` → reader → respond. Zero key after use.
4. `copyValue`: enforce whitelist — reject any `FieldKind.isSecret` or `protected == true` field with `error:"forbidden"` server-side (never rely on popup to hide the button).
5. popup.js states + rendering + copy via `navigator.clipboard.writeText` (popup context, allowed).
6. `_locales` EN+VI for all new strings; copy rules: no "!", no em-dash, no "·" (design-dna-standard).
7. Unit tests: router (echo, unknown cmd, forbidden copyValue, version mismatch), reader (origin matching incl. subdomain, masked card output contains ONLY last-4, identity metadata has no field values). Run `make test`.
8. Device QA **G3**: fresh install → enable → per-site grant flow ("Allow for One Day" / "Always Allow") → popup lists correct items for 3 real sites; wrong-origin site lists nothing; http:// page → popup shows "not supported on this page".

## Todo List

- [x] Protocol structs + router context injection (`VaultifyCore/WebExtensionRouter.swift` — routing core lives in VaultifyCore because `VaultifyTests` only compiles app-target sources; `VaultifySafari/SafariMessageRouter.swift` is the thin live binding)
- [x] `WebExtensionReader` with masked metadata (`VaultifyCore/WebExtensionReader.swift`)
- [x] Handler vault cmds with per-op Face ID + key zeroing (`SecureBytes` + `secureZero`)
- [x] popup states + lists + copy (non-secret only; states: locked / unlocking / list / empty / unsupported / error)
- [x] `_locales` EN+VI updated (unlock, sections, copy, errors; ping strings retired)
- [x] Unit tests green via `make test` (638 tests, 0 failures; suites `SafariMessageRouterTests` + `WebExtensionReaderTests`)
- [ ] G3 device QA recorded (user-owed; also re-verifies G1: Face ID presenting from the headless handler, popup-initiated)

## Success Criteria

- Popup lists origin-matched logins + global identities/cards with last-4 masking; secret copy rejected natively (test-proven); round-trip < 500ms post-biometric; `make test` + `make check` green; G3 PASS.

## Risk Assessment

| Risk | L×I | Mitigation |
|---|---|---|
| Face ID prompt per popup open annoys users | High×Med | Accepted v1; TTL metadata flag for UI copy only; revisit after QA |
| Handler memory cap (appex) on large vaults | Low×Med | Metadata-only decrypt; no full-item decode in list path |
| tabs.query returns no/odd origin (reader mode, about:) | Med×Low | Guard: non-https origin → "not supported" state |
| Popup CSS drifts from design system | Med×Low | Token map in popup.css reviewed against `docs/design-guidelines.md` |

## Security Considerations

- Per-op biometric; no key caching; metadata-only over bridge; secret-field copy blocked native-side; nothing sensitive in `browser.storage`; origin from tabs API only. CC full number is not decrypted at all in this phase.

## Next Steps

- P3 adds `getFillPayload` (the only cmd that ever returns field values) + the content-script fill engine.
