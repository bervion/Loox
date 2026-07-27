# Phase 07 — Visual tokens, accessibility, responsive

**Depends on:** phase-04, 05, 06.
**BLOCKED on the visual design file.** The token block below is extracted from the *shipped*
Loox brand and is the correct baseline to start from; the design file overrides it. Everything
tagged `[DESIGN-PENDING]` is a placeholder, not a decision.

The accessibility and responsive work (R3–R5) is **not** design-dependent and can proceed.

---

## Context

- `workers/loox-quick-view/src/open-page.ts:31-89` (`OPEN_PAGE_CSS`, ~59 lines, zero tokens)
- `looxpassword/src/app/globals.css:5-22` (the marketing site's token block)
- `workers/loox-quick-view/src/open-page-script-render.ts:32-129` (`drawQr` — **do not touch**)

**Do not plan against `docs/design-guidelines.md` or `docs/design-brief.md`.** Both are stale:
the former describes an "Astryx" system with `var(--color-*)` tokens and `<Heading type="display-1">`
components that do not exist in the shipped code; the latter still cites the retired gradient
`#1544FD→#20BDFD` and mandates a dark mode that was never built. `globals.css` and the shipped
components are the source of truth.

## R1 — Lift a token block into `OPEN_PAGE_CSS`

`OPEN_PAGE_CSS` currently hardcodes ~40 literal colours, 9 radii, 6 shadow recipes and 3 blur
recipes inline in selectors. The redesign adds several new states, a category header, per-kind
field chrome and a markdown block set — each of which would add another 10 literals.

**Do this first, and rewrite the existing 25 rules against the tokens in the same pass**,
otherwise the block is dead weight.

```css
:root {
  color-scheme: light;

  /* brand ramp */
  --loox-pale:#E6F3FF; --loox-sky:#7DD3FC; --loox-blue:#00B2FF;
  --loox-royal:#2979FF; --loox-deep:#0D47FF;
  --accent-strong:#0072E0;   /* accent text on WHITE */
  --accent-text:#0060C4;     /* NEW: accent text on a tint (AA) */
  --accent-tint:rgba(0,178,255,.10);
  --accent-edge:rgba(0,178,255,.22);
  --brand-gradient:linear-gradient(135deg,#00B2FF,#0D47FF);

  /* surface */
  --bg:#F4F7FB;
  --bg-wash:
    radial-gradient(46vw 46vw at -8vw -10vw, rgba(125,211,252,.42), rgba(125,211,252,0) 65%),
    radial-gradient(40vw 40vw at 108vw 10vh, rgba(41,121,255,.22), rgba(41,121,255,0) 65%),
    radial-gradient(44vw 44vw at 40vw 110vh, rgba(0,178,255,.20), rgba(0,178,255,0) 65%);
  --surface-solid:#FFFFFF;
  --surface-glass:rgba(255,255,255,.60);
  --surface-glass-strong:rgba(255,255,255,.94);
  --surface-row:rgba(255,255,255,.78);
  --surface-code:rgba(16,17,20,.92);
  --hairline:rgba(255,255,255,.85);      /* a WHITE border, not a grey one */
  --hairline-ink:rgba(13,71,255,.08);
  --divider:rgba(13,71,255,.16);
  --ink-tint:rgba(13,71,255,.06);

  /* text */
  --ink:#0B1220; --ink-2:#33415C; --ink-3:#3D4C68;
  --txt-2:#51607D;      /* 5.88:1 — the safe secondary */
  --txt-3:#65758F;      /* 4.34:1 — >=16px or >=600 only */
  --txt-faint:#8494AD;  /* 2.87:1 — DECORATIVE ONLY */
  --on-accent:#FFFFFF; --code-on-dark:#9EE4FF;

  /* status */
  --success:#146B33;    /* was #1E7E3E, 4.34:1 */
  --success-tint:rgba(52,199,89,.12); --success-edge:rgba(52,199,89,.35);
  --warning:#8A5200;    /* was #B36A00, 3.66:1 — FAILED AA */
  --warning-tint:rgba(255,159,10,.12); --warning-edge:rgba(255,159,10,.30);
  --danger:#C7142B;     /* NEW — the error state has no colour today */
  --danger-tint:rgba(255,59,48,.10); --danger-edge:rgba(255,59,48,.28);

  /* type */
  --font-sans:-apple-system,BlinkMacSystemFont,'SF Pro Display','SF Pro Text',
              'Helvetica Neue',Helvetica,Arial,sans-serif;
  --font-mono:ui-monospace,SFMono-Regular,Menlo,monospace;
  --fs-h1:clamp(26px,4.6vw,38px); --fs-h1-terminal:clamp(22px,3.6vw,30px);
  --fs-h2:22px; --fs-lede:15.5px; --fs-body:15px; --fs-sm:14px;
  --fs-chip:13.5px; --fs-caption:13px; --fs-micro:12.5px; --fs-eyebrow:12px;
  --fs-code:14.5px; --fs-code-strong:20px;
  --lh-tight:1.1; --lh-body:1.5; --lh-prose:1.65; --lh-longform:1.8;
  --tr-tight:-0.03em; --tr-snug:-0.02em; --tr-eyebrow:0.08em;
  --tr-code:0.14em; --tr-sas:0.4em;

  /* radius */
  --r-xs:8px; --r-sm:12px; --r-md:16px; --r-lg:22px;
  --r-xl:28px; --r-2xl:34px; --r-pill:999px;

  /* elevation — the inset white highlight is MANDATORY, it is what makes glass read as glass */
  --e1:0 12px 34px rgba(13,71,255,.06), inset 0 1px 0 rgba(255,255,255,.90);
  --e2:0 24px 60px rgba(13,71,255,.08), inset 0 1px 0 rgba(255,255,255,.90);
  --e3:0 26px 64px rgba(13,71,255,.12), inset 0 1px 0 rgba(255,255,255,.95);
  --e4:0 34px 84px rgba(13,71,255,.18), inset 0 1px 0 rgba(255,255,255,.95);
  --e-btn:0 10px 24px rgba(13,71,255,.32), inset 0 1px 0 rgba(255,255,255,.35);
  --focus-ring:0 0 0 4px rgba(0,178,255,.15);

  /* glass */
  --glass-lg:blur(28px) saturate(170%);
  --glass-md:blur(26px) saturate(180%);
  --glass-sm:blur(20px) saturate(170%);

  /* spacing */
  --s1:4px; --s2:8px; --s3:12px; --s4:16px;
  --s5:22px; --s6:30px; --s7:40px; --s8:52px;
  --gutter:24px; --w-main:560px; --w-card:540px;

  /* motion */
  --ease-brand:cubic-bezier(.32,.72,0,1);
  --d-press:.14s; --d-fast:.15s; --d-base:.2s; --d-slow:.22s; --d-enter:.45s;
}
```

Two signatures worth preserving deliberately: on this system a card's border is **white at 85%**,
never a grey line, and every shadow is a **blue** tint (`rgba(13,71,255,α)`), never black.
Copying that pair is what makes a new surface read as Loox. Half-pixel type sizes are also
deliberate, not sloppiness.

Rewrite map: `:35-41` → `--bg`/`--bg-wash`/`--ink`/`--gutter`; `:53-54` →
`--surface-solid`/`--r-2xl`/`--hairline`/`--e4`; `:68-71` → `--surface-glass`/`--glass-lg`/`--r-xl`/`--e3`;
`:72-74` → `--surface-row`/`--r-md`/`--hairline-ink`/`--fs-eyebrow`/`--tr-eyebrow`;
`:77-81` → `--r-pill`/`--d-base`/`--d-press` plus a `:focus-visible` rule; `:83-87` → the
corrected `--success` / `--warning`.

**No webfont is loadable** (`default-src 'none'` with no `font-src`), so a design specifying
Inter or an icon font is undeliverable without a header change. Flag this the moment the design
file arrives.

## R2 — Contrast fixes (each is a current AA failure)

| Selector | Now | Ratio on `#F4F7FB` | Fix |
|---|---|---|---|
| `.warning` (`:86`) | `#B36A00` 12.5px/600 | **3.66:1** | `#8A5200` (5.50:1). Darken the ink, not the tint. This is the most safety-relevant string on the page. |
| `.hint` (`:62`) | `#8494AD` 13px | **2.87:1** | `--txt-2` `#51607D` (5.88:1). This carries the primary waiting-state instruction. |
| `.row label` (`:74`) | `#8494AD` 11px | **2.87:1** | `--txt-2`. This identifies which secret you are about to copy. |
| `.badge-once` (`:83`) | `#1E7E3E` | 4.34:1 marginal | `#146B33` (5.68:1) |
| `.kicker` (`:46`) | `#0072E0` on accent tint | 4.04:1 marginal | `--accent-text` `#0060C4` (5.15:1) |

Treat `--txt-faint` as decorative-only from here on.

## R3 — Dark mode: keep `color-scheme: light` pinned for v1

The marketing site has **zero** `prefers-color-scheme` queries in 1508 lines, no theme provider,
and a surface model built entirely from white glass at 55–96% alpha over `#F4F7FB` with blue
shadows — light-only by construction, not by omission.

`color-scheme: light` on `/open` (`:32`) is **deliberate**, not an oversight: the older sibling
viewer at `workers/loox-link/src/viewer.ts` sets `color-scheme: light dark` and ships a real dark
override. The team has done this before and reversed it here.

**A half-built dark mode on a page that reveals passwords is worse than none**, because a
wrong-contrast concealed/revealed distinction is a security-relevant failure. If the design file
arrives with dark comps, treat it as a separate phase and say so. Two hard constraints if it is
ever revisited: the QR canvas must stay ink-on-white regardless of theme (already enforced inside
`drawQr` and out of scope to change — keep `.qr-card` white), and the glass depth model must be
replaced wholesale, not inverted.

Also add `@media (prefers-contrast: more)` and `@media (forced-colors: active)`. Neither exists on
either surface today, and forced-colors will currently flatten the concealed/revealed distinction
to nothing.

## R4 — Motion

There is **no `prefers-reduced-motion` rule anywhere on this page**, making it the only Loox
surface that ignores the preference. `.spinner` spins infinitely and `.state:not(.hidden)` runs a
16px translate on *every* state entry — and the redesign adds more states.

```css
@media (prefers-reduced-motion: reduce) {
  .state:not(.hidden) { animation: none; }
  .spinner { animation: none; border-top-color: var(--loox-deep); opacity: .6; }
  * { transition-duration: 0.01ms !important; }
}
```

The marketing site's own rule kills animations only and lets transitions run, which is the right
call — a 0.2s colour fade is not a vestibular trigger.

Keep the countdown ticking under reduced motion (it is information, not decoration) but drive it
with `textContent` only. If the design introduces a TOTP progress ring, it needs a numeric
fallback here.

## R5 — Responsive: the page breaks at 320px today

**Field row.** Budget at 320px: body padding 24×2 → 272; `.fields-card` padding 22×2 → 228;
`.row` padding 16×2 → 196. Inside that, `.val` is a row-flex holding a `<code>` plus Reveal
(~75px) and Copy (~65px), both `flex: none`. 140px of buttons plus 24px of gaps leaves **~32px**
for a value with `word-break: break-all` — the value renders as a one-character-wide vertical
ribbon. Concealed rows carry both buttons, so the worst case is exactly passwords, PINs and
private keys.

Fix: stack `.val` to a column below ~380px.

**SAS pill.** `.sas b` is 15px monospace with `letter-spacing: 0.4em` and 20px/16px side padding,
but `deriveSas` returns `word word NN` — up to 20 characters from the BIP-39 list. At ~9px glyph
plus 6px tracking that is ~300px of text plus 36px padding inside a 272px content box. The
verification string, the entire anti-MITM affordance, wraps or clips on a phone.

Fix: tracking that wide belongs on the **digit group only**, not on the words. Let the pill wrap.

**Targets and focus.** `button` is `padding: 7px 13px; font-size: 12.5px` → a ~30px target, under
both the 44px iOS guideline and WCAG 2.2 target size. There is **no `:focus-visible` rule anywhere
in the stylesheet** while every button is keyboard-reachable. Add `--focus-ring` and raise targets
to 44px.

Verify the whole page at 320px with a concealed multi-line field.

## R6 — Accessibility beyond contrast

The entire document contains **one** ARIA attribute: `aria-hidden` on the brand SVG.

- **Announce state changes.** `role="status" aria-live="polite"` on `#view-approved` and
  `#view-terminal`; move focus to the newly shown view's heading on entry (`tabindex="-1"` +
  `.focus()`). Without this a screen-reader user is not told the phone approved, is not told the
  fields arrived, and is not told the session expired and wiped. (Structural half in phase-04 R7.)
- **Countdowns are not live regions.** `aria-live="off"`, `role="timer"`, plus one visually-hidden
  polite region updated only at 2:00, 1:00, 0:30, 0:10.
- **Reveal is a toggle with `aria-pressed`** (phase-05 R4), which also stops focus dropping to
  `<body>` when the button is destroyed.
- **Copy needs a polite live region** for "Copied" — the current 1200ms `textContent` swap
  announces nothing.
- **Per-row accessible names.** Six buttons named "Copy" is unusable; build `aria-label` from
  `f.label`. Safe and intentional — labels are not values. Comment it.
- **Replace the bare `<label>`** (`:74`) which has no `for` and no wrapped control, so it is
  invalid and may be skipped entirely. Use `<dl>/<dt>/<dd>`, or a span plus `aria-labelledby` on
  the value.
- **The QR needs a text alternative:** `role="img"` plus an accessible name on the canvas. And
  when `drawQr` fails, show visible text pointing at the human code instead of silently hiding the
  biggest element on screen (phase-01 R3).

## R7 — Markdown block styles

`[DESIGN-PENDING]`. Sensible default: port the marketing site's `.article-body`
(h2/h3/p/ul/ol/code/pre/blockquote) scaled down one step — 16.5px→15px body, 22px→18px h2 — and
reuse `--surface-code` / `--code-on-dark` / `--r-md` for fenced blocks and `--ink-tint` / `--r-xs`
for inline code. Do not invent a new style set.

---

## Files to modify

- `workers/loox-quick-view/src/open-page.ts` — `OPEN_PAGE_CSS` and markup ARIA
- `workers/loox-quick-view/src/open-page-script-render.ts` — ARIA wiring, focus management

## Tests and validation

- `pnpm exec tsx scripts/test-open-page-headers.ts` — the no-inline-style assertion must still
  pass; CSSOM writes are fine, `setAttribute('style', …)` is not.
- Manual matrix: 320 / 375 / 768 / 1440px; reduced motion on; forced-colors on; increased
  contrast on; keyboard-only traversal of the rendered state; VoiceOver through all six states.
- Contrast: re-measure every pair in R2 after the design file lands.
- `pnpm exec tsx scripts/test-qr-decode.ts` — proves the restyle did not disturb the QR.

## Risks

- **The design file may specify a webfont, a dark mode, or a restyled QR.** The first needs a CSP
  change, the second is a separate phase, the third must be refused. Raise all three on arrival.
- **Restyling `.qr-card` is safe; resizing the canvas from JS is not.** `drawQr` computes
  `modulePx` from a fixed 480 budget and writes `canvas.width`/`height` itself. Style with CSS
  only — `#qr-canvas` already uses `width: min(280px,72vw); height: auto`.
