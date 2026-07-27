# Phase 01 — Correctness and regression guards

**Depends on:** nothing. Start immediately, independent of the decision and the design file.
**Why first:** these are shipping bugs plus the guard that would have caught the last outage.
No visual change.

---

## Context

- `workers/loox-quick-view/src/open-page-script-render.ts`
- `workers/loox-quick-view/scripts/test-open-page-headers.ts`
- `workers/loox-quick-view/src/open-page.ts` (ids only, no styling yet)

## Requirements

### R1 — Kill the `esc()` double-escape bug

`esc()` produces HTML entities; `textContent` does not parse entities, it renders them literally.

```js
// open-page-script-render.ts:183 (initial render)
valEl.textContent = f.concealed ? '•…' : esc(f.value || '');
// :211 (reveal)
fieldRowNodes[idx].valueEl.textContent = esc(field.value || '');
// :215 (copy) — uses the RAW value
navigator.clipboard.writeText(field.value || '')
```

A password `a&b<c` **displays** as `a&amp;b&lt;c` but **copies** as `a&b<c`. On a password
manager, a user who reads the value off screen and types it by hand gets a different string
than one who clicks Copy.

Delete `esc()` (`:167`) and both call sites. `textContent` is the correct and sufficient sink —
HTML escaping is only ever needed for an `innerHTML` sink, and there is none on this page.
Do not keep `esc()` "for the markdown renderer"; phase-06 builds nodes and will not need it.

### R2 — Null-guard every `$()` dereference in render

`renderFields` is the urgent one. It runs **after** `consumePayload` has flipped the DO to
CONSUMED and deleted the ciphertext, so a throw is unrecoverable:

```js
// :172 — no null check, on the path where the payload is already burned
var container = $('fields-container');
container.textContent = '';
```

A missing id throws → `decryptAndRender` rejects → `popFlow`'s catch
(`open-page-script-flow.ts:149-151`) → `wipeAndClose('error')`. The user sees "Unavailable",
the phone shows the approval succeeded, and the data is gone for good.

Minimum set to guard, each degrading rather than throwing:

| Site | Line | Degrade to |
|---|---|---|
| `renderWaiting` human-code / sas / canvas | `:146,147,154` | skip the node, keep the rest |
| `renderWaiting` drawQr catch body | `:156` | see R3 |
| `renderFields` container | `:172` | **must not throw** — bail to terminal only as a last resort |
| `renderFields` clipboard-warning | `:199` | skip |
| `renderTerminal` title / body | `:242-243` | skip — a throw here freezes the page on the previous view with no message |

### R3 — The drawQr failure handler is itself unguarded

```js
// :153-157
try { drawQr($('qr-canvas'), qr); }
catch (e) { $('qr-canvas').classList.add('hidden'); }   // throws on null
```

The catch exists precisely so a draw failure cannot cost the session, but if the canvas is
renamed or dropped, `drawQr` throws on `canvas.getContext`, the catch throws again, and the
throw escapes `renderWaiting` into bootstrap's catch (`flow.ts:82-84`) → terminal `error`.
That is the exact shape of the prior outage.

```js
var c = $('qr-canvas');
if (c) { try { drawQr(c, qr); } catch (e) { c.classList.add('hidden'); showQrFallback(); } }
```

`showQrFallback()` should surface visible text pointing at the human code rather than silently
hiding the biggest element on screen.

### R4 — `startCountdown`'s missing-element guard swallows `onZero`

```js
// :133-137
function tick() {
  var remainMs = expiresAtMs - Date.now();
  var el = $(elId);
  if (!el) return;                       // returns BEFORE the remainMs <= 0 branch
  if (remainMs <= 0) { …; if (onZero) onZero(); return; }
```

If the element is missing the interval spins forever and `onZero` never fires. For the waiting
state there is no redundant client timer, so expiry would depend entirely on the server EXPIRED
event arriving over `/events`. Move the zero check above the element lookup.

### R5 — Freeze the element-id contract with a test

Today the only content assertion on the rendered page is `no localStorage reference`. Nothing
checks that the ids the script depends on exist, so an HTML-only redesign can ship a page whose
script dies on first render with every check green. This is why the last regression reached
production.

Add to `scripts/test-open-page-headers.ts`, next to the storage greps:

```ts
const REQUIRED_IDS = ['view-boot','view-waiting','view-approved','view-rendered','view-terminal',
  'qr-canvas','human-code','sas-display','waiting-countdown','fields-container',
  'clipboard-warning','render-countdown','terminal-title','terminal-body','close-and-clear'];
for (const id of REQUIRED_IDS) ok(`id ${id} present`, body.includes(`id="${id}"`));
ok('qr target is a canvas', /<canvas[^>]*id="qr-canvas"/.test(body));
```

Phase-04 adds ids to this list as it adds nodes.

### R6 — Assert the HTML-sink ban and the full CSP

The header test checks seven CSP directives but never `trusted-types`, `require-trusted-types-for`
or `img-src`, and nothing greps the script for HTML sinks. Verified: the worker currently
contains **zero** occurrences of `innerHTML`, `createPolicy`, `trustedTypes`, or
`insertAdjacentHTML` — this test locks that in before phase-06 adds a renderer.

```ts
ok('trusted-types policy declared', csp.includes('trusted-types loox-quick-view-open'));
ok("require-trusted-types-for 'script'", csp.includes("require-trusted-types-for 'script'"));
ok("img-src 'self' data:", csp.includes("img-src 'self' data:"));

const script = openPageScript();   // NOTE: the storage greps run against `body`; these must run against the SCRIPT
for (const sink of ['innerHTML','outerHTML','insertAdjacentHTML','document.write',
                    'DOMParser','createContextualFragment','trustedTypes','createPolicy']) {
  ok(`no ${sink} in page script`, !script.includes(sink));
}
ok('no document.title write', !script.includes('document.title'));
```

The existing storage greps run against `body` (the HTML). These new greps must target
`openPageScript()` instead, or they assert nothing.

### R7 — `VIEWER_CSP` is a loaded gun one import away

`security.ts:20-29` exports a CSP with `script-src 'self' 'unsafe-inline'` and
`style-src 'self' 'unsafe-inline'` and **no** trusted-types. Its own comment says it is unused.
`index.ts` correctly uses `openPageHeaders()`. A future edit reaching for the "other" CSP
constant would restore inline script and style and drop Trusted Types in one line.

Delete it, or rename it to something self-evidently wrong to use here
(e.g. `UNUSED_LEGACY_VIEWER_CSP_DO_NOT_USE_ON_OPEN_PAGE`).

### R8 — Copy silently no-ops without a clipboard API

```js
// :214 — no else branch, and the .then() has no .catch()
if (navigator.clipboard && navigator.clipboard.writeText) { … }
```

On a non-secure context, an older browser, or a denied permission, the button looks enabled and
does nothing. Feature-detect at render time: either omit the button in favour of a
select-on-click affordance, or show an explicit failure. Add a `.catch()`.

**Do not** fall back to `document.execCommand` with a hidden `<input value=…>` — that puts the
decrypted value in an attribute and violates the module's hardening rule.

---

## Files to modify

- `workers/loox-quick-view/src/open-page-script-render.ts` — R1, R2, R3, R4, R8
- `workers/loox-quick-view/src/security.ts` — R7
- `workers/loox-quick-view/scripts/test-open-page-headers.ts` — R5, R6

## Tests and validation

```bash
cd /Users/bervion/Developer/Projects/frontend/looxpassword/workers/loox-quick-view
pnpm exec tsx scripts/test-open-page-headers.ts
pnpm exec tsx scripts/test-open-page-crypto-parity.ts   # must pass UNCHANGED
pnpm exec tsx scripts/test-quick-view-transcripts.ts    # must pass UNCHANGED
pnpm exec tsx scripts/test-qr-decode.ts                 # proves the QR is untouched
pnpm exec tsx scripts/test-quick-view-e2e.ts
```

Manual: share a login whose password contains `a&b<c"d`. Confirm the on-screen value and the
clipboard match exactly.

## Risks

- **Deleting `esc()` looks like removing a security control.** It is not — it is a
  no-op-plus-corruption in a `textContent` sink. Note the reasoning in the commit body so a
  future reviewer does not "restore" it.
- **R6's greps are string-based** and would trip on the word appearing in a comment. That is the
  intended strictness; write comments that avoid the literal sink names.
