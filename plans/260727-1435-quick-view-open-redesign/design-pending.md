# Design-pending register

**SUPERSEDED IN PART — the design file was retrieved after this register was written.**
See [design-spec.md](design-spec.md) for tokens, the waiting/expired/approved layouts, the
per-field menu actions, and the EN copy. Work through the list below and strike the entries
that spec answers; what it genuinely does not cover is the seven non-Login categories, the
markdown note presentation, dark mode, and the zero-field empty state.

Original note follows.

**The visual design file could not be retrieved.** Nothing in this plan guesses at it.

This file lists every decision that belongs to the design file. Each item is marked
`[DESIGN-PENDING]` at its point of use in the phase files. **Do not resolve any of these by
inference** — leave the placeholder until the file arrives, then work through this list.

---

## What is safe to build before the file arrives

Phases 01, 02, 03, 04 (behaviour and copy), 05 (structure and rules), 06 (renderer), and 08 do
not depend on the visual treatment. They are correctness, security, state, content and
localization work that holds under any design.

Phase 07 is the visual layer and **cannot start** until the file arrives. The token block in
phase-07 R1 is extracted from the *shipped* Loox brand — it is the correct baseline to diff
against, not a proposal for the new design.

---

## Open placeholders

| # | Decision | Phase | Default if the file never arrives |
|---|---|---|---|
| 1 | Layout of the item header: title, category, whether an icon appears, position relative to the badges row | 03 R3 | Title above category, no icon, above `#fields-container` |
| 2 | Treatment of the neutral `Shared fields` header for old app clients. It is a **design state, not an error state**, and must read as deliberate | 03 R5 | Same as the category header, with the category line omitted |
| 3 | Whether `identity` counts as "effectively empty" for the default-selection fallback, given its trio is non-empty with Email alone | 02 R1 | Leave as is — over-selecting personal data by default is the worse failure |
| 4 | Autolock warning: persistent hint line, or a banner appearing at ~90s hidden | 04 R4 | Static hint line |
| 5 | Approved/verifying state: determinate 90s bar, or spinner plus a "taking longer" line after ~10s | 04 R5 | Spinner plus the delayed line |
| 6 | Visual treatment of every row variant: hero TOTP tile, masked password row, plain row, monospace row, full-width note block, question/answer pairing | 05 R3 | Inherit the current `.row` with the phase-07 R5 responsive stacking |
| 7 | Whether any link affordance exists on `url` values | 05 R4 | **None.** An anchor beside a just-revealed password is phishing-shaped |
| 8 | Whether a revealed password auto-re-masks after ~20s | 05 R4 | No auto-re-mask; Reveal is a manual toggle |
| 9 | Markdown block styles | 06 R7 / 07 R7 | Port `.article-body` from the marketing site, scaled down one step |
| 10 | Card number digit grouping (4-4-4-4) — wanted, or noise | 05 R1 | Group it; display-only, no security delta |
| 11 | Per-line copy buttons for recovery codes | 05 R3 | Omit unless it can be done cleanly with integer indices |

---

## Questions to ask the moment the file arrives

These three would each invalidate part of the plan, so raise them first.

1. **Does it specify a webfont or an icon font?**
   Undeliverable as-is. `openPageHeaders()` sets `default-src 'none'` with **no `font-src`**, so
   *all* webfonts are blocked including same-origin. The page is locked to the system stack, and
   icons must be inline SVG or `data:` URIs. Shipping a font needs a CSP header change and its own
   review.

2. **Does it include dark comps?**
   Treat as a separate phase. `color-scheme: light` is a deliberate reversal, not an oversight —
   the sibling `loox-link` viewer ships dark and this page dropped it. A half-built dark mode on a
   page that reveals passwords is worse than none. If dark is genuinely wanted: the glass depth
   model must be replaced wholesale rather than inverted, and `.qr-card` must stay white in both
   themes.

3. **Does it restyle the QR — colours, gradient, logo overlay, module shape?**
   **Refuse it.** See `out-of-scope.md`. Point at the finder-corner outage. Only the `.qr-card`
   wrapper is restyleable.

## Also worth confirming with the user, not the file

- Decision A or B (phase-00) — this shapes the header entirely.
- Whether the item title is opt-out per approval, or always sent.
- Whether `/open` gets a Vietnamese UI (phase-08 section B).
- Whether the page should flag a "partial share" when the field set is obviously incomplete for
  its category. Only possible under decision A, and it needs the category template, which the
  category gives you.
