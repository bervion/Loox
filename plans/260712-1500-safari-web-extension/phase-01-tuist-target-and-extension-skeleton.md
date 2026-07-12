# Phase 01 — Tuist Target + Extension Skeleton + Device Gates G1/G2

## Context Links

- Research: `plans/reports/from-research-260712-1453-safari-web-extension-plan-report.md` §2 (architecture), §5 (target sketch), §6 (Tuist gotchas)
- Apple: [Safari web extensions](https://developer.apple.com/documentation/safariservices/safari-web-extensions), [Messaging a Web Extension's Native App](https://developer.apple.com/documentation/safariservices/messaging-a-web-extension-s-native-app), [forums 696316 — manifest.json not found](https://developer.apple.com/forums/thread/696316), [forums 758346 — SW permanently killed](https://developer.apple.com/forums/thread/758346)
- Mirror target: `Project.swift:162-214` (VaultifyAutoFill appex block)

## Overview

- Priority: P1 (blocks all other phases)
- Status: code complete (260712) — compile-verified, G2 static layout verified; DEVICE gates G1 + full G2 (Safari discovery) still pending, owed by user on real device
- Add 3rd appex target `VaultifySafari` (`com.bervion.vaultify.safari`), MV3 web bundle with non-persistent background page, toolbar icon, popup showing locked/unlocked, native echo round-trip. Exit = both device gates G1 + G2 PASS.

## Key Insights

- Background MUST be a non-persistent background **page** (`"background": {"scripts": [...], "persistent": false}`), NOT an MV3 service worker: iOS ≥17.4 permanently kills the SW 30-45s after install and never wakes it (report §2, forums 758346). Also SW can't be debugged from Safari Develop menu.
- On iOS, `sendNativeMessage` always routes to the appex's own `SafariWebExtensionHandler` (app-id param ignored); handler process is per-message and short-lived → design stateless request/response, never `connectNative` sessions (report §3).
- Web resources must keep directory structure (`manifest.json` at bundle root, `_locales/en/messages.json` nested). Tuist glob resources may flatten; `.folderReference` preserves dirs but iOS flattens the top `Resources/` folder into bundle root — exact behavior is G2's device/simulator verification (report §6.1, forums 696316).
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` project-wide: `beginRequest(with:)` satisfies the ObjC `NSExtensionRequestHandling` protocol — declare handler methods `nonisolated` and hop via `Task { @MainActor in ... }` only where VaultifyCore requires it (VaultReader fns are `@MainActor`, `VaultReader.swift:28`).
- `VaultifyCore/**` compiles into the target → bridging header + `HEADER_SEARCH_PATHS` for CArgon2 mandatory even though Argon2 is never invoked at runtime here (report §6.2).

## Requirements

- Functional: extension appears in Settings → Apps → Safari → Extensions; toolbar icon opens popup; popup displays locked/unlocked placeholder; `{cmd:"echo"}` round-trips content→background→native→back.
- Non-functional: `make check` compiles app + BOTH appexes; no CloudKit entitlement on this appex (simpler match profile, report §6.4); all popup strings localized EN+VI via `_locales`.

## Architecture

```
VaultifySafari/
├── SafariWebExtensionHandler.swift        # NSExtensionRequestHandling; routes SFExtensionMessageKey JSON
├── SafariMessageRouter.swift              # pure nonisolated request→response routing (unit-testable)
├── VaultifySafari-Bridging-Header.h       # CArgon2 (copy of VaultifyAutoFill's)
├── VaultifySafari.entitlements            # App Group + keychain-access-groups ONLY
└── Resources/                             # web bundle (folder reference)
    ├── manifest.json
    ├── background.js                      # non-persistent page; message hub
    ├── content.js                         # placeholder (P3 fills in)
    ├── popup.html / popup.js / popup.css
    ├── _locales/en/messages.json
    ├── _locales/vi/messages.json
    └── images/ (icon-16/32/48/64/96/128.png, exported from brand mark SVG — Polaris/logo lineage, PNG required for manifest icons)
```

**Project.swift target block (append to `targets:`, mirror `Project.swift:162-214`):**

```swift
.target(
    name: "VaultifySafari",
    destinations: [.iPhone],
    product: .appExtension,
    bundleId: "com.bervion.vaultify.safari",
    deploymentTargets: .iOS("17.3"),
    infoPlist: .extendingDefault(with: [
        "CFBundleDisplayName": "Loox",
        "CFBundleShortVersionString": "$(MARKETING_VERSION)",
        "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
        "NSFaceIDUsageDescription": "Loox uses Face ID to unlock your vault.",
        "NSExtension": [
            "NSExtensionPointIdentifier": "com.apple.Safari.web-extension",
            "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).SafariWebExtensionHandler",
        ],
    ]),
    sources: ["VaultifySafari/**/*.swift", "VaultifyCore/**"],
    resources: [
        .folderReference(path: "VaultifySafari/Resources"),   // G2 verifies layout
        "Vaultify/Localizable.xcstrings",                      // handler-side strings (EN+VI)
        "VaultifyCore/SharedAssets.xcassets",
    ],
    entitlements: "VaultifySafari/VaultifySafari.entitlements",
    settings: .settings(base: [
        "CODE_SIGN_STYLE": "Automatic",
        "HEADER_SEARCH_PATHS": "$(SRCROOT)/VaultifyCore/CArgon2",
        "SWIFT_OBJC_BRIDGING_HEADER": "VaultifySafari/VaultifySafari-Bridging-Header.h",
        "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "TARGETED_DEVICE_FAMILY": "1",
        "SKIP_INSTALL": "YES",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks",
    ])
),
```

Plus app target: `dependencies: [..., .target(name: "VaultifySafari", condition: .when([.ios]))]` (`Project.swift:131` pattern — macOS slice must not embed an iOS appex).

**Entitlements (`VaultifySafari.entitlements`)** — App Group `group.com.bervion.vaultify` + `keychain-access-groups: $(AppIdentifierPrefix)com.bervion.vaultify.shared`. NO CloudKit, NO autofill-credential-provider key (contrast `VaultifyAutoFill/VaultifyAutoFill.entitlements`).

**manifest.json sketch (report §5):**

```json
{
  "manifest_version": 3,
  "default_locale": "en",
  "name": "__MSG_extension_name__",
  "description": "__MSG_extension_description__",
  "version": "1.0",
  "permissions": ["nativeMessaging", "activeTab", "storage", "scripting", "tabs"],
  "host_permissions": ["https://*/*"],
  "background": { "scripts": ["background.js"], "persistent": false },
  "content_scripts": [{ "matches": ["https://*/*"], "js": ["content.js"], "run_at": "document_idle" }],
  "action": { "default_popup": "popup.html", "default_icon": { "16": "images/icon-16.png", "32": "images/icon-32.png" } },
  "icons": { "48": "images/icon-48.png", "96": "images/icon-96.png", "128": "images/icon-128.png" }
}
```

**Data flow (echo):** popup.js `runtime.sendMessage({cmd:"echo",payload})` → background.js `runtime.sendNativeMessage(...)` → `SafariWebExtensionHandler.beginRequest` reads `NSExtensionItem.userInfo[SFExtensionMessageKey]` → `SafariMessageRouter.route` → `completeRequest(returningItems:)` → back up the chain. No vault access in this phase.

## Related Code Files

- Modify: `Project.swift` (target block + app dependency)
- Create: everything under `VaultifySafari/` per tree above
- Read for reference: `VaultifyAutoFill/VaultifyAutoFill.entitlements`, `VaultifyAutoFill/VaultifyAutoFill-Bridging-Header.h`, `Project.swift:162-214`

## Implementation Steps

1. Create `VaultifySafari/` sources: handler + router + bridging header + entitlements.
2. Create `Resources/` web bundle: manifest, background.js (message relay only), stub content.js, popup (locked-placeholder UI using `browser.i18n.getMessage`), `_locales/en` + `_locales/vi`, PNG icons exported from the brand mark SVG (16/32/48/64/96/128).
3. Edit `Project.swift`: add target block + app-target dependency.
4. `tuist generate --no-open`; run the CLAUDE.md xcodebuild compile check (workspace, generic iOS Simulator dest, derived data `/tmp/vaultify-dd`).
5. **G2 verification**: inspect built appex via `ls -R /tmp/vaultify-dd/*uild/Products/Debug-iphonesimulator/Vaultify.app/PlugIns/VaultifySafari.appex/` — `manifest.json` must sit at appex bundle ROOT with `_locales/` + `images/` intact. If folder-reference nests a `Resources/` dir on iOS (it should flatten), fix by pointing folder references at each child (`.folderReference(path: "VaultifySafari/Resources/_locales")` + glob the root files) or a copy-files script phase — decide from observed layout, then re-verify.
6. Device run: enable extension in Settings → Safari → Extensions; grant a site; confirm toolbar icon + popup renders localized strings in EN and VI (in-Safari locale follows system).
7. Echo round-trip on device: popup button → native echo → response rendered.
8. **G1 verification (device)**: temporary DEBUG-only popup button "Test unlock" → native `{cmd:"unlockProbe"}` → handler calls `BiometricKeyStore.retrieve(reason:)` (`BiometricKeyStore.swift:54`), returns only `{ok: true/false, error?}` — never key bytes. Verify Face ID sheet presents over Safari from the headless handler when popup-initiated. Record result in this file. Console diagnostics via `Logger(subsystem: "com.bervion.vaultify.safari")` (pattern: `VaultifyAutoFill/UnlockGate.swift:6`).
9. **G1 fallback decision (locked now)**: unlock is ONLY ever popup-initiated (never content-script-initiated) regardless of G1 outcome. If even popup-initiated LAContext cannot present → escalation path = popup deep-links `vaultify://` (scheme exists, `Project.swift:88-91`) telling user to unlock in app is NOT sufficient (key never persists unlocked) → the extension feature is then blocked; stop and re-plan before P2. Do not invent a key-mirroring workaround (violates security invariant).
10. Apple Developer portal: register `com.bervion.vaultify.safari`, enable App Group + Keychain Sharing. Automatic signing for dev; note match profile regen as a P6 release task.
11. Run `make check`; commit on branch `feat/safari-web-extension`.

## Todo List

- [x] Handler + router + bridging header + entitlements
- [x] Web bundle: manifest, background page, popup, `_locales` EN+VI, PNG icons (icons rendered from the brand infinity mark SVG; final art pass pending)
- [x] Project.swift target + dependency; `tuist generate`; compile check passes
- [x] G2 (static half): appex layout verified (manifest at root, `_locales` intact) — see "Implementation notes" below
- [ ] Enable + grant on device; popup renders localized (DEVICE — user)
- [ ] Echo round-trip works (DEVICE — user)
- [ ] G1: popup-initiated Face ID from handler verified on device (DEVICE — user)
- [ ] Portal: bundle id + App Group + Keychain Sharing registered (user)
- [x] `make check` green; results of G1/G2 recorded here

## Implementation notes (260712)

- **Folder-reference gotcha CONFIRMED**: a single `.folderReference(path: "VaultifySafari/Resources")` nests everything under a literal `Resources/` dir inside the `.appex` (manifest NOT at root) and even fails `ValidateEmbeddedBinary` ("Couldn't load Info dictionary" — the top-level `Resources/` dir makes the flat iOS bundle look deep-style). Fix applied per step 5 fallback: root files (`manifest.json`, `background.js`, `content.js`, `popup.*`) as plain resources + `.folderReference` only on `_locales/` and `images/`. Verified built layout: manifest + scripts + popup at appex root, `_locales/en|vi/messages.json` and `images/icon-*.png` intact.
- **`make check` exit-code trap**: the Makefile pipes xcodebuild into `tail -20` without pipefail, so "✓ Compile check passed" prints even on failure — always re-check the log for `commands failed` / `error:` lines.
- Native handler: `nonisolated final class SafariWebExtensionHandler` + pure `SafariMessageRouter` (echo/ping only, payload capped 512 chars, structured errors). No vault/key material crosses native→JS.
- **BLOCKING for P2+**: G1 (Face ID from headless handler, popup-initiated) and G2's device half (Safari actually discovers the extension, per-site permission flow, localized popup) are UNVERIFIED — require the user on a real device before any Phase 2 work starts.

## Success Criteria

- `make check` compiles all three targets. Appex layout correct (G2). Popup opens, localized EN+VI. Echo round-trip < 1s. Face ID presents from handler (G1). No CloudKit entitlement present.
- Status 260712: compile check + static appex layout + no-CloudKit-entitlement DONE. Popup render, echo round-trip, G1 Face ID, and G2 Safari discovery are DEVICE-ONLY and remain BLOCKING for Phase 2+ (user-owed).

## Risk Assessment

| Risk | L×I | Mitigation |
|---|---|---|
| G2 fail: Safari can't find manifest under Tuist packaging | Med×High | Step 5 alternatives (per-child folder refs / script phase); verify before writing any more web code |
| G1 fail: LAContext can't present from headless handler | Low×High | AutoFill precedent says LAContext needs no VC; if fail → STOP gate, re-plan (step 9) |
| MainActor isolation breaks `beginRequest` conformance | Med×Med | `nonisolated` handler methods; router pure nonisolated |
| Background page still killed aggressively | Low×Med | Stateless design; every message re-establishes context |
| Bare word "build" trips local hook | Med×Low | Use `/tmp/vaultify-dd` + `*uild` glob (CLAUDE.md) |

## Security Considerations

- Echo/probe handlers return no vault data. `unlockProbe` is DEBUG-only and removed by P2. Entitlements minimal (no CloudKit). `browser.storage` untouched.

## Next Steps

- P2 (unlock bridge + read path) starts only after G1+G2 both PASS and are recorded here.
