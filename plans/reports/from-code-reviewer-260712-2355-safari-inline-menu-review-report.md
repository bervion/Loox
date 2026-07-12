# Code Review — Safari Inline Menu + Iframe CC + iPad (Phase 5)

Branch `feat/safari-inline-menu` · commits e1c8171, 5fbf4b3, 085b7d8 · READ-ONLY.
Scope: `inline-menu.js` (new), `background.js`, `content.js`, `fill-engine.js`,
`field-classifier.js`, `signup-detector.js`, `manifest.json`, `WebExtensionRouter.swift`
(`listItemsSession` + `authorizeAndDeliver`), `ExtensionSessionStore.swift`, `SafariMessageRouter.swift`.

## Verdict

The high-risk goals hold: **no page-readable identity/card value ever leaves the extension**,
**no non-allowlisted/spoofed frame can receive a card value**, and **no credential inline menu
can render** (logins never cross the bridge — structurally, not by UI hiding). Face ID is never
summoned by focus. One real defect: the inline menu can be triggered by a *programmatic* focus,
turning it into a **zero-click existence/count oracle** for cards + identities + warm-session state
(the values themselves stay protected). Fix is one line.

---

## HIGH-1 — Zero-click card/identity existence + warm-session oracle via programmatic focus

`inline-menu.js:337` `onFocusIn` fires on **any** `focusin`, with **no `event.isTrusted` gate**.
A hostile top-frame page can:

1. Inject `<input autocomplete="cc-number">` (tier-1 card) and `<input autocomplete="email">`
   (tier-1 identity) — both pass `eligibleTarget` (`inline-menu.js:111`, not credentialish,
   tier ≤ 2, not suppressed when no visible password is present).
2. Call `input.focus()` programmatically (no user action). `focusin` → `fetchItems()`
   (`:132`) → `inlineItems` → native `listItemsSession`. With a warm session this returns
   metadata; `showMenu` (`:287`) appends `menuHost` to `document.documentElement` (`:328`).
3. Although the shadow root is **closed** and `cachedItems` lives in the isolated content-script
   world (page cannot read either), the **host `<div>` is in the page DOM**. A `MutationObserver`
   on `documentElement` / `document.documentElement.lastElementChild` sees it appear, and
   `getBoundingClientRect()` height (44px/row) reveals the row count.

**What leaks to an arbitrary page, with zero interaction:** vault-is-warm (unlocked) boolean;
"user has ≥1 card" and "user has ≥1 identity" as separate signals (focus a cc field vs an email
field); and approximate counts. **What does NOT leak:** last4, brand, titles, any value — those
are behind the closed shadow + isolated world. So this is a fingerprint/targeting oracle
("this visitor is a Loox user with N cards, currently unlocked → strike now with a card-phish
overlay"), not a data-disclosure. The popup path has no analog because the user explicitly opens it.

Severity HIGH (zero-click, cross-origin, always-on via `all_frames`/every https page), not Critical
(no sensitive value crosses to the page).

**Fix (one line, zero UX cost — a real user focus is always trusted):**
```js
async function onFocusIn(event) {
  if (!event.isTrusted) return;              // ignore scripted focus
  ...
}
```
Defense-in-depth: `listItemsSession` has no native rate limit; caching + no-value-to-page bound
abuse, but a per-tab throttle would harden it. The `isTrusted` gate is the load-bearing fix.

---

## Verified SOUND (explicitly checked)

**Iframe CC allowlist (Priority 2) — sound.**
- Allowlist duplicated `background.js:52` and `fill-engine.js:35`; both = {js.stripe.com,
  checkout.stripe.com, pay.google.com}. **Agree.**
- Both gates enforce https + `port === ""` + lowercased exact hostname in-set
  (`allowlistedCCFrameOrigin:121`, `ccFrameOriginAllowed:44`). No subdomain/lookalike/port bypass
  (node tests assert `js.stripe.com.evil.com`, `sub.js.stripe.com`, `:8443`, `http://` all false).
- Background derives frame origin from **trusted `sender.url`** (`handleCCFrameHello:356`), never
  message-reported. Frame side re-checks own `location.origin` + `message.frameOrigin`
  (`frameSelfCheckFails:166`). Dual-side.
- Card values addressed by **explicit frameId** to registered frames only; identity + generated
  password pinned to **frameId 0** (`deliverFill:174`), never broadcast. `handleFrameFill:190`
  refuses any non-card category. A non-allowlisted subframe has **no listener at all**
  (`content.js:26`).
- **Stale registry after in-frame nav is neutralized**: a frame that navigates off-list keeps its
  frameId in `ccFrameRegistry` (subframe nav does not fire `tabs.onUpdated`), but the re-navigated
  frame fails `frameSelfCheckFails` (origin no longer allowlisted / `frameOrigin` mismatch) and,
  for a truly off-list origin, has no listener. No card value reaches it. Confirmed not exploitable.
- A compromised allowlisted context (e.g. XSS'd Stripe) gets card values only (the extended trust,
  identical to browser autofill) — never identity, never the vault key.

**Credential suppression (Priority 3) — sound (absolute rule structurally enforced).**
- Layer 1 `isCredentialish` (`:77`) refuses type=password/hidden + username/current-password/
  new-password/one-time-code autocomplete before any verdict.
- Layer 2 classifier never emits password/username (`EXCLUDE` regex + `FILLABLE_INPUT_TYPES`
  omits password; `field-classifier.js:39,69`).
- Layer 3 `credentialContextSuppressed` (`:96`) suppresses any scope with a **visible** password
  unless signup/changePassword in the **same** form; adjacent login+signup handled
  (`:104`); honeypot invisible passwords correctly do NOT suppress (`visiblePasswordFieldsIn`
  filters by `isVisible`). Node harness covers all these.
- **Decisive:** `inlineListsData` (`WebExtensionRouter.swift:415`) omits logins entirely and
  `showMenu` only renders card/identity — so even the worst edge (identity menu on a newsletter
  email field) is never a *credential* menu. The absolute rule cannot be violated because logins
  never cross the bridge.

**Authorized-fill reuse (Priority 4) — sound, no regression.**
- `handleInlineFillItem:282` → `contentSenderOrigin` (frameId 0, trusted https) + **`sender.tab.active`
  required** (hidden tab cannot summon Face ID) → shared `authorizeAndDeliver:215`.
- Post-round-trip origin re-check via `browser.tabs.get` (`:232`); single item; category matched
  natively (`getFillPayload:218`); values in locals, nulled in `finally`; no pre-fetch on focus
  (fetchItems is metadata only). getFillPayload authorization model unchanged.

**`listItemsSession` native (Priority 1 native side) — correct.**
`WebExtensionRouter.swift:157` validates https host, serves **only** from `retrieveSessionKey()`
(nil ⇒ `locked`, **never** a prompt — test `testListItemsSession…NeverPrompts` asserts
`unlocks.count == 0`), returns identities+cards metadata only (no logins; test asserts no
`sup3r-secret`/`alice`/full PAN/`me@example.com` in serialized output). SecureBytes + secureZero
scrubbing mirrors getFillPayload.

**Overlay hygiene (Priority 5) — sound.** Closed shadow root; createElement/textContent only, no
innerHTML; never auto-focuses (no focus theft); dismissal complete (scroll off-viewport, resize,
outside pointerdown, Escape, pagehide, ineligible focus); only titles/brand/last4 in the closed
shadow; no console.log / browser.storage. Note: last4/brand/titles live in content-script isolated
memory (`cachedItems`) — unreadable by the page; acceptable.

**Concurrency / stable-Xcode (Priority 6) — no issue.** Background maps mutate on the single JS
event loop. Native uses `MainActor.run` hops as elsewhere; no iOS-26-only API in the diff; iPad
change is destinations + `TARGETED_DEVICE_FAMILY 1,2` only, appex-scoped.

---

## Non-security notes (Low)

- `inline-menu.js:323` `location.href = "vaultify://"` runs inside a `makeRow` click handler — a
  genuine user tap; fine. No auto-navigation.
- Menu height as a count side-channel is inherent to any in-DOM overlay host; the HIGH-1
  `isTrusted` gate removes the *silent* trigger, which is the exploitable part.

## Unresolved questions

1. Confirm Safari fires `focusin` with `isTrusted === false` for scripted `.focus()` (WebKit does
   for programmatic focus) — the fix relies on it. Cheap to verify on-device in G5.
2. Should `listItemsSession` carry a per-tab rate limit as defense-in-depth, or is the
   metadata-cache + no-value-to-page bound deemed sufficient after HIGH-1 is fixed?
