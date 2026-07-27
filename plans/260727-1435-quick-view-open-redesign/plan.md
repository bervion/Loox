# Quick View `/open` page redesign

**Status:** UNBLOCKED. Contract decision = **Option A** (additive wire metadata). The four open
questions are answered in [decisions.md](decisions.md) — sharer name yes (with an anonymity
guard), `/open` goes multilingual with a header language picker, the app's Polaris icons get
imported as an inline SVG sprite, and **timers do not change**.
The visual design **has since been retrieved**: see [design-spec.md](design-spec.md), extracted
from `~/Downloads/Loox Password Website Design/Loox Website.dc.html` (`isQuick` block, lines
626–844) and `i18n.js`. It resolves most of `design-pending.md`; what it does NOT cover is
listed at the end of that spec — chiefly that the prototype only draws a Login, so the other
seven categories and the markdown note still need designing.

The spec also adds two items that are **behaviour, not styling**: expiry overlays the QR card
with a "Generate a new code" action rather than routing to the terminal view, and the design
states a 90-second QR life against the ~120s currently deployed.
**Scope:** UI/UX of the browser page served by the `loox-quick-view` Worker at `open.looxpassword.com`.
**Repos:** page = `/Users/bervion/Developer/Projects/frontend/looxpassword`, app = `/Users/bervion/Developer/Projects/mobile/ios/Vaultify`.

---

## 1. The contract gap — read this first

The wire payload the browser decrypts is `{version, fields}` and nothing else
(`Vaultify/Features/Sharing/QuickView/QuickViewPayloadComposer.swift:23-26`, verified).
It carries **no item category and no item title**.

The app has 8 item categories but the wire has only 6 `kind` strings, and two lossy hops
collapse them. Five of the eight categories arrive as nothing but `note` and `custom` fields:

| Category | What actually reaches the browser |
|---|---|
| login | `username`, `password` (concealed), `url` |
| note | one `note` |
| card | 2× `note` + 3× `custom` — no password, no username, no url |
| identity | `note`, `username`, `custom`, `note`, `custom`, `custom` |
| sshKey | 2× `note` (one concealed) |
| recoveryCodes | one concealed `note` — byte-identical to a protected secure note |
| securityQuestions | 4× `note`, alternating concealed |
| custom | `note` plus whatever the owner built |

**A shared payment card is indistinguishable from a secure note on the wire.** No frontend
change can recover information that was never sent. This decides the shape of everything else,
so phase-00 is a decision gate, not an implementation phase.

**Recommendation: Decision A (additive wire change).** See `phase-00-decision-contract-gap.md`
for the full cost/limitation comparison. Everything downstream is written so that phases 01,
02, 04, 06, 07, 08 run either way; only phase-03 and the per-category half of phase-05 depend
on the answer.

---

## 2. The visual design — retrieved

[`design-spec.md`](design-spec.md) carries the tokens, the waiting/expired/approved layouts,
the per-field menu actions and the EN copy, extracted from the prototype. It resolves most of
`design-pending.md`; the `[DESIGN-PENDING]` tags still standing in the phase files are the ones
it genuinely does not answer.

What the prototype does **not** cover, and phase-05 must therefore design in its language:
the seven non-Login categories, the markdown note, dark mode, and the empty state for an
approval that arrives with zero fields — which today is the *default* outcome for six of the
eight categories (phase-02).

Two things in the prototype are behaviour rather than styling and are treated as proposals,
not requirements: the "Generate a new code" action on expiry (phase-04 must verify the Worker
allows minting a session from the page), and its 90-second QR life, which is **rejected** —
see [decisions.md](decisions.md) §4.

---

## 3. Phases

| # | Phase | Depends on | Blocking input |
|---|---|---|---|
| 00 | [Decision: the contract gap](phase-00-decision-contract-gap.md) | — | ✅ decided: **A** |
| 01 | [Correctness and regression guards](phase-01-correctness-guards.md) | — | none, start now |
| 02 | [App-side share correctness](phase-02-app-share-correctness.md) | — | none, required either way |
| 03 | [Wire metadata: category + title + sharer + multiline](phase-03-wire-metadata.md) | 00 | ✅ unblocked |
| 04 | [States, copy, and the expired path](phase-04-states-and-copy.md) | 01 | none |
| 05 | [Field presentation, all 8 categories](phase-05-field-presentation.md) | 01, 03, 04 | ✅ unblocked |
| 06 | [Markdown safe-subset renderer](phase-06-markdown-renderer.md) | 01, 05 | none |
| 07 | [Visual tokens, accessibility, responsive](phase-07-tokens-a11y-responsive.md) | 04, 05, 06 | ✅ [design-spec.md](design-spec.md) |
| 08 | [Localization strings EN + VI](phase-08-localization-strings.md) | 02, 04, 05, 06 | none |
| 09 | Language picker + runtime i18n on `/open` | 04, 08 | none — see [decisions.md](decisions.md) §2 |
| 10 | Polaris icon sprite imported from the app | 05 | none — see [decisions.md](decisions.md) §3 |

Recommended order: **01 → 02 → 00 (decide) → 03 → 04 → 05 → 06 → 07 → 08.**
Phase 01 and 02 are shipping bug fixes and should not wait on the decision or the design.

Supporting documents:
- [`app-parity.md`](app-parity.md) — **the app's detail screen and Motion tokens are the source
  of truth for behaviour and animation**; the prototype is a visual reference only. Also carries
  a correction to the phase-02 severity claim.
- [`design-spec.md`](design-spec.md) — tokens, layouts and EN copy extracted from the prototype.
- [`decisions.md`](decisions.md) — the four settled questions.
- [`design-pending.md`](design-pending.md) — every placeholder awaiting the design file.
- [`out-of-scope.md`](out-of-scope.md) — the QR ban and the other hard exclusions.

---

## 4. Out of scope (hard)

**QR encoding and `drawQr` geometry must not be touched.** `qr-encoder.ts` and
`drawQr` (`open-page-script-render.ts:32-129`) are frozen — the module matrix, the
`modulePx / 3` body radius, the stroked finder ring, and the unconditional ink-on-white fill.
That code was fixed after an outage caused by a filled-finder radius that erased all twelve
finder corner modules. The QR is decorative in the new design; restyle the `.qr-card` wrapper
with CSS only, and never change the canvas backing size from JS. Full detail in
[`out-of-scope.md`](out-of-scope.md).

---

## 5. Acceptance criteria

**Correctness**
- A field value containing `& < > "` displays exactly as it copies (the `esc()` double-escape
  bug at `open-page-script-render.ts:183` and `:211` is gone).
- No `$()` dereference in `open-page-script-render.ts` can throw on a missing element;
  in particular `renderFields` degrades rather than destroying an already-consumed payload.
- A test pins the element-id contract so an HTML-only edit cannot ship a page whose script
  dies on first render.

**States**
- All six states render with distinct, accurate copy: boot, waiting, approved/verifying,
  rendered, terminal-expired, terminal-error (plus `locked`, `closed`, `timeout`).
- The post-reveal 5-minute wipe no longer borrows the pre-scan "Session expired" copy.
- The terminal state offers a working "Get a new code" action.

**Content**
- All 8 categories render legibly; no category shows an empty card.
- `kind` and `valid_until` are both consumed: per-kind presentation exists and the TOTP field
  counts down and goes stale at `valid_until`.
- Markdown notes render as structured prose, built only with `createElement`/`textContent`.

**Security (non-negotiable, each is a release blocker)**
- Zero occurrences of `innerHTML`, `outerHTML`, `insertAdjacentHTML`, `document.write`,
  `DOMParser`, `createContextualFragment` in the composed page script — asserted by test.
- No Trusted Types policy is created. The `loox-quick-view-open` allowlist entry stays unused.
- No decrypted value reaches any attribute, `document.title`, the URL, or history.
- `wipeRendered()` blanks every descendant text node before detaching, so a markdown subtree
  leaves nothing in a detached node.
- `test-open-page-crypto-parity.ts` and `test-quick-view-transcripts.ts` pass **unchanged**.
  If either moves, metadata leaked into a transcript and the change is wrong.

**Quality**
- Page renders correctly at 320px with a concealed multi-line field.
- `prefers-reduced-motion: reduce` is honoured.
- Every text/background pair meets WCAG AA; every button is ≥44px with a visible focus ring.
- Every new user-facing string has an EN and a VI value (phase-08).

---

## 6. Open questions

All five are answered — see [decisions.md](decisions.md).

1. ✅ **Decision A**, additive wire metadata.
2. ✅ Title always sent. The **sharer's name** is sent too, from `Persona.displayName`, but
   suppressed for pseudonymous/anonymous/strict-isolation personas — see decisions §1. That
   guard is a correctness requirement, not a preference.
3. ✅ `/open` is multilingual with a header language picker (phase-09). Field labels stay in
   the owner's language; they are payload data, not chrome.
4. ✅ Category icons come from the app's Polaris set as an inline SVG sprite (phase-10).
5. ⏳ Still open: flag a "partial share" when a category's field set is obviously incomplete.
   Now possible under A. Worth deciding once phase-02 makes empty shares impossible — it may
   become unnecessary.
