# App parity — the detail screen and motion are the source of truth

The prototype is a **visual** reference. Where it disagrees with the app on behaviour or
motion, the app wins. This file records the app's actual rules so phase-04/05/06/07 can
follow them instead of the mock.

---

## Correction: sharing is NOT broken for six categories

An earlier note in this plan said six of eight categories seal `fields: []` and that
"supports all item types" was false at the source. **That was overstated.**

`QuickViewApprovalFieldsSection.swift:48-60` builds `fieldTogglesCard` from
`LooxLinkEnvelope.shareableFields(of: item)` and renders a toggle row for **every** shareable
field, whatever the category. A payment card is fully shareable — the owner just has to tick
the rows.

What is actually wrong is narrower:

1. **Bad defaults.** `defaultSelectedFieldIDs` (`LooxLinkEnvelope.swift:44-51`) pre-ticks only
   `.username`, `.email`, `.url`, `.password` — 4 of the 12 `FieldKind` cases. So for card,
   note, sshKey, recoveryCodes and securityQuestions the sheet opens with **nothing ticked**
   and the owner must notice and act. That is a poor default, not a broken feature.
2. **No empty guard.** The "Approve with Face ID" button
   (`QuickViewApprovalSheet.swift:87-92`) carries no `.disabled`. Approving with zero ticked
   fields seals an empty payload, renders an empty card in the browser, and burns a rolling
   quota approval (§3.2).

Phase-02 is therefore: give each category a sensible default selection, and refuse to approve
an empty one. It is a UX fix, not a rescue.

---

## The detail screen is the presentation model

`ItemDetailScreen.swift` composes: a header — `FaviconView(urlString:category:size:56)`, the
item title, then `item.category.title` as a subhead (`:447-453`) — then tags (`:468`), then a
flat list of `DetailFieldRow(field:category:readOnly:)` (`:499-506`).

That is the same shape the design draws: avatar, title, subtitle, rows. So the web card should
mirror it, and the metadata phase-03 adds (category + title) is exactly what the header needs.

### `DetailFieldRow` rules the web must copy

| Rule | Source | Consequence for the page |
|---|---|---|
| Tap anywhere on the row copies | `DetailFieldRow.swift:4`, `:105` | Matches the design's "Tap any field to copy it" |
| **Notes opt out of tap-to-copy** — "a long note is for READING (and its links)" | `:63` | The markdown note must NOT be a copy target. Phase-06 must not wire the note row to copy, and the design's blanket tap-to-copy does not apply to it |
| Copy feedback is a **row flash**: background goes `VaultColors.copyFlash`, the value turns transparent and is replaced in place, keeping layout | `:102-103`, `:117-128` | The design's green "Copied" pill beside the value is a different idiom. Use the app's flash |
| **No standalone copy glyph** — the row is the affordance | `:190` | Keep the design's "…" menu for the *extra* actions (open site, copy pair), but do not add a copy button; copy stays the row tap |
| Card numbers get grouped formatting, a brand badge, and copy digits-only | `:145-154`, `:10` | Phase-05's card layout must format the number and copy without spaces |
| Reveal is per-row state via `GlyphResolveText(isRevealed:)` | `:25`, `:150-171` | Conceal/reveal is per field, not a page-level toggle |
| TOTP, url, multiline, card-number each have their own branch | `:135-147` | The page needs the same per-kind branching, not one generic row |

---

## Motion — use the app's tokens, not the prototype's

`Vaultify/DesignSystem/Tokens/Motion.swift`:

| Token | Value |
|---|---|
| `fast` | 0.14s |
| `base` | 0.20s |
| `medium` | 0.26s |
| `slow` | 0.32s |
| `standard` | `timingCurve(0.32, 0.72, 0, 1)` at `base` |
| `spring` | `spring(response: 0.34, dampingFraction: 0.86)` |
| `pressScale` | 0.97 |

The prototype uses the **same easing curve** — `cubic-bezier(0.32, 0.72, 0, 1)` — which is
reassuring, but runs it at **0.45–0.5s** and presses to **0.96**. Both are wrong against the
app. Map as:

- Entry / view transitions → `0.32s` (`slow`), curve `cubic-bezier(0.32,0.72,0,1)`
- Row and control transitions → `0.20s` (`base`), same curve
- Copy flash and micro-feedback → `0.14s` (`fast`)
- Press → `transform: scale(0.97)`
- Selection / spring-like moves → approximate `spring(0.34, 0.86)` with
  `linear(...)` or a tuned cubic-bezier; do not use a longer duration to fake bounce
- The prototype's `looxRise` stagger of 0.06s is fine to keep; it is a delay, not a duration

`Animation.vault(_:reduceMotion:)` collapses motion to **instant**, not merely shorter. The CSS
must do the same: under `prefers-reduced-motion: reduce`, set durations to `0s` rather than
scaling them down, and drop the `qvBubbleB` float and the breathing/spinner loops entirely.

Ship these as custom properties in `OPEN_PAGE_CSS` (`--motion-fast/base/medium/slow`,
`--motion-standard`, `--press-scale`) so the page stops hardcoding durations inline, and so a
future divergence from the app is a one-line diff rather than a hunt.
