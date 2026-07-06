# P2.3 — Extension persona-aware prefill (App Group mirror + VaultReader)

## Context links
- Canonical: `proposal-v3-locked-decisions.md` — **INV-R03**. Overview: `p2-plan.md`. Consumes P2.1 engine rule + P2.2 accessors.
- Verified today: `AutoFillView.swift:125` prefills `defaultUsername = VaultReader.defaultIdentityUsername(...)`;
  `CreateLoginView` (`CreateLoginView.swift:20-28`) seeds its username field from that. `activePersonaID` is in
  `UserDefaults.standard` (`SettingsStore.swift:87,112`) — the extension **cannot** read it. Only `preferredLanguage`
  is mirrored to `SharedConfig.sharedDefaults` (`SettingsStore.swift:106`).

## Overview
- **Priority:** P2 · **Status:** pending · **Depends on:** P2.2
- The EXTENSION half of INV-R03. The extension prefills a NEW login's username from the GLOBAL default identity
  with no persona knowledge → under a strictAnonymous active persona that is a cross-persona leak. Close it with a
  thin App-Group mirror (opaque IDs + policy enum only) + a persona-aware resolver.

## Key insights / decision
- **Do NOT** mirror a resolved plaintext email into App-Group defaults (new leak vector). Mirror only:
  `policy` (enum raw) + `primaryProfileItemID` (opaque UUID, not identity-bearing). The extension already holds the
  Vault Key post-unlock + `VaultStore` → it decrypts that ONE item to get the email. Cheap (one record), memory-safe.
- **Fail-closed:** strictAnonymous + no own profile ⇒ prefill "" (empty), never `defaultIdentityUsername`.
- Stale mirror (persona deleted) ⇒ `item(id:)` miss ⇒ falls through; under strictAnonymous still returns "" (safe).

## Requirements
- App writes `activePersonaIsolationPolicy` + `activePersonaProfileItemID` to `SharedConfig.sharedDefaults` on
  every `reload()` and every `setActivePersona(_:)`.
- `VaultReader.autofillPrefillUsername(vaultKey:)`: own profile email/name if `primaryProfileItemID` resolves;
  else "" when strictAnonymous, else existing `defaultIdentityUsername`.
- `CreateLoginView` API unchanged (still receives `defaultUsername`); only its source changes.

## Architecture / data flow
```
App: reload()/setActivePersona → mirrorActivePersonaContext() → SharedConfig.sharedDefaults{policy, profileItemID}
Extension: AutoFillView.task → VaultReader.autofillPrefillUsername(vaultKey) → CreateLoginView(defaultUsername:)
```
```swift
// SharedConfig.swift
static let activePersonaPolicyKey = "active_persona_policy"
static let activePersonaProfileItemKey = "active_persona_profile_item"

// VaultReader.swift (nonisolated read of mirror; @MainActor decode via VaultStore)
@MainActor static func autofillPrefillUsername(vaultKey: [UInt8]) -> String {
    let policy = PersonaIsolationPolicy(rawValue:
        SharedConfig.sharedDefaults.string(forKey: SharedConfig.activePersonaPolicyKey) ?? "") ?? .standard
    if let pid = SharedConfig.sharedDefaults.string(forKey: SharedConfig.activePersonaProfileItemKey),
       let u = username(forItemID: pid, key: vaultKey) { return u }
    if policy == .strictAnonymous { return "" }            // INV-R03 #6 — no cross-persona fallback
    return defaultIdentityUsername(vaultKey: vaultKey) ?? ""
}
```
`username(from:)`/`username(forItemID:)` extracted as a shared VaultReader helper (DRY with `defaultIdentityUsername`,
`VaultReader.swift:46-50`).

## Related code files
- **Modify:** `VaultifyCore/SharedConfig.swift` — two keys (near `languageKey`, `:31`).
- **Modify:** `VaultifyCore/VaultReader.swift` — `autofillPrefillUsername` + `username(forItemID:key:)` helper; refactor `defaultIdentityUsername` to reuse helper.
- **Modify:** `VaultifyAutoFill/AutoFillView.swift` — line 125 → `VaultReader.autofillPrefillUsername(vaultKey:)`.
- **Modify:** `Vaultify/Data/Repositories/VaultRepository.swift` — call `mirrorActivePersonaContext()` in `reload()` after `normalizeDefaultPersona()` (`:77`).
- **Modify:** `Vaultify/Data/Repositories/VaultRepository+Personas.swift` — `setActivePersona` (`:99-101`) also calls `mirrorActivePersonaContext()`.
- **Create:** `VaultifyTests/AutofillPrefillIsolationTests.swift`

> `mirrorActivePersonaContext()` body lives in `VaultRepository.swift` (owns `reload`); it reads `activePersona` and
> writes the two shared-defaults keys. Kept OUT of `+PersonaContext.swift` (P2.2-owned) to preserve file ownership.

## Implementation steps
1. Add the two `SharedConfig` keys.
2. VaultReader: extract `username(from item:)`; add `username(forItemID:key:)` (fetch record by id from `VaultStore.allRecords()`, decrypt, extract); add `autofillPrefillUsername`. Keep `defaultIdentityUsername` behavior identical.
3. `AutoFillView` task: swap the prefill call. `CreateLoginView` untouched.
4. Repository: add `mirrorActivePersonaContext()`; call from `reload()` + `setActivePersona`.
5. `tuist generate --no-open`; `make check` (compiles app + embedded extension).
6. Tests + `-only-testing:VaultifyTests/AutofillPrefillIsolationTests`.

## Todo
- [ ] SharedConfig keys
- [ ] VaultReader `autofillPrefillUsername` + shared helper (no `defaultIdentityUsername` regression)
- [ ] AutoFillView uses new func
- [ ] mirror on reload + setActivePersona
- [ ] tests green; `make check` builds extension

## Success criteria
- With mirror = {strictAnonymous, profileItemID=nil}: `autofillPrefillUsername` returns "" even though a default
  identity exists (assert ≠ default email) — INV-R03 #6.
- With mirror = {strictAnonymous, profileItemID=own}: returns the OWN profile email only.
- With mirror = {standard, profileItemID=nil}: returns `defaultIdentityUsername` (unchanged behavior).
- `defaultIdentityUsername` output identical to pre-change for all inputs (no regression).
- `make check` builds both targets (extension memory: one extra single-record decrypt, no new caches).

## Risk assessment
- **High L × High I:** mirror not written / stale → wrong prefill. Mitigation: write on BOTH reload + switch; opaque
  IDs; fail-closed under strictAnonymous; test the stale (nil profileItemID) path.
- **Med:** two writers of shared defaults (this + language) — independent keys, no contention.
- **Low:** extension reads mirror before first app reload (fresh install) → keys absent → `.standard` default →
  existing behavior. Acceptable (no persona = no isolation expectation yet).

## Security
- Only an enum + an opaque UUID cross into App-Group defaults — no identity-bearing plaintext. Email stays sealed;
  resolved in-extension under the Vault Key, same posture as `defaultIdentityUsername` today.

## Next steps
Manual device QA before release: switch to a strictAnonymous persona in-app, trigger web-registration AutoFill,
confirm the New-login username field is NOT prefilled with the personal email. Parallel-safe with P2.4 except the
shared `Localizable.xcstrings` (this phase adds none; if any, serialize).
</content>
