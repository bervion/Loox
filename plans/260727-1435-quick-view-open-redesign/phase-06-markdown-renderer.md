# Phase 06 — Markdown safe-subset renderer

**Depends on:** phase-01, phase-05.
**Deliverable:** a new module `open-page-script-markdown.ts` exporting `MARKDOWN_JS_SOURCE`,
exposing exactly one entry point `renderMarkdownInto(container, text)`.

Keep it out of `open-page-script-render.ts` — that file is the reviewed hardening surface and
should not double in size.

---

## Context

- `workers/loox-quick-view/src/security.ts:59-78` (the CSP, verbatim below)
- `workers/loox-quick-view/src/open-page-script.ts:29-42` (script assembly)
- `workers/loox-quick-view/src/open-page-script-render.ts:5-13` (the hardening rule), `:222-232` (wipe)
- `workers/loox-quick-view/src/open-page-script-flow.ts:148-151` (why a throw here is fatal)

## The exact CSP, verified

```
default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self';
img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'none';
trusted-types loox-quick-view-open; require-trusted-types-for 'script'
```

Plus `Cross-Origin-Embedder-Policy: require-corp`.

- **`script-src 'self'`** — one same-origin file. No library is loadable. Hand-rolled or nothing.
- **`style-src 'self'`** — every markdown style must be a class in `OPEN_PAGE_CSS`. No `style=""`,
  including via `setAttribute('style', …)`. `el.style.prop = …` through CSSOM is fine.
- **No `font-src` at all**, so `default-src 'none'` blocks **all** webfonts including same-origin.
  The page is locked to the system stack. Icons must be inline SVG or `data:` URIs.
- **`'unsafe-inline'` appears nowhere.** It exists only in the unused `VIEWER_CSP` — see
  phase-01 R7.

---

## R1 — The innerHTML ban, and why it is not a style preference

**Banned in this module and in `open-page-script-render.ts`:** `innerHTML`, `outerHTML`,
`insertAdjacentHTML`, `document.write`, `DOMParser.parseFromString`,
`Range.createContextualFragment`.

Three reasons, in severity order:

1. **It throws, and the throw destroys the delivery.** `require-trusted-types-for 'script'`
   makes any raw-string assignment to an HTML sink throw a `TypeError` in Chromium. A throw
   inside `decryptAndRender()` is caught by `popFlow()`'s catch → `wipeAndClose('error')`. At
   that point the payload is **already CONSUMED server-side and deleted** — it cannot be
   re-fetched. Safari does not enforce Trusted Types, so an innerHTML renderer would work
   silently on Safari and hard-crash the render path on Chrome. This is a session-destroying
   bug, not a lint violation. The codebase already learned this lesson twice, with `ctx.roundRect`
   and with `drawQr`.
2. It is the only XSS sink on the page.
3. An escaping bug in a `textContent` renderer is cosmetic; in an HTML-string renderer it is
   script execution.

**Do not create a Trusted Types policy named `loox-quick-view-open` to work around this.** The
allowlist entry is declared but deliberately never used (verified: zero occurrences of
`createPolicy` or `trustedTypes` in the worker). Using it would reintroduce an HTML sink into
the one code path that handles decrypted secrets. Phase-01 R6 asserts this by test.

**The rule that makes the renderer safe is structural, not filter-based:** it never converts a
string into markup. It converts a string into a *choice among fixed tag constants*, and every
character of note content ends up in `textContent`. There is no sanitizer to bypass because
there is nothing to sanitize.

## R2 — The three hardening rules

- **R2a — Note-derived text may appear only in text nodes.** Never in an attribute: no `href`,
  `title`, `alt`, `id`, `class`, `data-*`, `aria-label`, no form-control `value`, no CSS custom
  property.
- **R2b — Every element is `document.createElement` with a literal, constant tag name and a
  literal, constant class.** Nothing about the DOM *shape* may derive from note content beyond
  the block type itself. In particular, **discard a fenced block's info string** — it would
  become an attacker-controlled `class`.
- **R2c — The subtree root stays registered as `valueEl` in `fieldRowNodes`,** and the wipe
  blanks every descendant text node **before** detaching.

The module doc's existing rule is sometimes read as "values never touch the DOM". That is not
what the code does — line 183 already writes values into `textContent`. Read against the code it
guards three things: values never enter **attributes**; the closure array is the single
authoritative copy and the DOM copy is derivative and disposable; and every node that displayed a
value is reachable for the wipe. Markdown breaks only the third, and only because the current
wipe assumes one text node per row.

## R3 — Fix the wipe for arbitrary depth

```js
// open-page-script-render.ts:225-226 — complete today only because a row has
// exactly one value-bearing node.
fieldRowNodes[i].valueEl.textContent = '';
fieldRowNodes[i].root.remove();
```

Setting `textContent = ''` on a parent **detaches** its children rather than clearing them. The
detached subtree still contains the plaintext, and DevTools retains references to detached nodes
— precisely the "a detached node an inspector could still walk" case the module doc says the
design defends against.

```js
function wipeSubtree(el) {
  // Blank each text node IN PLACE first: detaching alone leaves the plaintext
  // alive inside a detached node an inspector still holds a reference to.
  var w = document.createTreeWalker(el, NodeFilter.SHOW_TEXT, null, false), n;
  while ((n = w.nextNode())) n.data = '';
  while (el.firstChild) el.removeChild(el.firstChild);
}
// in wipeRendered():
wipeSubtree(fieldRowNodes[i].valueEl);
fieldRowNodes[i].root.remove();
```

Apply it to plain rows too — it is strictly stronger than today's behaviour.

## R4 — The supported subset

Every row is `createElement('<constant>')` + a constant class + `textContent`.

| Construct | Element | Notes |
|---|---|---|
| ATX heading `#`–`###` | `h3` / `h4` / `h5` | clamp the level; inline-parse the text |
| Paragraph | `p` | inline-parse |
| Bold `**x**` | `strong` | |
| Italic `*x*` / `_x_` | `em` | |
| Inline code | `code.md-code` | |
| Fenced code | `pre.md-pre > code` | raw block text; **discard the info string** |
| Unordered list | `ul > li` | flat only, no nesting |
| Ordered list | `ol > li` | flat only; do not set `start` from content |
| Blockquote `> ` | `blockquote` | children are `p` |
| Thematic break `---` | `hr` | no content at all |
| Link `[t](u)` | **text nodes** | see R5 |
| Image `![a](u)` | **text node**, alt only | see R5 |
| Table | **not supported** | ~80 lines of alignment parsing for a construct that essentially never appears in a password-manager note; the app has dedicated categories for recovery codes and security questions |
| Raw HTML in the note | **text node, verbatim** | `<script>` renders as literal characters |

Inline parsing is a small tokenizer producing `{type, text}` records, then a fixed `switch` maps
each to a tag constant. Heading and list-item text go through the same inline parser, so bold in
a heading works.

**Two guards, worth 4 lines:** `MAX_NOTE_CHARS = 20000` and `MAX_BLOCKS = 1000`. Past either,
fall back to the plain pre-wrap path so a crafted note cannot freeze the tab during the 5-minute
render TTL.

## R5 — Links and images

**Render markdown links as plain text. Do not emit `<a>` at all.**

1. **R2a violation.** `href` is an attribute. Putting note content there puts a decrypted value
   somewhere queryable, serialisable via `outerHTML`, and copyable from DevTools — exactly the
   `data-*` pattern the hardened model was written to eliminate. Every scheme-allowlist
   discussion is downstream of this; the attribute itself is the problem.
2. **Injection.** `javascript:`, `data:text/html`, `vbscript:` and whitespace-obfuscated variants
   (`java\tscript:`) all reach the navigation sink through `href`. CSP does not stop a
   `javascript:` navigation from a user click.
3. **Leak.** A click navigates the tab to a third party while a decrypted payload is on screen.
   `Referrer-Policy: no-referrer` suppresses the Referer header but not the DNS lookup or the
   connection, so the note author's chosen host learns the note was opened, when, and from which
   IP. And backgrounding the tab trips the 2-minute autolock.

**Policy:** `[text](url)` → a text node with `text`, then a separate `span.md-url` text node with
the URL so the user can read and manually copy it. Bare autolinks stay plain text. A link title is
discarded. No `rel`, no `target`, because there is no anchor.

**Images are impossible here by two independent mechanisms** — `img-src 'self' data:` blocks any
remote `src`, and `require-corp` blocks cross-origin subresources regardless. Rendering a broken
`<img>` would also write note-derived text into `src` and `alt`. Drop image syntax: emit the alt
text as a plain text node, discard the URL.

If clickable links are ever genuinely needed, the minimum bar is: `https:` only after `new URL()`
parses and `.protocol === 'https:'`, `rel="noopener noreferrer nofollow"`, `target="_blank"`, an
interstitial confirm, **and** an explicit amendment to the module's hardening doc acknowledging
that `href` now carries decrypted content. A deliberate exception, never a default.

## R6 — Reveal and copy for a long note

The current model does not fit: 8 bullet characters in a single-line `code` element is meaningless
for a 40-line note, and `.val` is a row-direction flex with buttons pinned beside a one-line value.

1. **New row variant** `.row.row-note`, `flex-direction: column`: label on top, actions in a small
   header bar, body below at full width. Gate per phase-05 R2. Everything else keeps the inline row.
2. **Not concealed** → render the markdown immediately. Clamp the body to ~12rem with a CSS
   `max-height` plus a fade, and a **Show more** button that only toggles a class. No value moves.
3. **Concealed** → render **nothing** but a "Hidden" placeholder and a Reveal button. On click,
   build the subtree from `decryptedFields[idx].value` and append it. This is a genuine hardening
   improvement over the current behaviour: for a concealed note the plaintext never enters the DOM
   at all unless the user asks.
4. **Copy copies raw markdown source**, not rendered text — already correct for free, since copy
   reads `field.value` from the closure array and never from the DOM. Do not add a second
   "copy as plain text" button.
5. **Wipe** is unchanged in shape: `valueEl` is the note's container and `wipeSubtree()` handles
   arbitrary depth. Both the render TTL and the hidden autolock already funnel through
   `wipeAndClose` → `wipeRendered`, so a revealed note is covered by both with no new plumbing.
6. **Selection stays enabled** on the rendered body. Users will want to grab one line, and Copy
   already puts the full value on the clipboard.

New strings: **Show more**, **Show less**, **Hidden**.

## R7 — Sizing, and shipping incrementally

| Option | JS | CSS | Risk |
|---|---|---|---|
| A. `pre-wrap` plain text | ~6 | ~10 | none |
| **B. The subset above** | **~160–190** | ~40 | low, contained |
| C. B + tables + nested lists + reference links | ~300–340 | ~70 | medium |

**Recommend B.** A note is the one field type that is routinely long and structured, and the
redesign's whole premise is presentation. Monospace `pre-wrap` in a `word-break: break-all` code
element is exactly what the redesign is fixing. ~170 lines is fair for the only new code with an
injection story, in an isolated module.

**The `renderMarkdownInto` seam is identical either way**, and option A is a 6-line body for the
same function — so ship A first if the redesign needs to be unblocked in one commit, then swap
in B.

`[DESIGN-PENDING]` — the markdown block styles. Porting the marketing site's `.article-body`
scaled down one step is a reasonable default (see phase-07), but the design file decides.

---

## Files to create / modify

- **create** `workers/loox-quick-view/src/open-page-script-markdown.ts`
- `workers/loox-quick-view/src/open-page-script.ts` — concatenate `MARKDOWN_JS_SOURCE` **before**
  `RENDER_JS_SOURCE` in the shared IIFE
- `workers/loox-quick-view/src/open-page-script-render.ts` — R3 wipe, R6 row variant
- `workers/loox-quick-view/src/open-page.ts` — markdown classes in `OPEN_PAGE_CSS`
- `workers/loox-quick-view/scripts/test-open-page-headers.ts` — sink greps cover the new module

## Tests and validation

- Phase-01 R6's sink greps must pass with the new module in the bundle.
- Fixture notes: headings, nested emphasis, a fenced block with an info string, a list, a
  blockquote, `[x](javascript:alert(1))`, `![a](https://evil/x.png)`, raw `<script>alert(1)</script>`,
  a 25000-character note, and a note with 2000 blocks.
  Assert: no `<a>` and no `<img>` in the output; the info string appears in no `class`; the raw
  script tag appears as literal text; the oversized inputs fall back to plain text.
- Assert after `wipeRendered()` that no text node anywhere in the document, attached or detached
  and reachable from the row roots, contains a fixture secret.
- Cross-browser: verify the render path in Chrome specifically, since only Chromium enforces
  Trusted Types.

## Risks

- **A parser bug throws and burns a consumed payload.** Wrap `renderMarkdownInto` in a try/catch
  that falls back to the plain-text path — never let it reach `popFlow`'s catch. This mirrors the
  existing `drawQr` guard and is mandatory.
- **Scope creep into tables and nested lists.** Both are YAGNI here. Say no.
