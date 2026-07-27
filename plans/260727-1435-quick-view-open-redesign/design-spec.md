# Quick View /open — design spec (extracted from source)

Source: `~/Downloads/Loox Password Website Design/Loox Website.dc.html`, the `isQuick`
block, lines 626–844. Copy from `i18n.js`, the `qv` object. This supersedes the
placeholders in `design-pending.md` for everything listed below; anything not listed
here is still unspecified.

The design is an interactive prototype with its own state names: `wait` → `unlock` →
`ok`, plus `expired`. They map onto the page's existing views as noted.

## Tokens

| Role | Value |
|---|---|
| Page background | `#F4F7FB` + three radial accent washes, `background-attachment: fixed` |
| Text primary | `#0B1220` |
| Text secondary | `#51607D` |
| Text tertiary / labels | `#8494AD` |
| Accent ramp | `#00B2FF` → `#0D47FF` (135°) |
| Accent text on light | `#0072E0` |
| Success | fill `rgba(52,199,89,0.12)`, border `rgba(52,199,89,0.35)`, text `#1E7E3E` |
| Warning | fill `rgba(255,159,10,0.18)`, border `rgba(214,141,19,0.35)`, stroke `#B36A00` |
| Glass surface | `rgba(255,255,255,0.6)` + `blur(28px) saturate(170–190%)`, border `rgba(255,255,255,0.85–0.92)` |
| Card shadow | `0 26px 64px rgba(13,71,255,0.12)`, inset `0 1px 0 rgba(255,255,255,0.95)` |
| QR card shadow | `0 34px 84px rgba(13,71,255,0.18)` |
| Radii | QR card 34, field card 28, menu 20, row/menu-item 14, avatar 13, pill 999 |
| Mono | `ui-monospace, SFMono-Regular, Menlo, monospace` |
| Motion | `looxRise 0.45–0.5s cubic-bezier(0.32,0.72,0,1)`, stagger 0.06s; press `scale(0.96)`; hover lift `translateY(-1px)` |

Type scale: h1 `clamp(30px,4.2vw,46px)/700/-0.03em`; sub `16.5px/1.65`; field label
`11px/700/0.07em uppercase`; field value `mono 14.5px/600`; SAS `mono 17px/700/0.24em`
with the accent gradient as `background-clip: text`.

## Waiting state (maps to `view-waiting`)

Two-column on desktop (`data-qv-grid`), stacked on mobile.

**Left — QR art.** White card, radius 34, padding 18, the QR canvas inside. A countdown
ring sits over the card corner: a circle with a clock glyph and the remaining time. A
"Verify code" bubble floats at `bottom:-19px`, centred: uppercase 9.5px label plus the
4-digit SAS in gradient mono. The bubble has a slow `qvBubbleB 7s` float.

**Right — copy.** Kicker pill "Quick View" → h1 → sub → a numbered 1-2-3 step list with a
vertical rail connecting the markers → a status pill containing a small spinner canvas
and the live status text.

Mobile swaps the step list for an "Open in Loox" primary button plus a note that another
device can scan instead.

## Expired state — NEW BEHAVIOUR, not just styling

The design does **not** route expiry to the terminal view. It overlays the QR card
itself: `position:absolute; inset:0`, glass blur, a 52px circular warning badge with a
clock glyph, title, body, and a primary **"Generate a new code"** button.

Copy: *"This code has expired"* / *"Codes live for 90 seconds so a screenshot is never
enough. Generate a fresh one to keep going."*

Two conflicts to resolve before implementing:
1. The design says **90 seconds**; the deployed page runs ~120s (observed "Expires in
   1:59"). Pick one.
2. Regenerating requires minting a **new session** from the page. Phase 04 must confirm
   whether the worker permits that without a protocol change. If it does not, this
   degrades to a reload prompt and the button copy must change.

## Approved state (maps to `view-rendered`)

Header badges, centred, wrapping: green "One-time delivery" pill, plus a neutral
"Closes in {n}s" pill.

Then one glass card, `max-width:540px`, containing:

**Item header** — 40px `#101114` rounded square with a white monogram, then the item
title and a "Shared by …" line. This is the part that needs `title` and the sharer name
on the wire (phase-03).

**Field rows** — each row is tap-to-copy. Left: uppercase label over the mono value,
truncating with ellipsis. Right: a "Copied" pill that animates in, and a 32px round "…"
button opening a glass menu (`min-width:214px`, radius 20) with **type-aware actions**:

| Field | Menu actions |
|---|---|
| Website | Open website · Copy address |
| Username | (copy via row tap) |
| Password | Show/Hide · Copy · **Copy username & password** |
| One-time code | Copy one-time code |

The TOTP row replaces the text value with a `190×56` canvas — a live countdown
visualisation, not a plain string.

Footer of the card: a hint row "Tap any field to copy it." Below the card, a centred
"Done & close" outline button. Page footer: a 34px rule and the line *"Nothing here
touches a server. The code is generated in your browser and dies with this tab."*

## Copy (EN) — from `i18n.js`

`kicker` Quick View · `h1` Bring a secret to this device · `sub` Any browser, any
platform. Scan with Loox on your iPhone, approve with Face ID — the fields land here
exactly once. · `steps` Point your iPhone camera at the code / Loox opens with the
request / Approve with Face ID · `mobT` Already on your iPhone? · `mobBtn` Open in Loox ·
`mobNote` Or let another device scan the code below. · `sas` Verify code · `waiting`
Waiting for a scan from the Loox app… · `approving` Waiting for the owner's Face ID… ·
`once` One-time delivery · `close` Closes in · `done` Done & close · `expT` This code has
expired · `expB` Codes live for 90 seconds so a screenshot is never enough. Generate a
fresh one to keep going. · `regen` Generate a new code · `more` More · `copiedLbl` Copied
· `tapHint` Tap any field to copy it. · `openSite` Open website · `copyUrl` Copy address
· `copyPair` Copy username & password · `copyCode` Copy one-time code · `foot` Nothing
here touches a server. The code is generated in your browser and dies with this tab.

All of the above need Vietnamese counterparts — see phase-08. Note the copy style rules:
no "!", and the em dashes above must be reworked to match house style before shipping.

## Not covered by the design

The prototype only draws a **Login**. There is no comp for a secure note (so nothing for
markdown), payment card, identity, SSH key, recovery codes, security questions, or
custom. Phase 05 must design those in this language and have them reviewed.

Two smaller gaps: the prototype has no dark mode for this page, and no empty state for an
approval that arrives with zero fields — which today is the *default* outcome for six of
eight categories (see phase-02).
