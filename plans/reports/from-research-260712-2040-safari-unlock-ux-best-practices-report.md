# Safari Web Extension Unlock UX — Best Practices Research + Vaultify Recommendation

Date: 2026-07-12 · Researcher report · No code modified.

## 0. Codebase ground truth (verified)

| Fact | Evidence |
|---|---|
| Handler is per-message, short-lived, stateless | `VaultifySafari/SafariWebExtensionHandler.swift:3-7` (doc comment), `:22-35` |
| Per-operation Face ID, nothing cached | `VaultifySafari/SafariMessageRouter.swift:29-41` (`liveContext.retrieveKey` → `BiometricKeyStore.retrieve`) |
| Fresh `LAContext` per retrieve, no reuse duration set | `VaultifyCore/Keychain/BiometricKeyStore.swift:54-66` |
| `status` cmd hardcodes `locked: true` | `VaultifyCore/WebExtensionRouter.swift:70-73` |
| Popup requires manual Unlock tap | `VaultifySafari/Resources/popup.js:175-198` (`initialize()` ends at `show("locked")`; unlock only on button click `:177`) |
| **AutoFill ext already solves this per-presentation**: ONE Face ID on appear (`.task`), key held in `@State var vaultKey: SecureBytes` for the whole UI presentation, all fills reuse it; `presetKey` variant avoids double-prompt across flows | `VaultifyAutoFill/UnlockGate.swift:30, 42-49, 70, 135-155` |
| App auto-lock: single `autoLock` timer (0/60/300/900/3600s, default 5 min), sliding `lastActivity`, background-elapsed check | `Vaultify/App/SettingsStore.swift:25-43,54,125`; `Vaultify/Security/VaultSession.swift:250-273` |
| `autoLock` stored in `UserDefaults.standard` — **extension cannot read it today** | `SettingsStore.swift:47` |
| App-group `UserDefaults` helper exists | `VaultifyCore/SharedConfig.swift:27` (`sharedDefaults`) |
| Key-never-crosses-bridge invariant | `WebExtensionRouter.swift:10-16`; whitelist gate `:109-112` |

## 1. What 1Password / Bitwarden / Dashlane actually do (iOS Safari)

**Only 1Password ships an iOS Safari Web Extension.** Bitwarden and Dashlane deliberately do NOT — both rely on the native AutoFill Credential Provider on iPhone. So 1Password is the only direct precedent; Bitwarden/Dashlane are precedent for "AutoFill is the primary surface".

- **1Password for Safari (iOS)** — biometric unlock inside the extension: "If you set up Touch ID or Face ID in the app, you can also use your fingerprint or face to unlock 1Password in Safari" ([1P getting-started-safari-ios](https://support.1password.com/getting-started-safari-ios/)). The extension keeps **its own session** with a user-configurable lifetime: popup menu → Settings → Security & privacy → "Reauthorize After" ([same source](https://support.1password.com/getting-started-safari-ios/)). Face ID in the iOS extension was initially missing (v8) and added later ([1P community](https://1password.community/discussion/132325/faceid-not-available-in-ios-safari-extension-version8)).
- **1Password device-unlock integration (iOS)** — "1Password will automatically unlock for up to 10 minutes when you unlock your iPhone or iPad" ([1P unlock-auto-lock](https://support.1password.com/unlock-auto-lock/)); with it on, "you may not see prompts to unlock with Face ID as often". Nov 2025 they extended this model to desktop with 3 lock presets; mobile keeps the stricter 10-minute window ([MacRumors 2025-11-13](https://www.macrumors.com/2025/11/13/1password-simplifies-access/)). Net behavior users perceive: open popup → if session valid, list appears instantly; if not, biometric prompt fires; cancel leaves a manual unlock UI. **No per-action re-prompting within a session — the session is the norm across the industry.**
- **Bitwarden** — no iOS Safari extension (open feature request, [community thread](https://community.bitwarden.com/t/bitwarden-safari-extension-for-ios-and-ipados/57281)); mobile is app+AutoFill ([bitwarden.com/download](https://bitwarden.com/download/)). Instructive negative example: their **macOS** Safari appex biometric unlock was long non-automatic/broken precisely because the appex can't hold state and IPCs to the desktop app ([GitHub bitwarden/clients#4594](https://github.com/bitwarden/clients/issues/4594), [contributing docs](https://contributing.bitwarden.com/getting-started/clients/browser/biometric/)) — validates that per-message statelessness is the real enemy, and that session state must live outside the handler process.
- **Dashlane** — "You don't need to use an extension with the Dashlane app on your iPhone" — AutoFill only on iOS; Safari extension is desktop-only ([Dashlane on Apple devices](https://support.dashlane.com/hc/en-us/articles/202699061-Dashlane-on-Apple-devices)).

**Auto-prompt on popup open:** there is no special WebExtension lifecycle event — the popup page's script simply runs every time the popup opens (our `initialize()` at `popup.js:198` already IS the hook). The idiomatic pattern (1P behavior) = attempt unlock immediately on popup open; **session caching is what makes this tolerable** (prompt fires only when session expired). Pitfalls if you auto-prompt WITHOUT a session: Face ID sheet on every popup open (annoyance), and cancel-loops — mitigate by never auto-retrying after a cancel within the same popup instance (show the manual Unlock button, which we already have).

## 2. Q4 first — `touchIDAuthenticationAllowableReuseDuration`: NOT viable

Apple docs ([LAContext.touchIDAuthenticationAllowableReuseDuration](https://developer.apple.com/documentation/localauthentication/lacontext/touchidauthenticationallowablereuseduration)): "If the user unlocks the device using **Touch ID** within the specified time interval, then authentication for the receiver succeeds automatically, without prompting the user for Touch ID… The maximum allowable duration for Touch ID authentication reuse is specified by the `LATouchIDAuthenticationMaximumAllowableReuseDuration` constant" (= 5 minutes).

Three independent kill-shots for our case:
1. **Touch-ID-only by contract.** The docs describe Touch ID exclusively; developer reports confirm Face ID keychain reads re-prompt regardless of the setting ([Apple dev forums / field reports](https://developer.apple.com/forums/tags/face-id), [Medium field report](https://medium.com/@anshulkoshti23/touchidauthenticationallowablereuseduration-10-is-not-working-on-your-app-1f24004f4d9e)). Every device Vaultify targets (iPhone, iOS 17.3+) is Face ID hardware.
2. **Reuse binds to a single `LAContext` instance** (or a Touch ID device-unlock event). Our handler builds a fresh `LAContext` per message (`BiometricKeyStore.swift:55`) in a process that is reaped between messages — there is no instance to reuse.
3. Even where it works, cap is 5 min and reliability with `SecItemCopyMatching` + `.biometryCurrentSet` is disputed in the field ([SO/forums](https://developer.apple.com/forums/thread/71180)).

Verdict: **reject option (d)**. Also note: Apple offers no blessed mechanism for this exact problem — the one dev-forum thread asking precisely our question (Safari extension + Face ID keychain, handler can't hold state) is unanswered ([forums/thread/696736](https://developer.apple.com/forums/thread/696736)).

## 3. Session-location options, ranked

| # | Option | Reliability | Security | Verdict |
|---|---|---|---|---|
| 1 | **(b)+(c) hybrid: short-TTL session keychain item** (`WhenUnlockedThisDeviceOnly`, shared access group, expiry embedded), written by ext after Face ID AND optionally by app on unlock | High — survives handler reaping, works across popup opens | Bounded no-user-presence window; item readable only by our own team-signed binaries in the access group, only while device unlocked, never leaves device/backup | **RECOMMENDED** |
| 2 | (a) process-static cache in handler | Poor/unpredictable — appex reaped between messages at OS discretion (our own header `SafariWebExtensionHandler.swift:3-7` documents this); works "sometimes" → inconsistent UX; adds a 2nd invalidation path | Best (memory-only) | Reject as primary; unnecessary as L1 given keychain read is ~ms (YAGNI) |
| 3 | (c) alone: piggyback app session via app-group token | Only helps when app was recently open — popup-first flows (the common case: user is in Safari) still Face-ID per op | Same class as (b) | Insufficient alone; fold into (1) as an optional writer |
| 4 | (d) LAContext reuse duration | Non-functional on Face ID hardware | n/a | Reject (§2) |

### Security analysis of the recommended session item
- **What weakens:** during TTL, `Vault Key` is retrievable from keychain **without user presence** (no `.biometryCurrentSet` ACL). Exposure ≈ 1Password's model, and strictly narrower than their "device unlock = 10 min unlocked".
- **Who can read it:** only binaries signed by team `WDNL2F75V7` in `SharedConfig.keychainAccessGroup` — the app + our two extensions. A malicious webpage still gets nothing new: JS bridge output is unchanged (metadata + whitelisted non-secret fields, enforced natively at `WebExtensionRouter.swift:109-112`).
- **At rest / stolen device:** `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` + `kSecUseDataProtectionKeychain` → ciphertext under device passcode class keys, unreadable while device locked, excluded from backups/migration ([Apple: Accessing keychain items with Face ID or Touch ID](https://developer.apple.com/documentation/LocalAuthentication/accessing-keychain-items-with-face-id-or-touch-id)). Residual risk = attacker holding the device **unlocked** during TTL — but that attacker can already read items in the unlocked app; delta is marginal.
- **Biometry change:** session item has no `.biometryCurrentSet`, so it would survive a biometric re-enrollment for up to TTL. Mitigate: clear it inside `BiometricKeyStore.delete()` and keep TTL short.

## 4. Recommended design for Vaultify (concrete)

**One new primitive + 5 touch points. Key never crosses the bridge; JS layer contract unchanged.**

### 4.1 `ExtensionSessionStore` (new file, `VaultifyCore/Keychain/extension-session… ` → `ExtensionSessionStore.swift`, ~80 LoC)
- Generic-password item, account `vault.extensionSession`, service `KeychainStore.service`, `kSecAttrAccessGroup = SharedConfig.keychainAccessGroup`, `kSecUseDataProtectionKeychain`, accessibility `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, **no biometric ACL**.
- Payload blob: `expiresAt (UInt64 epoch-seconds, 8 bytes) || vaultKey bytes`. TTL enforced in code on read: expired → delete item, return nil. Reads/writes never prompt.
- API: `save(vaultKey:[UInt8], ttl:TimeInterval)`, `load() -> [UInt8]?` (nil if absent/expired), `clear()`. All `nonisolated`, zeroize transients via `secureZero` (mirror `WebExtensionRouter.swift:137-141`).

### 4.2 Handler read path — `VaultifySafari/SafariMessageRouter.swift:33-41`
Replace `liveContext.retrieveKey` closure:
1. `ExtensionSessionStore.load()` → hit: return (no prompt; optionally re-save to slide the window).
2. Miss: `BiometricKeyStore.retrieve(reason:)` (Face ID) → on success `ExtensionSessionStore.save(key, ttl: sessionTTL)` → return.
- `sessionTTL` = mirrored app `autoLock` read from `SharedConfig.sharedDefaults` (§4.4); `.immediate` (0) → **skip saving entirely** → today's per-op behavior preserved for strict users.

### 4.3 Popup auto-prompt — `VaultifySafari/Resources/popup.js:175-198`
In `initialize()`, after the origin chip resolves (`:187-195`), call `unlockAndList()` directly instead of `show("locked")`. Existing behavior already handles the rest: `unlockCancelled` → `show("locked")` with the manual Unlock button (`:52`, `:177`) — that is the anti-cancel-loop (never auto-retry in the same popup instance). Within TTL the popup renders the list instantly with zero prompts. No background.js change needed (`listItems` path unchanged). Optional polish: make `status` (`WebExtensionRouter.swift:70-73`) report real session state (`ExtensionSessionStore` peek) instead of hardcoded `locked: true` — not required by the flow.

### 4.4 Mirror autoLock to the app group — `Vaultify/App/SettingsStore.swift:54`
`didSet` additionally writes `autoLock.rawValue` to `SharedConfig.sharedDefaults` (and backfill once at init `:125`). Extension reads it; missing value → default 300s. (Non-sensitive int — fine in app-group defaults.)

### 4.5 Invalidation — mirror the app's lock lifecycle (Q3: yes, respect app auto-lock)
| Trigger | Action | Where |
|---|---|---|
| TTL elapsed | `load()` self-deletes | ExtensionSessionStore |
| App locks (auto, panic shake, Lock Now) | `ExtensionSessionStore.clear()` | `VaultSession.lock()` — `Vaultify/Security/VaultSession.swift:149-155` (+ `lockToOnboarding` `:158-162`) |
| Biometric unlock disabled / vault reset / re-store | `clear()` inside `BiometricKeyStore.delete()` — `VaultifyCore/Keychain/BiometricKeyStore.swift:86-89` (also covers `store()`'s leading `delete()` `:35`) |
| Device locks | item unreadable while locked (accessibility class); TTL still bounds it after re-unlock | free |
| autoLock set to `.immediate` | no session ever written | §4.2 |

### 4.6 Optional piggyback (user decision D2): app unlock seeds the session
In `VaultSession.adoptUnlocked` (`VaultSession.swift:172-178`), also `ExtensionSessionStore.save(key, ttl: sessionTTL)` — mirrors 1P "unlocked app ⇒ extension unlocked", so a user who just used the app gets a zero-prompt popup. Slightly widens the window (session exists even if Safari never used). Recommend ON — matches user's "like 1Password" ask — but it is a policy choice.

### Why not extend to AutoFill?
`UnlockGate` already achieves once-per-presentation UX (`UnlockGate.swift:70,147-150`) and its per-presentation Face ID matches platform convention (Apple Passwords prompts per AutoFill session too). Adopting the session there would remove even that prompt — bigger behavior change, separate decision (D4). YAGNI for this fix.

### Effort / risk
~1 new 80-line file + ~30 lines of edits across 4 files + xcstrings untouched (no new user-facing strings except maybe a Settings row if TTL is made user-visible). Unit-testable: `WebExtensionRouterContext` already injects `retrieveKey` (`WebExtensionRouter.swift:45-50`), so tests can exercise session-hit/miss without keychain. Adoption risk: none external — zero new dependencies, all first-party APIs stable since iOS 8/13.

## 5. Decisions the USER must make
- **D1 — Session TTL policy:** recommend `TTL = app autoLock` (default 5 min), with a hard cap (suggest 15 min) so `autoLock = 1 hour` doesn't leave a 1-hour no-biometric key in keychain. Accept cap? Or uncapped = exact mirror of app?
- **D2 — App-unlock piggyback (§4.6):** ON (1P-like, most "automatic") or OFF (extension session only ever created by an in-extension Face ID)? Recommend ON.
- **D3 — Auto-prompt scope:** Face ID auto-fires on popup open whenever session expired (recommended, 1P-like), vs. auto-prompt only when a session previously existed, vs. keep manual button for first-ever unlock. Recommend always-auto with cancel → manual button.
- **D4 — Extend session to AutoFill extension** (skip its per-presentation Face ID when session valid)? Recommend NO for now.
- **D5 — Sliding vs fixed TTL:** sliding (refresh on each use, mirrors app `lastActivity` model at `VaultSession.swift:250-255`) vs fixed-from-unlock. Recommend sliding, consistent with the app.

## 6. Limitations / not covered
- 1Password's internal session storage mechanism on iOS Safari is not public; behavior inferred from official support docs + community threads, not source.
- Did not benchmark actual handler-process lifetime on-device (how long iOS keeps the appex warm) — irrelevant to the chosen design, which assumes zero warmth.
- Claim "Face ID never honors reuse duration" rests on Apple docs wording (Touch-ID-only) + multiple field reports; Apple has no explicit "does not apply to Face ID" sentence.
- Did not evaluate wrapping the session key under a Secure-Enclave key (non-biometric SE-wrap) — would harden against keychain-dump tooling on compromised devices at +~40 LoC; deferred as optional hardening (YAGNI unless threat model includes jailbroken-device-while-unlocked).

## 7. Open questions
1. D1–D5 above (TTL cap, piggyback, auto-prompt scope, AutoFill adoption, sliding/fixed).
2. Should the extension session state be surfaced in the app UI (e.g. "Safari extension unlocked" indicator / manual revoke)? Not required; 1P doesn't on iOS.

## Sources
- Apple: [touchIDAuthenticationAllowableReuseDuration](https://developer.apple.com/documentation/localauthentication/lacontext/touchidauthenticationallowablereuseduration) · [Accessing Keychain Items with Face ID or Touch ID](https://developer.apple.com/documentation/LocalAuthentication/accessing-keychain-items-with-face-id-or-touch-id) · [Dev forums thread 696736 (Safari ext + FaceID/Keychain, unanswered)](https://developer.apple.com/forums/thread/696736) · [Messaging between the app and JS in a Safari web extension](https://developer.apple.com/documentation/safariservices/messaging-between-the-app-and-javascript-in-a-safari-web-extension)
- 1Password: [Getting started with 1Password for Safari on iOS](https://support.1password.com/getting-started-safari-ios/) · [Unlock and auto-lock settings](https://support.1password.com/unlock-auto-lock/) · [Face ID unlock](https://support.1password.com/face-id/) · [Community: FaceID not available in iOS Safari extension (v8)](https://1password.community/discussion/132325/faceid-not-available-in-ios-safari-extension-version8) · [MacRumors: 1Password simplifies access (2025-11-13)](https://www.macrumors.com/2025/11/13/1password-simplifies-access/)
- Bitwarden: [Community: Safari extension for iOS/iPadOS (feature request)](https://community.bitwarden.com/t/bitwarden-safari-extension-for-ios-and-ipados/57281) · [clients#4594: biometric unlock not automatic on Safari/macOS](https://github.com/bitwarden/clients/issues/4594) · [Contributing docs: browser biometric IPC](https://contributing.bitwarden.com/getting-started/clients/browser/biometric/) · [Downloads (no iOS extension)](https://bitwarden.com/download/)
- Dashlane: [Dashlane on Apple devices (AutoFill-only on iOS)](https://support.dashlane.com/hc/en-us/articles/202699061-Dashlane-on-Apple-devices)
- Field report: [reuse duration not working (Medium)](https://medium.com/@anshulkoshti23/touchidauthenticationallowablereuseduration-10-is-not-working-on-your-app-1f24004f4d9e)
