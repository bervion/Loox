# Phase 04 — Signup Assist + Generated Password + Save Prompt

## Context Links

- Research: `plans/reports/from-research-260712-1453-safari-web-extension-plan-report.md` §1 (save rows), §4 (1P double-prompt bug class), §7 (double save prompt row)
- 1Password double-prompt precedent: [community discussion 169233](https://www.1password.community/discussions/1password/on-iossafari-how-do-i-stop-1password-suggesting-to-save-passwords-filled-out-by-/169233)
- Native save capability already shipped: `Project.swift:184-189` (`SupportsSavePasswordCredentials`, `SupportsGeneratePasswordCredentials`, iOS 26.2+) + `VaultifyAutoFill/SavePasswordView.swift`
- Prereq: Phase 03 complete

## Overview

- Priority: P2
- Status: pending
- Detect signup/change-password pages; offer generated-password fill from popup (reuse `PasswordGenerator`); on submit of a NEW login, show an in-page save overlay that writes via `VaultWriter.createLogin` — but ONLY on devices without the native iOS 26.2 save path, to avoid the 1P double-prompt bug (gate G4).

## Key Insights

- Signup detection = classifier extension: `autocomplete="new-password"` (tier 1); two password fields in one form ⇒ signup/change (tier 4); single password + submit label regex (`sign up|register|create account|đăng ký|dang ky|tạo tài khoản`) (tier 3). Login pages (single `current-password`) are explicitly NOT handled — QuickType owns them (suppression rule, report §5).
- No `browser.notifications` on Safari (report §2) → save prompt must be an in-page shadow-DOM overlay injected by the content script.
- **Double-prompt gate:** JS cannot query "is my app the system credential provider" nor the iOS version reliably. Native side CAN: handler checks `ProcessInfo.processInfo.operatingSystemVersion >= 26.2` → protocol adds `capabilities` to the `status` response (`{nativeSave: bool}`); background caches it per session and the content script suppresses the save overlay when `nativeSave == true`. Whether native save actually fires for extension-filled forms is exactly what G4 verifies on device; if native save does NOT fire on 26.2+ for our filled generated password, flip policy to "overlay always, but debounce if a native sheet appeared" per observed behavior — decide at G4, record here.
- Save overlay reads ONLY user-typed values captured at submit intent (form `submit` listener + button-click fallback), never passive scraping (report §3.5). Values held in content-script memory, sent natively only when user taps Save in the overlay.
- `VaultWriter.createLogin(site:username:password:)` (`VaultifyCore/VaultWriter.swift:22`) is the same path the AutoFill save flow uses — no new persistence code, LWW/sync semantics inherited (memory: synced column changes bump `updatedAt` via existing writer).
- Generated password: `PasswordGenerator.generate` (`VaultifyCore/PasswordGenerator.swift:42`) runs NATIVE side (new cmd `generatePassword`) so the wordlist/entropy source stays native; extension appex must bundle `eff_large_wordlist.txt` if passphrase mode offered (mirror `Project.swift:200`) — v1: character passwords only, no wordlist resource, passphrases deferred.

## Requirements

- Functional: popup shows "Use generated password" when signup detected (fills both password + confirm fields); after submit, overlay "Save login to Loox?" with editable title/username → Save (Face ID → createLogin) / Not now / Never for this site (host stored in shared defaults via native, not browser.storage — survives extension reinstall and is auditable in-app later).
- Non-functional: overlay in closed shadow root, design-token-approximated styling, EN+VI strings, dismiss on scroll-away never steals focus; zero password logging.

## Architecture

```
signup-detector.js   # extends classifier output: pageType = login | signup | changePassword | none
save-overlay.js      # shadow-DOM prompt; submit-intent capture; talks to background only
```

**Protocol additions:** `generatePassword {options}` → `{password}` (native, no vault access, no Face ID); `saveLogin {origin, username, password, title}` → Face ID → `VaultWriter.createLogin` → `{ok, itemId}`; `neverSave {origin}` / `status.capabilities.nativeSave + neverSaveHosts` piggyback.

**Data flow (save):** user submits form → content script captured values (memory only) → overlay shown (if `nativeSave == false` && host not in neverSave) → user taps Save → background → native `saveLogin` → Face ID → createLogin → toast. Overlay auto-discards captured values after 60s or navigation.

## Related Code Files

- Create: `VaultifySafari/Resources/signup-detector.js`, `VaultifySafari/Resources/save-overlay.js`, `VaultifyTests/WebExtensionSaveLoginTests.swift`
- Modify: `content.js` (wire detector + overlay), `background.js` (capabilities cache), `popup.js/html` (generated-password action), `SafariMessageRouter.swift` + handler (`generatePassword`, `saveLogin`, `neverSave`, capabilities), `_locales/en|vi`, `manifest.json` (add `save-overlay.js`, `signup-detector.js` to content_scripts)
- Read: `VaultifyAutoFill/SavePasswordView.swift` + `CreateLoginView.swift` (native save precedent), `VaultifyCore/VaultWriter.swift`

## Implementation Steps

1. Native cmds: `generatePassword` (pure, tested), `saveLogin` (Face ID, createLogin, duplicate-host+username check → returns `error:"duplicate"` so overlay offers nothing in v1 beyond message "Already saved"), `neverSave` list in App Group shared defaults.
2. `status` capabilities: OS-version check native-side; background caches per browser session.
3. `signup-detector.js` heuristics + unit-style checks against P3 fixtures (add signup fixture + change-password fixture).
4. Popup generated-password flow: fills `new-password` fields via existing fill-engine path (tier-1 targets only).
5. `save-overlay.js`: closed shadow root, submit-intent capture, 60s value TTL, Save/Not now/Never actions.
6. Suppression wiring: overlay renders only when `capabilities.nativeSave == false` AND host not never-saved AND pageType ∈ {signup, changePassword} AND values present.
7. Device QA **G4**: (a) iOS 26.2+ device: fill generated password → submit → verify NO extension overlay AND observe whether native save sheet appears; (b) iOS 17.x-26.1 device/sim: overlay appears, Save creates item visible in app + AutoFill QuickType. Record both outcomes; adjust policy per Key Insights if native sheet doesn't fire.
8. Swift tests: saveLogin routing (duplicate, forbidden origin http, missing fields), generatePassword determinism of options handling. `make test`.

## Todo List

- [ ] generatePassword + saveLogin + neverSave native cmds with tests
- [ ] Capabilities (nativeSave) in status
- [ ] signup-detector + fixtures
- [ ] Popup generated-password fill
- [ ] save-overlay shadow DOM + submit capture + TTL
- [ ] Suppression logic wired
- [ ] G4 dual-device QA recorded, policy confirmed
- [ ] EN+VI strings; `make test` green

## Success Criteria

- Signup fixture + 2 real signup pages: generated password fills both fields; save overlay creates a login that AutoFill immediately serves; on 26.2+ no double prompt observed (G4 PASS); duplicate save handled gracefully.

## Risk Assessment

| Risk | L×I | Mitigation |
|---|---|---|
| Double save prompt on 26.2+ | Med×High | Native-side version gate + G4 device verification before enabling overlay by default |
| Submit-intent capture misses SPA "submit" (fetch, no form event) | High×Med | Button-click fallback + password-field blur heuristic; accept partial coverage v1 |
| Overlay clickjacked/spoofed by page | Med×Med | Closed shadow root, extension-namespaced z-index, values never in DOM attributes; page can still overlay OURS — user education copy, revisit P6 |
| Never-save list grows unmanaged | Low×Low | Stored in App Group defaults; in-app management screen deferred (backlog note) |

## Security Considerations

- Captured credentials: memory-only, 60s TTL, sent natively only on explicit Save tap, Face ID gates the write. Never-save list contains hosts only (no secrets). `generatePassword` returns a fresh password (not vault data) — no biometric needed, but rate-limit (5/min) to avoid page-scripted abuse via compromised renderer (defense in depth; page can't call runtime APIs, but cheap to add).

## Next Steps

- P5 inline menu reuses detector + fill engine; save overlay patterns inform inline menu shadow-DOM hygiene.
