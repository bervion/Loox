# Safari Fill Engine (Phase 3) Security Review — feat/safari-fill-engine

Scope: `git diff main...HEAD` (commit `3fb2098`). READ-ONLY, no code changed.
Focus: fill-authorization model, value-leak surface, cross-origin/iframe/visibility, CC/identity
extraction, classifier safety, concurrency/CI. Prior-review regressions (M1 sender gating, strict
host match) re-verified.

## Verdict

**The fill-authorization model is sound.** No path exists for a page or content script to obtain
identity/card values without a user tapping Fill in the popup. Zero Critical findings. One High
(visibility gauntlet demonstrably bypassable by the branch's own trap fixture), two Medium, four Low.

## Authorization model — verified chain (priority 1)

1. **Page JS cannot message the extension.** Safari has no `externally_connectable`; a web page
   cannot address `runtime.onMessage` or `runtime.sendMessage` of the extension at all.
2. **Content scripts cannot reach native.** Apple documentation is explicit: "Content scripts that
   are injected into web content cannot send messages to the native app extension" — a hijacked
   content-script context cannot invoke `getFillPayload` (or `listItems`) directly via
   `sendNativeMessage`. (Verified against Apple's "Messaging between the app and JavaScript in a
   Safari web extension" doc.)
3. **`getFillPayload` is never relayable.** It is absent from `NATIVE_COMMANDS`
   (`background.js:19`), so any `runtime.sendMessage({cmd:"getFillPayload"})` — from popup OR
   content script — dies at `unknownCommand` (`background.js:183`). The background page constructs
   it exclusively inside `handleFillItem` (`background.js:91-97`), reachable only via `fillItem`.
4. **M1 sender gating holds and is extended.** `POPUP_ONLY_COMMANDS` now covers
   `listItems`, `copyValue`, `fillItem`, `classifyPage` (`background.js:20`); `isPopupSender`
   rejects any sender with `sender.tab` (all content scripts) and requires an extension-internal
   `sender.url` when one is supplied (`background.js:28-34`).
5. **Origin binding.** Origin always derives from trusted `browser.tabs.query`
   (`activeHTTPSTab`, `background.js:48-54`), https-only; never sender-supplied. Tab id + origin
   captured BEFORE the native round trip, re-verified via `browser.tabs.get` AFTER it
   (`background.js:107-109`) — a payload never reaches a tab whose origin changed during
   Face ID. `content.js:100-103` belt-checks `location.protocol === "https:"` and
   `message.origin === location.origin` at delivery.
6. **Native pre-unlock validation.** `getFillPayload` rejects non-https origin, missing itemId,
   non-{identity,card} category BEFORE any key retrieval (`WebExtensionRouter.swift:150-159`) —
   a bad request never triggers Face ID. Stored `item.category` must equal the requested category
   (`WebExtensionFillPayload.swift:35`) — an identity itemId cannot unlock card secrets.
7. **Face ID / session.** Key release goes through `ExtensionSessionStore.retrieve()` →
   `BiometricKeyStore.retrieve` (`SafariMessageRouter.swift:39-48`); within a live session a fill
   is prompt-free, but the popup Fill tap is still mandatory — no autofill on load anywhere.

## Value-leak surface — verified (priority 2)

- Payload = exactly one item, one category. Identity: fullName/givenName/familyName/email/phone/
  address only; card: ccName/ccNumber/ccExpMonth/ccExpYear/ccExp/ccCsc only
  (`WebExtensionFillPayload.swift:44-118`). Fixed key set; no generic field serialization.
- Hard floor `releasableForFill` (`:154-157`): never `.password`/`.totp` kinds, never `guard2`,
  never SecretGuard payloads. PIN is `.number` kind and matches no card label
  (test `testCardPayloadCanonicalKeysAndDigitStripping` asserts "0000" absent). Identity fills
  additionally exclude `protected` fields (`:72`); card number/CSC release template-protected
  values by design (plan's PCI row) — matches the phase file's documented deviation.
- Login/password/TOTP structurally unreachable: `fillableCategories = {identity, card}` and
  category-mismatch → `.forbidden` (tests `testLoginCategoryForbidden`,
  `testRouterResponseCarriesNoUnrequestedSecrets`).
- No `console.*` anywhere in `VaultifySafari/Resources/*.js` (grep-verified); nothing written to
  `browser.storage`; popup renders via `textContent` only; only aggregate `{filled, skipped}`
  counts return to the popup (`background.js:123-130`); `values` nulled after dispatch
  (`background.js:105,131-133`); 10 s delivery cap enforced (`withTimeout`).
- Native handler logs `cmd` only (`SafariWebExtensionHandler.swift:25`); key bytes wrapped in
  `SecureBytes`, transient array zeroed (`WebExtensionRouter.swift:189-193`).

## Findings

### High

**H1. Visibility gauntlet misses off-screen and ancestor-opacity fields — the branch's own trap
fixture defeats it.** `isVisible` (`fill-engine.js:29-39`) checks display/visibility, own
`opacity`, rect ≥ 10×10, and offsetParent — but:
- `position:absolute; left:-9999px` (fixture trap `offscreen_pan`,
  `hidden-field-exfiltration-trap.html:21`): display ok, opacity 1, rect ~150×20, offsetParent
  non-null → **fills**. The fixture's own contract ("every one must stay empty") fails.
- Ancestor `opacity:0`: CSS opacity does not inherit into the child's computed value, so
  `getComputedStyle(el).opacity` is `1` → fills.
- `position:fixed; top:-9999px` passes via the explicit fixed-position allowance (`:38`);
  `transform: translate(-9999px)` and `clip-path: inset(100%)` also pass.

Failure scenario: user taps Fill Identity on a page showing a single visible email field; the page
hides fullName/phone/address inputs off-screen and silently harvests the whole identity (the popup
reports "Filled 4", the user sees one field). Same pattern duplicates PAN/CSC into attacker-scripted
off-screen fields during a card fill.

Fix: (a) document-space coordinate check — reject when
`rect.right + scrollX <= 0 || rect.bottom + scrollY <= 0` (below-the-fold legit fields keep
positive document coords, so this does not break real checkouts); (b) bounded ancestor walk
rejecting any ancestor with computed `opacity <= 0.1` (or use
`el.checkVisibility({checkOpacity:true})` where available — Safari 17.4+, keep the manual walk as
fallback since deployment floor is iOS 17.3). Re-run the trap fixture as the acceptance test —
device QA for it is still an open TODO in the phase file (correctly not marked done).

### Medium

**M1. Consent-origin vs delivery-origin gap: the origin the user was shown is never bound to the
fill.** The popup renders the site chip from `activeTabOrigin` at popup-init
(`popup.js:246-260`) but `fillItem` carries only `{itemId, category}` (`popup.js:119-121`);
`handleFillItem` re-derives the origin from the active tab at TAP time (`background.js:88`).
If the underlying page navigates cross-origin between popup open and the Fill tap (timed
`location=` redirect keeps running under the popup overlay), the payload is delivered to an https
origin the user never saw — the post-native re-check compares against the tap-time origin, and the
content-script belt passes because the new page IS that origin. Identity/card items are global
(no host binding), so nothing on the native side catches it either. Exploit prerequisites are
real but narrow (attacker script on the initially shown page, which could often capture the fill
anyway), so Medium — but the fix is cheap and removes the class: popup sends the origin it
displayed, and `handleFillItem` requires `message.expectedOrigin === tab.origin` (comparing a
sender-supplied value AGAINST the trusted tabs-API value is safe — it can only narrow).

**M2. SecretGuard defense-in-depth on the PAN path is dead code.**
`WebExtensionFillPayload.swift:103-104`:

```swift
let digits = PaymentCard.digitsOnly(cardNumberValue(of: item))
if digits.count >= 8, !SecretGuard.isProtected(digits) {
```

`SecretGuard.isProtected` tests the `"v2g:"` prefix (`SecretGuard.swift:25`) — a digits-only
string can never carry it, so the guard is always false. Today no live leak: sealing always sets
`guard2 = true` (`ProtectFieldSheet.swift:93-99`) and `cardNumberValue` filters `guard2 != true`
(`WebExtensionReader.swift:140`), which `testCardLevel2SealedNumberNotReleased` pins. But the
codebase treats `protected`/`guard2`/SecretGuard as independent everywhere else
(`releasable`, `releasableForFill` check all three), and a future/synced/migrated record carrying
a `v2g:` value with `guard2` unset would release base64-ciphertext-derived digits as `ccNumber`
into a card field (junk fill + a sliver of ciphertext material). The same latent pattern exists
pre-existing in `cardSummary`'s last-4 (`WebExtensionReader.swift:125-131`). Fix: test the RAW
value — `let raw = cardNumberValue(of: item); … !SecretGuard.isProtected(raw)` — matching how
`cardValue`→`releasableForFill` already handles Cardholder/Expiry/CSC.

### Low

**L1. `activeTabOrigin` (and echo/ping/status) accepted from content scripts.** Not in
`POPUP_ONLY_COMMANDS` (`background.js:20,167`): a compromised content-script context in any
background tab can learn the ACTIVE tab's origin (cross-tab browsing disclosure), and can bounce
echo/ping/status off the native handler for no reason. Add `activeTabOrigin` to the popup-only
set and gate the diagnostics too — nothing a content script legitimately needs remains.

**L2. Unused `storage` and `scripting` manifest permissions** (`manifest.json:7`). Nothing in the
JS uses either (grep-verified). Drop both — smaller surface, and "storage" specifically invites
the exact secret-persistence mistake the comments forbid.

**L3. Comment drift: "the fill engine regroups per target"**
(`WebExtensionFillPayload.swift:102-103`) — `fill-engine.js` writes plain digits and never
regroups. Digits-only is the safe universal form; fix the comment, not the code.

**L4. `splitFullName` is Western-order** (`WebExtensionFillPayload.swift:84-92`): "Nguyễn Văn An"
→ given "Nguyễn Văn" / family "An", so a VI site with separate Họ/Tên fields gets them inverted
(Họ=An). Documented as deliberate in the phase file (VI sites typically use one full-name field);
correctness nit only, no security impact. Consider a locale heuristic later.

## Cross-origin / iframe / visibility (priority 3)

- Top-frame only: `window.top !== window` bail (`content.js:16`) + `all_frames` absent from
  manifest (defaults false) — cross-origin iframe fill denied twice. `tabs.sendMessage` without
  `frameId` can only reach frames that HAVE the content script = top frame only.
- Re-classification at fill moment (`content.js:109`, stateless) prevents stale-element delivery;
  type re-checked at fill (`inputTypeAllowed`, `fill-engine.js:45-51`) so a post-classification
  `type=hidden`/`password` mutation is caught. Hidden/password/checkbox/radio/etc. excluded at
  collection too (`content.js:49-52`). No page-load autofill exists anywhere.
- Gap: off-screen / ancestor-opacity — see **H1**.

## CC/identity extraction + classifier (priorities 4-5)

- PAN digits-only with 8-digit floor; CSC 3-4 digits enforced; expiry normalized from MM/YY,
  MM/YYYY, M/YY, dash variants (`expiryComponents`, tests green). Card subfields are label-strict
  ("Cardholder"/"Expiry"/"Security Code") — no positional fallback, PIN (.number) unreachable.
  Address is label-strict so an unrelated multiline note can never fill a street field.
- Host match unregressed: strict exact/dot-boundary matcher (`WebExtensionReader.swift:99-105`),
  no substring clause; identities/cards are global by design (no website field).
- Classifier probes (executed via node, all pass): "Tên đăng nhập" → excluded (not givenName);
  "Account number"/"Số tài khoản"/"OTP"/"Mã thẻ quà tặng" → excluded/null; "Họ"/"Tên" match whole
  tokens only ("phone" does not trip "ho"). CC secrets need tier 1-2 evidence or tier-3 +
  plausible maxlength, never textarea/select (`ccEvidenceStrongEnough`). Shipped node test suite
  (53 assertions) passes. Note (informational): EXCLUDE runs after tier 1, so
  `autocomplete="cc-number"` on a text input named "password" classifies ccNumber — page-declared
  intent per WHATWG; the page reads whatever it receives anyway, not a trust boundary. Minor nit:
  "Tên miền" (domain) classifies as givenName tier 3 — harmless misfill.

## Concurrency / CI (priority 6)

- New Swift is `nonisolated` extension of a `nonisolated enum`; store access wrapped in
  `MainActor.run`; per-message key retrieval with `secureZero`. No over-long expressions; explicit
  imports. `Project.swift` resource globs include the two new JS files (regenerate via tuist).
  Phase file records `make check` + `make test` green (676 tests); 19 fill-payload tests cover the
  rejection matrix. Node classifier tests re-run in this review: pass.

## Prior-review status

| Prior finding | Status |
|---|---|
| H1 session slide TOCTOU | FIXED — update-only slide (`ExtensionSessionStore.swift:86,104`) |
| M1 sender gating | FIXED + extended to `fillItem`/`classifyPage` (`background.js:20,161`) |
| M3 over-broad host match | FIXED — strict `hostMatches` (`WebExtensionReader.swift:99-105`) |

## Recommended actions (priority order)

1. **H1** — document-space off-screen check + ancestor-opacity walk in `isVisible`; make the trap
   fixture pass before device QA sign-off.
2. **M1** — bind popup-displayed origin: `expectedOrigin` equality check in `handleFillItem`.
3. **M2** — `SecretGuard.isProtected(raw)` on the raw PAN value (one-line); mirror in `cardSummary`.
4. **L1/L2** — popup-only-gate `activeTabOrigin` + diagnostics; drop `storage`/`scripting` perms.

## Unresolved questions

1. Device QA matrix (phase TODO, user-owed) is the only remaining gate — the trap fixture must be
   re-run after the H1 fix, since it currently would FAIL on `offscreen_pan`.
2. Should `fillItem` require a fresh (non-session) Face ID for card category specifically? Current
   design (popup tap + session) matches the plan; flagging only as a product-level choice.
