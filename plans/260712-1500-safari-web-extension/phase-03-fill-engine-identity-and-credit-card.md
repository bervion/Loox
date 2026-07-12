# Phase 03 — Fill Engine: Field Classifier + Identity + Credit-Card Fill

## Context Links

- Research: `plans/reports/from-research-260712-1453-safari-web-extension-plan-report.md` §1 (identity/CC = web-ext-only value), §3 (fill security), §4 (1P detection heuristics)
- 1Password: [Save and fill credit cards and addresses](https://support.1password.com/credit-card-address-filling/)
- WHATWG autocomplete tokens: https://html.spec.whatwg.org/multipage/form-control-infrastructure.html#autofill
- Prereq: Phase 02 complete

## Overview

- Priority: P1 (this is the reason the extension exists — Credential Provider cannot fill identity/CC, report §1)
- Status: implemented (device QA matrix pending — code complete, `make check` + `make test` green, classifier node tests green)
- Content-script field classifier + fill engine; popup-driven fill: user opens popup on a page → taps an Identity or Card → values fill into classified visible fields. Passwords are NOT filled by this phase (QuickType owns login fields).

## Key Insights

- Classifier tiers (1P model, report §4): (1) `autocomplete` attribute tokens — authoritative; (2) `input type` / `inputmode` (`tel`, `email`); (3) name/id/placeholder/`<label>`/aria-label regexes — must cover EN and VI (e.g. `họ tên|ho ten`, `địa chỉ|dia chi`, `điện thoại|dien thoai`, `số thẻ|so the`); (4) form-level context (a field near `cc-number` classified `text` is likely `cc-name`).
- Field targets map to vault templates (`ItemCategory.swift:62-77`): identity → Full Name/Email/Phone/Address/DOB; card → Cardholder/Card Number/Expiry/Security Code. Name splitting (given/family) derived from Full Name for `given-name`/`family-name` tokens; expiry reformatted per target (`MM/YY`, `MM/YYYY`, split month+year selects).
- Filling frameworks-controlled inputs (React/Vue) requires native setter + synthetic `input`/`change` events (`Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(...)` then `dispatchEvent(new Event('input',{bubbles:true}))`) — plain `.value=` silently reverts.
- Content script runs in Safari's isolated world; page owns the DOM → every fill writes into hostile territory (report §3.2). All safety checks run at fill moment, not classification moment.

## Requirements

- Functional: `classify` cmd from background → content script returns field map summary (counts per category) so popup can enable/disable "Fill" buttons; `fillFields` cmd delivers `[selectorPath → value]` and content script executes with checks; per-field fill report returned (filled/skipped+reason) shown as popup toast.
- Non-functional: classifier pure functions in `field-classifier.js` (no DOM globals in logic core — testable via fixture DOM); fill latency < 300ms after payload arrives; zero values logged.

## Architecture

```
content.js            # message endpoint; orchestrates classify/fill on this frame (top frame only in v1)
field-classifier.js   # pure: (fieldDescriptor[]) → classification[]; tiered heuristics
fill-engine.js        # value writing (native setter + events), visibility/focus checks, fill report
```

**Data flow (fill card):** popup tap "Fill card X" → background → native `getFillPayload {itemId, origin, categories:["card"]}` → handler: Face ID → decrypt ONLY that item's needed fields (CC number decrypted here, at fill moment — report §7 PCI row) → response → background forwards to content script of the SAME tab id it derived origin from (tab-id pinning: payload never goes to a tab whose origin changed since the request — background re-checks `tab.url` origin equality before injecting) → fill-engine writes values → payload object cleared.

**Fill-moment safety checks (each field, hard-fail = skip):**
1. `location.protocol === "https:"` (belt) AND background verified https origin (suspenders).
2. Element visible: `offsetParent !== null`, computed `opacity > 0.1`, rect ≥ 10×10 px, not `visibility:hidden` (report §3.4 — hidden-field exfiltration).
3. Element editable: not `disabled`/`readonly`.
4. Same-origin frame only: v1 fills top frame; `all_frames` stays false in manifest until P5.
5. CC number/CVC additionally: only into `<input>` whose classification came from tier 1-2 evidence, or tier 3 with a Luhn-compatible `maxlength` (13-19) — never into `textarea`/contenteditable.

**Protocol additions:** `getFillPayload` (native, returns values — the ONLY such cmd), `classifyPage` + `fillFields` (background↔content). Native response includes `expiresAt` hint; background holds payload in a local variable only (never `storage`), discards after dispatch or 10s.

## Related Code Files

- Create: `VaultifySafari/Resources/field-classifier.js`, `VaultifySafari/Resources/fill-engine.js`, `VaultifyTests/WebExtensionFillPayloadTests.swift`, `VaultifySafari/Resources/test-fixtures/` (static HTML pages: plain form, React-style, VI-labeled form, hidden-field trap, split expiry) — fixtures excluded from appex resources (dev-only folder, NOT under `Resources/` actually shipped; place at `VaultifySafari/DevFixtures/` instead)
- Modify: `content.js`, `background.js`, `popup.js/html/css`, `SafariMessageRouter.swift`, `WebExtensionReader.swift` (add `fillPayload(itemId:categories:key:)`), `_locales/en|vi`, `manifest.json` (no change expected — verify `all_frames` default false)
- Read: `VaultifyCore/Models/ItemCategory.swift`, `VaultifyCore/Models/DynamicField.swift`, `VaultifyCore/Models/PaymentCard.swift`

## Implementation Steps

1. `WebExtensionReader.fillPayload`: decrypt requested item only; map DynamicFields → canonical keys (`fullName`, `email`, `phone`, `address`, `ccName`, `ccNumber`, `ccExp`, `ccCsc`); derive `givenName`/`familyName`; strip spaces from CC number; unit-test payload contains ONLY requested item's fields.
2. Router: `getFillPayload` requires `itemId` + `origin` (https) + category; reject otherwise (test each rejection).
3. `field-classifier.js`: tier pipeline; emit `{fieldId, category, key, confidence, evidenceTier}`; EN+VI regex tables as data constants.
4. `fill-engine.js`: native-setter write + events; safety checks 1-5; produce fill report.
5. `content.js`: handle `classifyPage`/`fillFields`; assign stable per-load field ids (WeakMap element↔id — never CSS selectors serialized to native).
6. background.js: tab-id pinning + origin re-check + payload lifetime (local var, clear after dispatch/10s timeout).
7. popup: show fill buttons enabled by classify summary; result toast; strings EN+VI.
8. Manual QA matrix on device: fixtures (all 5) + 6 real sites (2 checkout pages with CC form, 2 address forms, 1 VI-language site, 1 React SPA). Record per-site results in this file.
9. `make test` + `make check`.

## Todo List

- [x] fillPayload native path + rejection tests (`WebExtensionFillPayload.swift`, 19 tests in `WebExtensionFillPayloadTests.swift`)
- [x] Classifier tiers with EN+VI evidence tables (`field-classifier.js` + node tests in `DevFixtures/field-classifier-node-tests.mjs`)
- [x] Fill engine with 5 safety checks + fill report (`fill-engine.js`)
- [x] Tab-id pinning + payload lifetime in background (`background.js` `handleFillItem`)
- [x] Popup fill UX + toast, EN+VI (`popup.js/css`, `_locales/en|vi`)
- [x] DevFixtures pages authored (incl. hidden-field trap) — 5 fixtures under `VaultifySafari/DevFixtures/`
- [ ] QA matrix executed on device, results recorded (USER-OWED: real-site fill accuracy, hidden-trap zero-fill, CC iframe deny, React reversion fixture)
- [x] `make test` green (676 tests, 0 failures)

## Implementation Notes (deviations from spec, all deliberate)

- `getFillPayload` is NOT relayed from any runtime message: `background.js` constructs it only inside the popup-gated `fillItem` flow — stronger than gating the raw command.
- Content script re-classifies at fill moment (stateless) instead of caching classifyPage results — a mutated/SPA-navigated page can never receive values into stale elements; WeakMap field ids still used within a page load.
- CC tier-3 maxlength corroboration: 13-19 for `cc-number` (per spec), 3-4 for `cc-csc` (a CVC input never carries a PAN-length maxlength; spec's 13-19 wording was PAN-oriented).
- Identity DOB not in the fill payload (step-1 canonical key list omits it; date-format adaptation deferred).
- Name split is Western order (given = leading tokens, family = last) per WHATWG autocomplete semantics; VI-order sites typically use a single full-name field which gets the unsplit value.
- Identity fills respect the `protected` flag; card fills release template-protected number/CSC at fill moment (the phase's PCI row) — `guard2`/SecretGuard always block both.

## Success Criteria

- Identity + card fill works on ≥5/6 real-site QA matrix entries; hidden-field trap fixture receives ZERO values (test is the trap page); payload rejection tests green; no secret ever written to console/log/storage (grep the JS for `console.` before merge).

## Risk Assessment

| Risk | L×I | Mitigation |
|---|---|---|
| Classifier misfires on exotic markup | High×Med | Tiered evidence + confidence threshold; low confidence → field not offered, never guessed for CC |
| React/Vue value reversion | High×Med | Native setter + synthetic events (step 4); fixture covers it |
| Payload delivered to navigated-away tab | Low×High | Tab-id pin + origin re-check + 10s expiry |
| Split/exotic expiry formats | Med×Low | Format adapters; select-element month/year support |
| VI label detection gaps | Med×Med | VI regex table + dedicated VI fixture + VI real site in QA |

## Security Considerations

- CC number decrypted only inside `fillPayload` at fill moment; single-item scope; https double-check; visibility checks per field; top-frame only; payload never persisted, cleared after dispatch; classifier never sends field VALUES from page to native (descriptors only: attributes, never user-typed content).

## Next Steps

- P4 reuses the classifier's `new-password`/signup signals for signup assist + save prompt.
