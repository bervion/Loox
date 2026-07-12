---
name: safari-web-extension-review-patterns
description: Review patterns for Vaultify's Safari web extension (sender gating, save/fill auth, JS overlay hygiene, version-proxy gates)
metadata:
  type: project
---

# Safari web extension review patterns (plan 260712-1500)

Trust chain to re-verify on every extension diff (reports 2104/2214/2312):
- Listener order in `background.js`: `POPUP_ONLY_COMMANDS` rejection FIRST; content-reachable cmds derive origin ONLY via `contentSenderOrigin` (sender.tab.url + frameId 0 + sender.url belt). Message-supplied origins must never be forwarded; native requests rebuilt with whitelisted keys.
- Native router re-validates https host and runs ALL shape/policy checks BEFORE unlock, so forged requests never raise Face ID. Test pattern: `failingContext` whose `retrieveKey` calls `XCTFail`.
- `ExtensionSessionStore` warm window (≤15 min, no biometric) substitutes for Face ID on EVERY router cmd — new WRITE cmds inherit silent-no-presence execution. Flag rate limits + presence policy for writes (2312 M1: saveLogin unthrottled + `duplicate` error = origin-scoped username oracle).
- Fill paths must reuse `isVisible`/`isEditable`/`setNativeValue` gauntlet (off-screen park, ancestor opacity) and re-scan the page AT FILL MOMENT; only counts return to popup; canary test that responses never echo secrets.

Bug classes found here worth re-checking elsewhere:
- **Version-proxy capability gate**: `isOperatingSystemAtLeast(26.2)` used as proxy for "native save sheet owns UX" → NEITHER-prompts edge when provider disabled or sheet doesn't fire for JS-set values. Prefer capability checks (ASCredentialIdentityStore state) over OS version.
- **pagehide-kills-capture**: memory-only submit capture + full-nav form POST = overlay never usable on classic signups; conservative wipe is safe but guts the feature. Check which nav class QA fixtures cover.
- **Detector counts invisible inputs**: honeypot hidden password fields flip login→signup (tier by field count needs visibility filter in DOM scan; pure detect() stays attribute-only).
- **Untrimmed-vs-trimmed dup check**: compare uses raw request value, store trims → dup bypass.
- **sender.url belt is a no-op if Safari omits sender.url** — cross-origin nav race must be device-verified.

Overlay hygiene bar (passed in 2312): closed shadow root, createElement/textContent only, secrets never in DOM (only .value property for editables), isTrusted-only capture (no keystroke/timer), 60s TTL, no browser.storage, handler logs cmd only.

Phase-05 inline menu + iframe CC (report 2355):
- **Programmatic-focus oracle (bug class)**: an auto-on-focus surface (inline menu) that reacts to `focusin` WITHOUT an `event.isTrusted` gate = zero-click oracle. Even with closed shadow + isolated-world (values unreadable by page), appending a menu-HOST div to the page DOM leaks existence + count (row height) + warm-session state via MutationObserver. Fix = `if (!event.isTrusted) return` — real user focus is always trusted, zero UX cost. Check any new focus/hover/scroll-triggered overlay for this.
- `listItemsSession` (session-only, NEVER prompts; nil session ⇒ `locked`) verified correct: identities+cards metadata only, logins omitted at `inlineListsData` (structural, not UI-hidden) — the "no credential inline menu" rule is enforced because logins never cross the bridge.
- iframe CC allowlist SOUND pattern to re-verify: dup constant background↔fill-engine must agree; both gates = https + `port===""` + lowercased exact host in-set; background derives frame origin from trusted `sender.url` not message; dual-side self-check (`frameSelfCheckFails`); card→registered frameIds, identity/genpw→frameId 0 only; non-allowlisted subframe has NO listener; stale registry after in-frame nav neutralized by self-check + no-listener (subframe nav does NOT fire tabs.onUpdated — rely on the frame gate, not registry invalidation).

Related: [[approval-transport-review-patterns]], [[vaultify-concurrency-audit-review-patterns]]
