# Safari Web Extension for Vaultify — Research Report

Date: 2026-07-12 · Researcher agent · No code modified.
Scope: add a 1Password-style Safari Web Extension target to the existing SwiftUI app (app + AutoFill Credential Provider, Tuist-generated, iOS 17.3+).

---

## 1. Feasibility Matrix

| Desired capability | iOS Safari Web Ext? | Credential Provider? | Verdict / notes |
|---|---|---|---|
| Toolbar icon in Safari | ✅ Yes | ❌ | Extension icon lives in the `aA` / puzzle-piece Page Settings menu (iOS 15–17) and directly beside the address bar on newer iOS once granted. Tapping opens the `action` popup (sheet on iPhone). Per-site permission prompts gate everything. |
| Detect login pages | ✅ Yes (content script heuristics) | Partial (only field focus events, no page context) | Content script classifies forms via `type=password`, `autocomplete` attrs, labels, form action. |
| Autofill credentials (user/pass) | ✅ Possible | ✅ **Already shipped** | iOS routes password autofill through the Credential Provider (QuickType bar). Web-ext credential fill is redundant + conflicts: 1Password **hides its inline menu on iOS when the same app is the system AutoFill provider** to avoid double UX. Keep credentials native; web ext only covers non-standard fields the QuickType bar misses. |
| Detect + fill registration/signup | ✅ Yes | Partial (iOS 26.2+ native save sheet + strong password — already enabled in `Project.swift` capabilities) | Web ext detects signup forms (new-password + email/confirm heuristics), fills generated password + identity fields, shows save prompt overlay. Pre-26.2 devices get save via web ext; ≥26.2 risk of **double save prompt** — must coordinate. |
| Fill Identity (name/address/phone) | ✅ **Web ext only** | ❌ impossible | ASCredentialProvider API has no identity/contact fill. iOS gives 3rd parties no other hook. This is the #1 net-new value of the web ext. |
| Fill credit cards | ✅ **Web ext only** | ❌ impossible | System Safari CC autofill = Apple Wallet/Keychain only. 1Password fills CC via its Safari extension exactly this way. #2 net-new value. |
| Fill TOTP into custom fields | ✅ Yes | ✅ (iOS 18+ `ProvidesOneTimeCodes`, shipped) | Web ext useful only for exotic OTP fields QuickType misses. |
| Save-new-login prompt on submit | ✅ Yes | iOS 26.2+ only | Web ext gives pre-26.2 parity. |

**Boundary summary:** Credential Provider stays the source of truth for passwords/passkeys/OTP. The web extension adds: toolbar presence, identity fill, credit-card fill, custom/non-standard field detection, signup-page assistance, save prompts on older iOS.

---

## 2. iOS Safari Web Extension Architecture (Q1)

- **Packaging:** an app extension (`.appex`) embedded in the app, `NSExtensionPointIdentifier = com.apple.Safari.web-extension`, `NSExtensionPrincipalClass = SafariWebExtensionHandler` implementing `NSExtensionRequestHandling` (SafariServices). Supported since iOS 15; MV3 since Safari 15.4 → fine on iOS 17.3+ floor. ([Apple: Safari web extensions](https://developer.apple.com/documentation/safariservices/safari-web-extensions), [Tech Talk 110148](https://developer.apple.com/videos/play/tech-talks/110148/), [extension.ninja MV3](https://www.extension.ninja/blog/post/apple-safari-manifest-v3-support/))
- **Web layer:** standard WebExtension bundle in the appex resources — `manifest.json` (MV3), content scripts, background script, `action` popup HTML, `_locales/`.
- **Background:** MUST be non-persistent on iOS. Two options: MV3 service worker, or `"background": {"scripts": [...], "persistent": false}`. **Prefer the non-persistent background page**: (a) MV3 service workers can't be debugged from Safari's Develop menu; (b) since ~iOS 17.4 there's a documented bug where the extension service worker is **permanently killed 30–45 s after install and never wakes** ([Apple forums 758346](https://developer.apple.com/forums/thread/758346)). Non-persistent classic background scripts wake reliably on events.
- **APIs available on iOS:** `runtime` (incl. `sendNativeMessage`, `connectNative`), `storage`, `tabs` (subset), `scripting`, `declarativeNetRequest`, `i18n`, `action` (popup).
- **NOT supported on iOS (vs macOS / Chrome):** `webRequest` (limited on macOS, **absent on iOS**), `notifications` (absent in Safari entirely), `identity`/`launchWebAuthFlow`, `cookies.onChanged`, devtools panels, sidebar. `contextMenus` is effectively useless on touch. ([Evil Martians conversion guide](https://evilmartians.com/chronicles/how-to-quickly-and-weightlessly-convert-chrome-extensions-to-safari), [Apple compat doc](https://developer.apple.com/documentation/safariservices/assessing-your-safari-web-extension-s-browser-compatibility))
- **Toolbar icon & permissions model:** user must enable the extension (Settings → Apps → Safari → Extensions, or Safari `aA` → Manage Extensions), then grant per-site access: "Allow for One Day" / "Always Allow" → "Always Allow on Every Website". Icon shows a warning badge until granted. `host_permissions: ["<all_urls>"]` produces the scariest prompt; unavoidable for a password manager (1Password requires it too). ([MacStories iOS 15 review](https://www.macstories.net/stories/ios-and-ipados-15-the-macstories-review/17/), [iMore how-to](https://www.imore.com/how-add-and-enable-extensions-safari-iphone-and-ipad))

---

## 3. Native ↔ Extension Messaging + Unlock Bridge (Q3)

**Message path:**
```
content script (page world? NO — isolated world)
  └─ browser.runtime.sendMessage ─► background script
        └─ browser.runtime.sendNativeMessage("app.id", msg)   [needs "nativeMessaging" permission]
              └─ SafariWebExtensionHandler.beginRequest(with: NSExtensionContext)
                    ├─ reads NSExtensionItem userInfo[SFExtensionMessageKey]
                    ├─ VaultifyCore: open encrypted store from App Group, unwrap Vault Key
                    └─ context.completeRequest(returningItems: [response])
```
- On iOS the native recipient is **the extension's own handler process**, not the containing app. Safari ignores the app-id parameter and always routes to the bundled handler. Handler is **spun up per message and short-lived** — good for stateless queries, wrong place for long pipelines ([Apple: Messaging a Web Extension's Native App](https://developer.apple.com/documentation/safariservices/messaging-a-web-extension-s-native-app), [forums 824924](https://developer.apple.com/forums/thread/824924)).
- `connectNative` (persistent port) exists but on iOS the handler process can still be reaped; design for stateless request/response.
- App ↔ extension data sharing = **App Group** (`group.com.bervion.vaultify`) + shared keychain group — exactly the existing AutoFill pattern ([Apple: Messaging between the app and JavaScript](https://developer.apple.com/documentation/safariservices/messaging-between-the-app-and-javascript-in-a-safari-web-extension)).

**Vaultify unlock bridge (reuse existing plumbing — verified in repo):**
- `VaultifyCore/SharedConfig.swift`: App Group holds the **encrypted SwiftData store + wrapped key bundle**; `keychainAccessGroup = WDNL2F75V7.com.bervion.vaultify.shared` holds the **biometric-gated Vault Key** (`BiometricKeyStore.retrieve(reason:)`, Face ID). The AutoFill extension already unlocks this way — the Safari handler does the same. No Argon2 in the extension path (biometric-wrapped key, not password KDF) → avoids the 64 MiB Argon2 memory spike inside a memory-capped appex.
- Entitlements for the new appex = App Group + `keychain-access-groups` shared group (mirror `VaultifyAutoFill.entitlements`, minus CloudKit initially).
- **Face ID context caveat:** `beginRequest` runs headless. AutoFill precedent shows LAContext works from extension processes, but a web-extension handler has no view controller; the Face ID sheet should still present over Safari (LAContext doesn't need a VC). **Must verify on device** — fallback: require unlock via popup interaction (popup tap → native message → biometric) rather than from content-script-initiated flows.

**Security model (non-negotiable):**
1. **Vault Key and decrypted vault NEVER cross the native→JS bridge.** Handler returns only: (a) match metadata for the active host (item id, title, username, obfuscated CC last-4), (b) on explicit user pick, the specific field values to fill — nothing more.
2. Content scripts run in Safari's **isolated world** — page JS can't call extension APIs — but the page fully controls the DOM: treat every fill as writing into hostile territory.
3. Host/origin binding: background derives the origin from `tabs` API (trusted), never from content-script-reported URL. Match on registrable domain + scheme (https only for fill), same policy as the AutoFill matcher.
4. Fill only on explicit user action (tap in popup/inline UI). Never auto-fill on page load — classic credential-exfiltration vector via invisible fields ([known autofill attacks]). Check field visibility (offsetParent, opacity, size), refuse fields in cross-origin iframes by default (`all_frames: true` + per-frame origin check if iframe fill needed, e.g. Stripe CC iframes — punt to later phase).
5. Registration save prompt reads values the **user typed** only after submit intent — never scrape passively.

---

## 4. 1Password Reference Notes (Q4)

- 1Password ships its iOS Safari extension **inside the main 1Password app** (the standalone "1Password for Safari" App Store listing is the Mac one). Enable in Safari settings; icon in the `aA`/address-bar area opens a popup with unlock (Face ID) ([1P: Get to know 1Password for Safari on iOS](https://support.1password.com/getting-started-safari-ios/)).
- **Inline menu** anchored to the focused field: suggestions for logins, identities, credit cards; arrow-key navigable; "Use Suggested Password" on signup/change-password fields ([1P: save & fill credit cards/addresses](https://support.1password.com/credit-card-address-filling/)).
- **Conflict handling:** when 1Password is the system AutoFill (Credential Provider), the extension **hides its inline credential menu** on iOS to avoid double prompts; identities/CC remain extension-only ([1P community ME-271](https://www.1password.community/1password-at-home-31/me-271-feedback-inline-menu-hidden-in-safari-on-ios-when-system-autofill-is-enabled-24290)). Known bug class: iOS re-prompting to save a login the extension just filled ([1P community](https://www.1password.community/discussions/1password/on-iossafari-how-do-i-stop-1password-suggesting-to-save-passwords-filled-out-by-/169233)).
- Page-type detection = client-side form scoring: `autocomplete` attributes (`cc-number`, `given-name`, `new-password`…), input names/ids/labels/placeholder text, form structure (password+confirm ⇒ signup; single password + user ⇒ login; cc-number pattern ⇒ payment). "Ask before filling" setting for non-credential categories.
- Takeaway for Vaultify: start with **popup-driven fill** (tap icon → pick item → fill), add inline menu later — inline overlay is the hardest, most breakage-prone part of 1Password's stack.

---

## 5. Recommended Architecture

**Targets (3rd appex):**
- `VaultifySafari` — `com.bervion.vaultify.safari`, `product: .appExtension`, iOS 17.3+, iPhone (+iPad later).
- Sources: `VaultifySafari/**` (handler + `VaultifyCore/**` shared, same as AutoFill).
- Web bundle: `VaultifySafari/Resources/` — `manifest.json`, `background.js` (non-persistent page, NOT service worker), `content.js` (+ `fill-engine.js`, `field-classifier.js`), `popup.html/js/css`, `_locales/en`, `_locales/vi`, icons.

**manifest.json (MV3) sketch:**
```json
{
  "manifest_version": 3,
  "default_locale": "en",
  "permissions": ["nativeMessaging", "activeTab", "storage", "scripting", "tabs"],
  "host_permissions": ["https://*/*"],
  "background": { "scripts": ["background.js"], "persistent": false },
  "content_scripts": [{ "matches": ["https://*/*"], "js": ["content.js"], "run_at": "document_idle" }],
  "action": { "default_popup": "popup.html", "default_icon": { "16": "...", "32": "..." } }
}
```

**Responsibility split:**
- **Stays native (Credential Provider):** password/passkey/OTP fill via QuickType, iOS 26.2+ save/strong-password. Untouched.
- **Web extension:** identity fill, credit-card fill, signup detection + generated-password fill, custom-field fill, save prompt (pre-26.2), toolbar popup (vault status, per-site items, generator).
- **Suppression rule (from 1Password):** content script never renders credential inline UI for standard login fields — QuickType owns those. Mirror a shared-defaults flag if needed later.
- **Unlock:** popup "Unlock" → native message → `BiometricKeyStore.retrieve` (Face ID) → handler caches nothing across processes; each fill re-derives from keychain (fast, already how AutoFill works). Optionally mirror an "app unlocked recently" TTL flag in shared defaults for UX (metadata only, never key material).

---

## 6. Tuist / Project.swift Changes (Q5)

High level (mirror `VaultifyAutoFill` block):

```swift
.target(
    name: "VaultifySafari",
    destinations: [.iPhone],
    product: .appExtension,
    bundleId: "com.bervion.vaultify.safari",
    deploymentTargets: .iOS("17.3"),
    infoPlist: .extendingDefault(with: [
        "CFBundleDisplayName": "Loox",   // name shown in Safari's extension list
        "CFBundleShortVersionString": "$(MARKETING_VERSION)",
        "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
        "NSFaceIDUsageDescription": "Loox uses Face ID to unlock your vault.",
        "NSExtension": [
            "NSExtensionPointIdentifier": "com.apple.Safari.web-extension",
            "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).SafariWebExtensionHandler",
        ],
    ]),
    sources: ["VaultifySafari/**/*.swift", "VaultifyCore/**"],
    resources: [ /* see gotcha below */ ],
    entitlements: "VaultifySafari/VaultifySafari.entitlements",  // App Group + shared keychain group
    settings: .settings(base: [
        "CODE_SIGN_STYLE": "Automatic",
        "HEADER_SEARCH_PATHS": "$(SRCROOT)/VaultifyCore/CArgon2",
        "SWIFT_OBJC_BRIDGING_HEADER": "VaultifySafari/VaultifySafari-Bridging-Header.h", // CArgon2 (VaultifyCore compiles into target)
        "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
        "TARGETED_DEVICE_FAMILY": "1",
        "SKIP_INSTALL": "YES",
    ])
),
```
Plus: app target `dependencies: [.target(name: "VaultifySafari", condition: .when([.ios]))]`.

**Gotchas:**
1. **Web resources must keep their directory structure** (`_locales/en/messages.json`, `images/…`). Tuist glob resources flatten processing per file but preserve relative dirs only via **folder reference**: use `.folderReference(path: "VaultifySafari/Resources")` in `resources` so Safari finds `manifest.json` at the expected root and `_locales` intact. Verify post-`tuist generate` that the built `.appex` contains `manifest.json` at bundle top level (iOS flattens `Resources/` into bundle root — Xcode's own template relies on this). ([forums 696316: "make sure your manifest.json file…"](https://developer.apple.com/forums/thread/696316))
2. VaultifyCore compiles into a 3rd target → needs the same bridging header + Argon2 header search path or it won't compile (even if the KDF is never invoked at runtime).
3. `Localizable.xcstrings` + `SharedAssets.xcassets` if handler-side strings/assets needed; **web-layer strings localize via `_locales` (EN+VI mandatory per project convention)** — two localization systems in one target.
4. Signing/CI: new bundle id in portal + App Group + shared keychain group capability; regenerate fastlane match profiles (same runbook as autofill in `docs/deployment-guide.md`). No CloudKit initially → simpler profile.
5. Cross-project appex embedding breaks in Tuist ([tuist#6734](https://github.com/tuist/tuist/issues/6734)) — irrelevant here (single Project.swift) but don't split it out later.
6. Don't add the appex dependency to the macOS slice yet (same `.when([.ios])` trick already used for AutoFill); a macOS Safari extension is a separate target later.

---

## 7. Security & Performance Pitfalls (Q6)

| Pitfall | Mitigation |
|---|---|
| Vault/key exposure to page JS | Only per-item field values cross the bridge, only on user action. No bulk vault, no key material, ever. |
| Hidden-field credential exfiltration | Visibility + focus checks before fill; fill only user-picked item into user-visible fields; https-only. |
| Cross-origin iframe fill (CC widgets) | Default deny; phase-gated explicit support with per-frame origin checks. |
| `<all_urls>` permission scare | Expected for password managers; onboarding screen in-app explaining the grant flow (1P does this). |
| Double save prompt (ext + iOS 26.2 native save) | Version-gate: extension save prompt only when native `SupportsSavePasswordCredentials` path unavailable, or make ext save prompt opt-in. |
| Inline menu vs QuickType conflict | Don't render inline credential UI on iOS (1P precedent). |
| Background worker permanently killed (iOS ≥17.4 bug) | Use non-persistent background **page** (classic scripts), event-driven, stateless. |
| Handler process short-lived / memory cap | Stateless request/response; biometric-wrapped key (no Argon2) keeps peak memory low; no long-running work in `beginRequest`. |
| No `browser.notifications`, no `webRequest` on iOS | Save prompts = in-page overlay from content script; no request interception features planned. |
| PCI-adjacent CC handling | CC number decrypted only at fill moment; never into `browser.storage`; mask in popup (last-4); no logging. |
| `browser.storage.local` is NOT encrypted-at-rest by you | Store nothing sensitive there — UI prefs only. |
| Complete-protection file class | Vault file in App Group is complete-protection; Safari fill while device locked is a non-scenario (Safari unavailable), same constraint as AutoFill today. |

---

## 8. Phased Rollout Suggestion

1. **P1 Skeleton:** Tuist target, manifest, toolbar icon, popup showing locked/unlocked state, native echo message round-trip. Device-verify: manifest discovery, per-site permission flow, Face ID from handler.
2. **P2 Read path:** unlock bridge + popup lists items matching active tab origin (via existing `VaultReader` host matching); copy-to-clipboard.
3. **P3 Fill engine:** content-script field classifier (autocomplete attrs first, heuristics second) + fill-from-popup for identity + credit cards (the two capabilities Credential Provider can't do).
4. **P4 Signup assist:** signup-page detection, generated-password fill (reuse `PasswordGenerator`), save-new-login overlay (gated off when native save available).
5. **P5 Polish:** inline menu (optional, highest breakage risk), iframe CC support, iPad enablement.
6. **P6 macOS:** reuse web bundle in a macOS Safari web extension target (app already has a mac slice).

Each phase ships behind device QA on iOS 17.3 sim floor + current iOS; Safari extension behavior differs per iOS release (memory: iOS 26 search-tab lesson — test on the actual shipping iOS).

---

## Sources

- [Apple — Safari web extensions](https://developer.apple.com/documentation/safariservices/safari-web-extensions)
- [Apple — Messaging a Web Extension's Native App](https://developer.apple.com/documentation/safariservices/messaging-a-web-extension-s-native-app)
- [Apple — Messaging between the app and JavaScript](https://developer.apple.com/documentation/safariservices/messaging-between-the-app-and-javascript-in-a-safari-web-extension)
- [Apple — Assessing browser compatibility](https://developer.apple.com/documentation/safariservices/assessing-your-safari-web-extension-s-browser-compatibility) · [Troubleshooting](https://developer.apple.com/documentation/safariservices/troubleshooting-your-safari-web-extension)
- [Apple Tech Talk — Build and deploy Safari Extensions for iOS](https://developer.apple.com/videos/play/tech-talks/110148/) · [WWDC20 Meet Safari Web Extensions](https://developer.apple.com/videos/play/wwdc2020/10665/) · [WWDC26 Create web extensions for Safari](https://developer.apple.com/videos/play/wwdc2026/216/)
- [Apple forums — SW permanently killed on iOS](https://developer.apple.com/forums/thread/758346) · [IPC patterns](https://developer.apple.com/forums/thread/824924) · [manifest.json not found](https://developer.apple.com/forums/thread/696316) · [permissions prompt](https://developer.apple.com/forums/thread/700744)
- [Evil Martians — converting Chrome extensions to Safari](https://evilmartians.com/chronicles/how-to-quickly-and-weightlessly-convert-chrome-extensions-to-safari)
- [extension.ninja — Safari 15.4 MV3](https://www.extension.ninja/blog/post/apple-safari-manifest-v3-support/)
- 1Password: [Safari on iOS](https://support.1password.com/getting-started-safari-ios/) · [CC & address filling](https://support.1password.com/credit-card-address-filling/) · [iOS AutoFill](https://support.1password.com/ios-autofill/) · [inline menu hidden when system AutoFill on](https://www.1password.community/1password-at-home-31/me-271-feedback-inline-menu-hidden-in-safari-on-ios-when-system-autofill-is-enabled-24290) · [double save prompt](https://www.1password.community/discussions/1password/on-iossafari-how-do-i-stop-1password-suggesting-to-save-passwords-filled-out-by-/169233)
- [MacStories — iOS 15 Safari extensions](https://www.macstories.net/stories/ios-and-ipados-15-the-macstories-review/17/) · [iMore — enabling extensions](https://www.imore.com/how-add-and-enable-extensions-safari-iphone-and-ipad)
- [tuist#6734 — cross-project appex embedding](https://github.com/tuist/tuist/issues/6734)
- Tutorials (lower weight): [Raza P. — iOS Safari Web Extension](https://medium.com/@razapadhani/how-to-build-an-ios-safari-web-extension-268cddfd6d65) · [Marko Simic — Gist](https://medium.com/@simicvm/gist-building-a-safari-web-extension-d1c8de6dc11d) · [bendodson — Browser Note](https://bendodson.com/weblog/2022/03/11/browser-note/)

## Limitations / not covered

- No hands-on prototype: manifest discovery under Tuist folder-reference and Face ID from the headless handler are **assessed from docs, not device-verified**.
- Apple developer doc pages don't render via fetch; API-support specifics cross-checked via 3 independent secondary sources instead of the primary compat table.
- App Store review posture for password-manager web extensions not researched in depth (1P/Bitwarden/Dashlane all shipped ⇒ low risk).

## Open Questions

1. Can `LAContext` present Face ID from the headless `SafariWebExtensionHandler` process (no UI), or must unlock always be popup-initiated? Device test required (P1 gate).
2. Tuist `.folderReference` vs glob: which produces the `.appex` layout Safari accepts for `manifest.json` + `_locales`? Verify at P1.
3. iOS 26.2+ native save + extension save prompt interplay — exact suppression signal available to the content script? (No API to query "is my app the system provider" from JS; may need shared-defaults mirror + native message.)
4. Enable iPad at P1 (app target already declares `.iPad`) or defer with iPhone-only parity to AutoFill?
5. `connectNative` port stability on current iOS — worth using for popup sessions, or stick to pure `sendNativeMessage`?
