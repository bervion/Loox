# Code Review — Safari Web Extension Phase 4: Signup Assist + Save Prompt

- Branch: `feat/safari-signup-assist` (`9ca3aea`, `94d5e78`), diff `main...HEAD`
- Scope: `WebExtensionRouter.swift` (+160), `WebExtensionSaveGate.swift` (new), `VaultWriter.swift`, `SharedConfig.swift`, `background.js`, `content.js`, `fill-engine.js`, `save-overlay.js` (new), `signup-detector.js` (new), `popup.js/html`, `manifest.json`, `_locales`, `WebExtensionSaveLoginTests.swift` (258 LOC, 17 tests)
- Prior reviews checked for regression: unlock-session (260712-2104), fill-engine (260712-2214)

## Verdict

**Save/generate authorization is sound.** No Critical findings. No path exists for a web page to
write a login or extract a generated/saved password without explicit user action, and no password
touches the page DOM, `browser.storage`, logs, or any response echo. The two High findings are
(1) the OS-version-proxy G4 gate can leave iOS 26.2+ users with NEITHER save prompt (plan-known,
device QA pending) and (2) the save overlay is structurally unusable on classic full-page-navigation
signups (pagehide kills the capture before the user can tap Save).

## Authorization chain — verified (priority 1)

Traced end-to-end; each link confirmed in code:

1. **Page world cannot message the hub.** Only content scripts / popup reach
   `browser.runtime.onMessage`; synthetic page events are rejected by `event.isTrusted` checks at
   both capture points (`save-overlay.js:139,147` submit + click listeners). No keystroke, timer,
   blur, or MutationObserver reads — field values are read exclusively inside the two isTrusted
   handlers (`captureAtIntent`, save-overlay.js:96-121).
2. **Sender gating intact (no regression).** `POPUP_ONLY_COMMANDS` enforced first in the listener
   (background.js:317-319) and now includes `generatePasswordFill`. `saveGate/saveLogin/neverSave`
   accept content senders but derive origin ONLY from `sender.tab.url`
   (`contentSenderOrigin`, background.js:53-66): tab-less senders (popup) → forbidden; sub-frames
   (`frameId !== 0`) → forbidden; non-https → forbidden; belt compares `sender.url` origin to the
   tab's top-level origin. A message-supplied origin is never forwarded — `handleSaveLogin`
   rebuilds the native request with whitelisted keys only (background.js:253-276).
3. **Native re-validation.** `WebExtensionRouter.saveLogin` re-parses origin via `httpsHost`
   (https-with-host, lowercased), bounds password/username ≤512 and title ≤120, and runs the
   never-save + native-save belt BEFORE any unlock (WebExtensionRouter.swift:279-301) — a forged
   request can never even trigger a Face ID prompt. Verified by `failingContext` tests
   (WebExtensionSaveLoginTests.swift:112-149).
4. **Write is unlock-gated.** `unlockedKey` → `ExtensionSessionStore.retrieve()` (warm session,
   sliding ≤15 min, mirrored auto-lock, fail-closed on missing mirror) else Face ID via
   `BiometricKeyStore.retrieve` (SafariMessageRouter.swift:39-48). Same gate as fill. Caveat: see M1.
5. **Origin binding of the saved item.** `createLogin(site: origin, ...)` — the Website field and
   derived title come from the trusted-sender origin, never from page-supplied strings
   (VaultWriter.swift:38-45). AutoFill will only ever serve it back to that host.
6. **Generated password direction.** `generatePassword` is native-only reachable through the
   popup-gated `generatePasswordFill` flow (not in `NATIVE_COMMANDS`, not in `CONTENT_SAVE`);
   requires a popup tap. Background nulls the value after dispatch, re-checks tab origin after the
   native round trip, content script re-runs `LooxSignupDetector.scan` AT FILL MOMENT and
   `fillPasswordAll` re-verifies `type === "password"` + the full `isVisible`/`isEditable` gauntlet
   from the fill-engine review (off-screen park, ancestor opacity — reused, not duplicated).
   Only `{filled, skipped}` counts return to the popup.

**Leak canary — clean.** Password lives in content-script closure only (60 s TTL, cleared on
pagehide/scroll-away/save); overlay is a CLOSED shadow root built with createElement/textContent;
only title/username appear in the overlay, as input `.value` properties (page cannot reach into a
closed shadow root, and Safari's isolated content-script world protects `attachShadow` itself).
No `browser.storage`/localStorage anywhere (grep: comments only). Native handler logs `cmd` only.
`saveLogin` response = `itemId` only — enforced by the JSON canary test
(`testSaveLoginResponseNeverEchoesThePassword`).

## Findings

### Critical

None.

### High

**H1. G4 gate is an OS-version proxy — iOS 26.2+ can end up with NEITHER save prompt.**
`WebExtensionSaveGate.nativeSavePathActive()` (WebExtensionSaveGate.swift:23-27) suppresses the
overlay AND belt-refuses `saveLogin` purely on `isOperatingSystemAtLeast(26.2)`. Two failure
scenarios on 26.2+: (a) user never enabled Vaultify as the AutoFill credential provider → the OS
sheet saves to iCloud Keychain or nothing, and Vaultify's own overlay is suppressed → the user can
NEVER save to Vaultify from Safari; (b) the native sheet may not fire at all for JS-`setNativeValue`
generated passwords (its trigger heuristics are aimed at typed/strong-password flows). Both edges are
exactly what the plan's G4 device QA (user-owed, phase-04 §7) must decide — but note that flipping
the JS overlay back on will NOT be enough: the native `saveLogin` belt returns `forbidden` on the
same predicate (WebExtensionRouter.swift:297-299), so any policy flip must change native too.
Fix direction: at G4, if outcome (a)/(b) observed, gate on provider enablement
(`ASCredentialIdentityStore.shared.state.isEnabled` is callable from the handler process) AND the
version, not version alone. Until G4 is recorded this phase must not ship. The "BOTH prompt" edge
appears impossible (belt + overlay share one predicate); the "NEITHER" edge is live.

**H2. Full-navigation signups can't complete a save — capture dies on pagehide.**
The submit listener does not (and must not) preventDefault, so on a classic form-POST signup the
page navigates immediately; `pagehide` → `dismiss()` (save-overlay.js:151) wipes the captured
values and removes the overlay, usually before the ~2-hop `saveGate` round trip even renders it.
The feature therefore effectively works only on fetch/SPA signups — the inverse of the plan's
acknowledged "SPA-miss" risk, and it silently guts the primary "user submits form → Save" flow of
phase-04 §Data flow. Not a security hole (the conservative wipe is the safe choice), but the core
feature promise fails on a large class of sites. Fix direction (later phase): park the captured
pair in background-page memory keyed by (tabId, origin) with a short TTL and re-offer via the
content script after a SAME-ORIGIN navigation completes — never across origins; note iOS Safari's
non-persistent background page also dies, so this needs explicit design, not a quick patch.
Minimum for v1: document the limitation in the plan and verify at G4 which class of test sites the
QA uses (an SPA-only test would mask this).

### Medium

**M1. `saveLogin` has no rate limit and no user-presence requirement inside a warm session —
inconsistent with the branch's own threat model.** The branch adds a 5/min rate limit to
`generatePassword` explicitly citing "a compromised renderer scripting the extension messaging
surface" (WebExtensionSaveGate.swift:55-59). Under that same adversary, `saveLogin` is strictly
more interesting and completely unthrottled: with a warm `ExtensionSessionStore` window (≤15 min
after any popup unlock), a compromised content-script context on evil.com can, with zero user
interaction, (a) write unlimited junk logins for its own origin (vault pollution; each is
`dirty = true` so it also spams CloudKit sync), and (b) use the `duplicate` error as an
origin-scoped username-existence oracle against the vault (probe username → `duplicate` = the user
has that login for this host). Outside the window each attempt raises a real Face ID sheet →
prompt-bombing/fatigue that can trick the user into seeding the session. All impact is
origin-scoped and inbound-only (nothing is extracted), hence Medium not High. Fix: apply the same
sliding-window limiter to `saveLogin` (e.g. 5/min shared stamps key), and consider requiring a
fresh biometric (bypass `ExtensionSessionStore`) for WRITES as a policy decision — reads got the
session for UX; writes are rare enough to afford Face ID every time.

**M2. Change-password pages create a second login instead of updating — stale-password hazard.**
`captureAtIntent` proceeds for `pageType === "changePassword"` (save-overlay.js:100) and
`saveLogin` only ever calls `createLogin`. On a change-password page there is usually no username
field → `usernameElement` nil → item saved with username `""`. Result: the user's EXISTING login
keeps the OLD password, a new item with empty username holds the new one, AutoFill now serves two
credentials (one stale), and the NEXT password change on that site is refused as `duplicate`
(same host, same `""` username) with no update path. The plan scoped the overlay to "submit of a
NEW login" (phase-04 §Overview). Fix for v1: restrict the SAVE overlay to `pageType === "signup"`
(keep changePassword for generated-password FILL only), or detect the existing-host case and label
it as an update flow in a later phase.

**M3. Detector counts invisible password inputs — honeypot login forms misclassify as signup.**
`scan()` collects `input[type="password"]` with no visibility filter (signup-detector.js:243) and
tier 4 fires on "≥2 password fields in one form". Login forms with a hidden anti-autofill honeypot
password field (a common pattern) classify as `signup` → the popup offers "Use generated password"
on a login page (a tap overwrites the user's typed login password — visible, but confusing) and the
save overlay pops after a plain login submit. No credential leaves the machine, but this is exactly
the "unwanted save on a login page" misclassification priority 5 asks about. Fix: filter
descriptors through the fill-engine's `isVisible` (or a cheap subset: display/visibility/size) in
`scan()` before `detect()` — the pure `detect()` layer can stay attribute-only.

### Low

**L1. Cross-origin-navigation origin race hinges on Safari populating `sender.url`.** If a save
message from dying page A arrives after the tab navigated to B, `sender.tab.url` reports B; the
only defense is the `sender.url` belt (background.js:62-65), which is a no-op when Safari omits
`sender.url`. Add a G4 device check that Safari on iOS populates `sender.url` for content-script
messages; if not, pin the origin at capture time via an extra content-script echo and compare.

**L2. Duplicate check compares untrimmed username.** Router compares `request.username.lowercased()`
raw, but `createLogin` trims before storing (WebExtensionRouter.swift:303-306 vs
VaultWriter.swift:31). `" alice"` passes the duplicate gate then stores as `alice` → true duplicate.
Trim before comparing.

**L3. `allowGenerate` read-modify-write is not atomic across handler processes.** Safari spawns a
handler per message; two concurrent `generatePassword` calls can both read 4 stamps and both append
(6/5). Defense-in-depth only — acceptable, note it in the comment.

**L4. Overlay reverse-clickjack.** The page can layer a `pointer-events: none` decoy at max z-index
over the Save button so a user click lands on Save. Gain is minimal (saves the user's own typed
values under the attacker's own origin) and the plan already defers spoofing/clickjack UX to P6.
No action for v1.

**L5. `neverTapped` is fire-and-forget.** A failed native `neverSave` write is silently dropped and
the overlay returns on the next submit. Acceptable; a retry or status line would polish it.

**L6. Save-overlay palette is hardcoded hex (`#1544fd` etc.).** Design-token approximation is
plan-sanctioned for the shadow-DOM overlay ("design-token-approximated styling") but drifts from
the app's live accent. Fine for v1; note for the P6 design pass.

## Non-regression check (prior reviews)

- Sender gating (unlock-session M1): now present and extended correctly; popup-only set enforced
  before any dispatch. ✅
- Strict host matcher (`hostMatches`, dot-boundary, no `evilgoogle.com` bleed): untouched; reused
  by the duplicate check. ✅
- Fill-auth chain, off-screen/ancestor-opacity visibility, origin re-check after native round trip
  (fill-engine review): `fillPasswordAll` reuses `isVisible`/`isEditable`/`setNativeValue`; the
  generated-password flow mirrors `handleFillItem`'s tab-id pin + post-native origin re-check +
  in-page origin/type re-verification. ✅
- `getFillPayload` still never accepted from any sender; `generatePassword`/`saveLogin` correctly
  kept out of `NATIVE_COMMANDS` passthrough. ✅

## Other checks

- **Concurrency:** router `nonisolated`, store access wrapped in `MainActor.run`, handler process
  per message holds nothing across requests. Session store slide remains update-only (H1 fix from
  unlock-session review intact). No races beyond L3.
- **Stable-Xcode/CI risk:** no long expression chains, no new APIs above iOS 17.3
  (`isOperatingSystemAtLeast` is ancient); `OperatingSystemVersion` literal fine. Type-check risk low.
- **Tests:** 17 focused router tests incl. before-unlock rejection harness (`failingContext` with
  `XCTFail` in `retrieveKey` — nice pattern) and the password-echo canary. Node harness + EN/VI
  fixtures for the pure detector. Locale key parity EN=VI (39/39). Tests not re-run in this review
  (plan records 694/694 green).
- **Plan TODO status:** all phase-04 boxes checked except "G4 dual-device QA" (user-owed) — matches
  code state. H1/H2 should be resolved/recorded at G4 before the phase is called done.

## Recommended actions (priority order)

1. Hold ship on G4 device QA; test BOTH a full-nav signup and an SPA signup (H2), and a 26.2+
   device with the provider disabled (H1). Record outcomes in phase-04.
2. Add the sliding-window rate limit to `saveLogin`; decide whether vault WRITES should bypass the
   warm session and always demand Face ID (M1).
3. Restrict the save overlay to `pageType === "signup"` for v1 (M2).
4. Visibility-filter password descriptors in `scan()` (M3).
5. Trim username before the duplicate compare (L2); G4-verify `sender.url` population (L1).

## Unresolved questions

1. Does the iOS 26.2+ native save sheet actually fire for `setNativeValue`-filled generated
   passwords in Safari? (Decides H1 policy — plan already flags this, G4.)
2. Is `ASCredentialIdentityStore.shared.state` reachable/accurate from the Safari extension handler
   process? (Determines the better G4 gate predicate.)
3. Product call: should extension-initiated vault writes ever ride the no-biometric session window,
   or is per-write Face ID acceptable UX? (M1.)
