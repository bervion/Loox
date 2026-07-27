# Phase 05 — Field presentation, all 8 categories

**Depends on:** phase-01, phase-04. Category headers depend on phase-03 (decision A).
**Core insight:** the page today ignores `kind` and `valid_until` entirely
(`open-page-script-render.ts:169-196` reads only `label`, `value`, `concealed`). Per-kind
presentation and a live TOTP countdown are available from data **already on the wire**, before
any contract change.

---

## Context

- `workers/loox-quick-view/src/open-page-script-render.ts:169-232`
- `Vaultify/Features/Sharing/QuickView/QuickViewPayloadComposer.swift:143-158` (wire kinds)
- `VaultifyCore/Models/ItemCategory.swift:80-127` (what each category actually sends)

## Two invariants that constrain everything below

### Field order is frozen

`QuickViewFieldManifest.hash(orderedFields:)` runs over the final array and the AAD binds it.
Visually reordering makes the page disagree with the approval sheet the owner just confirmed on
the phone. **Preserve array order absolutely.** Express hierarchy through size, weight and
treatment, never through position.

### The wire kind vocabulary is six strings, not seven

`username | password | url | note | custom | otp-code`. The browser never sees `email`
(collapsed into `username`) or `currentTOTP` (it is `otp-code` on the wire). A default branch is
mandatory — a future app version can add one. `concealed` is `Bool?` and is **omitted when
false**; treat missing as false, never as concealed.

---

## R1 — Per-kind presentation

| Kind | Treatment |
|---|---|
| `otp-code` | Hero tile regardless of position. Large tracked digits, grouped 3+3. Drive a ring or bar from `valid_until` (currently discarded). At `valid_until`, mark stale, dim it, and disable Copy with the message below. Never concealed — the app sets `concealed: nil` for it. |
| `password` | Arrives `concealed: true`. Monospace, dot-masked, Reveal **toggle** plus Copy. Strongest visual weight among the persisted fields. |
| `username` | Single line, Copy only, no Reveal. **This bucket also carries Identity's Email** — label it from `f.label`, never from the kind. |
| `url` | Single line, Copy. See R4 on linking. |
| `note`, single-line, no newline, under ~80 chars | **Plain text row, no markdown.** |
| `note`, multi-line or long | Full-width block row, markdown-rendered (phase-06), collapsed with Show more. |
| `custom` | Plain row, monospace when concealed. Optional: group all-digit 12-19 char values 4-4-4-4 for readability — display-only formatting of an already-revealed value, no security delta. |
| unknown | Fall through to the plain row. |

**Closing the `valid_until` gap is worth calling out.** The composer does real work to mint a
boundary-aware current code and an AEAD-bound `valid_until` specifically so the page can count
down and redact. The page has never used it. New string: **This code expired. Approve again for
a fresh one.**

## R2 — The markdown gate is content-shaped, not kind-shaped

`LooxLinkEnvelope.viewerKind` maps **both** `.text` and `.multiline` to `"note"`. So a one-word
custom text field is `kind: "note"`, identical to a 40-line markdown note.

If the page markdown-renders every `kind === 'note'`:
- a Payment Card's "Cardholder: John Smith" gets markdown-parsed
- every Security Question and Answer gets markdown-parsed
- an SSH private key beginning `-----BEGIN OPENSSH PRIVATE KEY-----` renders its leading dashes
  as a setext heading or horizontal rule, **visually corrupting a secret the user needs verbatim**

Gate:

```js
// Under decision A, prefer the explicit flag.
var isProse = f.multiline === true ||
              (f.kind === 'note' && (/\n/.test(value) || value.length > 120));
// Never markdown a key blob, whatever the flags say.
if (/^(-----BEGIN |ssh-rsa |ssh-ed25519 |ecdsa-sha2-)/.test(value)) isProse = false;
```

The key-blob test is content-based and language-independent, so it holds under decision B too.

## R3 — Per-category presentation, all 8

Under **decision A** the category is known and drives the header plus the refinements below.
Under **decision B** every item gets the neutral `Shared fields` header and only the
kind-and-content rules in R1/R2 apply — the "expect" column then documents what the user sees,
not what the page can name.

| Category | What arrives | Presentation |
|---|---|---|
| **login** | `username`, `password` (concealed), `url` | Reference layout. Username plain, password hero-masked with Reveal toggle, website with Copy. |
| **note** | one `note`, usually multiline, may be concealed | Single full-width prose block, markdown-rendered, collapsed with Show more. If concealed, stays masked until Reveal (phase-06 R4). |
| **card** | `note` Cardholder, `custom` Card Number (concealed), `note` Expiry, `custom` Security Code (concealed), `custom` PIN (concealed) | All plain rows, **no markdown**. Monospace + 4-4-4-4 grouping on the long digit value. Three separate concealed rows, each with its own Reveal. |
| **identity** | `note` Full Name, `username` Email, `custom` Phone, `note` Address, `custom` DOB, `custom` ID Number (concealed) | Plain rows throughout. Address is `.multiline` upstream so it may trip the prose gate — acceptable, it renders as a short block. |
| **sshKey** | `note` Private Key (concealed), `note` Public Key | **Markdown explicitly suppressed** by the key-blob test. Monospace, `overflow-x: auto`, preserve line breaks exactly, no wrapping that could corrupt a copy-paste. Private key stays masked until Reveal. |
| **recoveryCodes** | one concealed `note`, typically one code per line | Monospace, one code per line, masked until Reveal. Optional: per-line copy buttons — **index-addressed only**, never a value in an attribute. |
| **securityQuestions** | 4× `note`, alternating unconcealed question / concealed answer | Plain rows. Under decision A, pair them visually (question as a quieter label above its answer). Under B, leave as flat rows — the alternating-pair heuristic collides with a login carrying a note plus a protected note. |
| **custom** | one `note` plus whatever the owner built | Fully generic. Every row falls through to the kind rules. This is the proof the generic path must be good on its own. |

`[DESIGN-PENDING]` — the visual treatment of each row variant, the hero tile, the category
header, and the question/answer pairing.

## R4 — Linking, copy, and the affordances to refuse

**Do not auto-link `url` values.** An anchor on a page that just displayed the matching password
is a phishing-shaped affordance. If a link is wanted it must be an explicit secondary "Open site"
action with `rel="noopener noreferrer"`, never the value text itself.
`[DESIGN-PENDING]` — whether any link affordance exists at all. Recommend none.

Note also that `target="_blank"` backgrounds the page, which after 2 minutes trips the hidden-tab
autolock and wipes the session out from under the user. Bad UX even ignoring the security angle.

**Per-field Copy only. No "Copy all".** It would push every concealed secret onto the clipboard
in one gesture, which is the opposite of what the `concealed` flag is for.

**Reveal becomes a toggle** with `aria-pressed`. Today `btn.remove()` (`render.ts:212`) destroys
the focused element, dropping keyboard and screen-reader focus to `<body>`, and gives the user no
way to re-conceal. A toggle fixes both. New strings: **Hide**, plus the existing Reveal / Copy /
Copied.

Consider auto-re-masking a revealed password after ~20s. `[DESIGN-PENDING]`.

## R5 — The row DOM contract

Every action control inside `#fields-container` must stay a real `<button>` carrying
`data-act="reveal"|"copy"` and `data-idx="<i>"`. The delegate uses `ev.target.closest('button')`,
so icons nested inside the button are fine. `#fields-container.onclick` is **assigned directly**
— do not attach a second handler.

**`data-idx` must stay a plain integer index.** Never put a value, a label, or a kind into any
`data-*` attribute. Values live only in the `decryptedFields` closure array and are read by
integer index.

`fieldRowNodes[i]` is `{root, valueEl}`; every new row variant must register exactly those two
references or `wipeRendered()` misses nodes.

**Accessible names are the one safe exception.** Six buttons all named "Copy" is unusable. Build
`aria-label` from `f.label` — the hardening rule bans *values* from attributes, and labels are
not values. State this in a code comment so a future reviewer does not "fix" it.

---

## Files to modify

- `workers/loox-quick-view/src/open-page-script-render.ts` — the whole `renderFields` rewrite
- `workers/loox-quick-view/src/open-page.ts` — new row-variant classes
- `workers/loox-quick-view/scripts/test-open-page-headers.ts` — sink greps still pass

## Tests and validation

Build a fixture set covering one payload per category, shaped exactly as the templates above,
and render each. Assert:
- No category renders an empty card.
- An SSH private key value is byte-identical on screen and on the clipboard, with no markdown.
- A value containing `& < > "` matches its clipboard (phase-01 R1 regression).
- `otp-code` counts down and goes stale at `valid_until`.
- No `data-*` attribute anywhere in the rendered DOM contains a field value — assert by walking
  the rendered tree for the fixture's secret substrings.

## Risks

- **The prose gate is a heuristic under decision B.** A one-line note of 130 characters renders
  as a block. Low harm; the key-blob suppression covers the case that actually corrupts data.
- **Per-line copy for recovery codes** is the easiest place to accidentally put a value in an
  attribute. If it cannot be done cleanly with indices, drop it.
- **Rewriting `renderFields` touches the hardened surface.** Keep the module doc's rules verbatim
  and extend them; do not restructure the closure-array model.
