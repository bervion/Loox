# Phase 04 — States, copy, and the expired path

**Depends on:** phase-01.
**Scope:** the five view containers, their sub-states, the timers behind them, and the exact
copy for each. `[DESIGN-PENDING]` marks visual treatment only — the copy below is proposed and
reviewable now.

---

## Context

- `workers/loox-quick-view/src/open-page.ts:157-179` (the five containers)
- `workers/loox-quick-view/src/open-page-script-render.ts:24-30, 146-165, 234-245`
- `workers/loox-quick-view/src/open-page-script-flow.ts:18-19, 119-125, 175-198`
- `workers/loox-quick-view/src/session-do.ts` (session TTL), `session-do-mailbox.ts` (consume TTL)

## The state machine (do not add or remove containers — add inside them)

| View | Entered by | Left by |
|---|---|---|
| `view-boot` | initial HTML | `renderWaiting` on `POST /sessions` success; `renderTerminal('error')` on any bootstrap throw |
| `view-waiting` | `renderWaiting(...)` | `APPROVED` → approved; `EXPIRED` → terminal; local countdown 0 → terminal |
| `view-approved` | `renderApproved()` | `renderFields` on decrypt success; any PoP/decrypt throw → terminal `error` |
| `view-rendered` | `renderFields(...)` | 5-min TTL → terminal `timeout`; 2-min hidden autolock → terminal `locked`; Done → terminal `closed` |
| `view-terminal` | `renderTerminal(reason)` | nothing today — R3 adds the restart |

`setView` toggles the `hidden` class across the five siblings. **`hidden` as a class name is
load-bearing** in three places; renaming it breaks state switching silently.

**Do not design a UI for the `CONSUMED`-elsewhere branch** (`flow.ts:124`). `stopSubscription()`
runs the instant APPROVED arrives, and consume requires *this* browser's ECDSA PoP, so the branch
is effectively unreachable. Leave the code, give it no design.

## Timers — the exact numbers

| Timer | Value | Source | Visible today |
|---|---|---|---|
| Session create → approval | **180s** | `CREATE_TO_APPROVAL_TTL_MS`, `session-do.ts` | yes, `#waiting-countdown` |
| Render TTL after reveal | **300s** | `RENDER_TTL_MS`, `flow.ts:18` | yes, `#render-countdown` |
| Hidden-tab autolock | **120s** | `HIDDEN_AUTOLOCK_MS`, `flow.ts:19` | **no** — R4 |
| Claim → consume | 90s | `PAYLOAD_CONSUME_TTL_MS` | no — R5 |
| PoP challenge | 30s | `POP_CHALLENGE_TTL_MS` | no — R5 |

The render TTL is armed twice — the visible countdown (`render.ts:201`) and a redundant
`setTimeout` (`flow.ts:175`). Both call `wipeAndClose`, which is idempotent behind
`sessionState.closed`. **Keep the redundancy** — it is the only thing that still wipes if the
countdown element goes missing.

---

## Requirements

### R1 — Copy for every state

Proposed. Project copy style applies: no exclamation marks, no em dashes, no middot separators.
Ideas separate by layout or by words. VI in phase-08.

**Boot**
| Slot | EN |
|---|---|
| body | Preparing a secure session |

**Waiting** (headline and sub are page-level, currently at `open-page.ts:154-155`)
| Slot | EN |
|---|---|
| h1 | Open on your computer |
| sub | Scan this code with Loox on your iPhone and approve with Face ID. The fields appear here exactly once. |
| verify label | Verify code |
| countdown label | Expires in |
| hint | Scan this code or type it into the app to view your item on this screen. |
| QR fallback (drawQr failed) | The code image could not be drawn. Type the code above into Loox instead. |

**Approved / verifying**
| Slot | EN |
|---|---|
| body | Approved on your phone. Verifying and decrypting. |

**Rendered**
| Slot | EN |
|---|---|
| badge | One-time delivery |
| countdown label | Closes in |
| autolock hint (new, R4) | Switch away from this tab for 2 minutes and these fields clear themselves. |
| clipboard warning | Copied to this computer's clipboard. Clear it when you are done. |
| done button | Done and close |

**Terminal — five reasons.** Four exist (`render.ts:234-239`); `timeout` is new.

| Reason | Title | Body |
|---|---|---|
| `expired` (never scanned) | Session expired | Nobody approved this session in time. Nothing was sent to this page. |
| `timeout` **(new)** | Fields cleared | Your 5 minutes are up and the fields have been wiped from this page. Approve again from the app to see them once more. |
| `locked` | Locked | This view was locked after the tab was hidden. Start a new session to see the fields again. |
| `closed` | Closed | This session has been closed and the fields are cleared. |
| `error` | Unavailable | This Quick View could not be opened. Start a new session from the app. |
| `rate_limited` **(new, R6)** | Too many attempts | Too many sessions were started from this network. Wait a few minutes and try again. |

### R2 — Stop the reveal timeout borrowing the pre-scan copy

Today a user who successfully received their fields and let 5 minutes run out is told
"This Quick View session is no longer available" — identical to a user whose phone never
scanned. Two very different situations, one message.

Change `wipeAndClose('expired')` → `wipeAndClose('timeout')` at:
- `open-page-script-render.ts:201` (the visible countdown's `onZero`)
- `open-page-script-flow.ts:175` (the redundant `setTimeout`)

Leave `renderWaiting`'s `onZero` at `render.ts:159` as `'expired'` — that one is correct.

### R3 — The terminal state needs a way out

Today `#view-terminal` is a title and a paragraph, every copy ends in "close this tab", and
`bootstrap()` only ever runs once from `DOMContentLoaded`. `sessionState.closed` is sticky with
no reset path. There is genuinely no in-page recovery.

**Add a "Get a new code" button that calls `location.reload()`.** Zero backend change. Why this
is safe, all verified:

- A new session is one unauthenticated `POST /v1/quick-view/sessions` with a fresh ECDH+ECDSA
  pair. It has no dependency on the dead session.
- The page uses **no storage APIs at all** (asserted by the existing header test), so a reload
  discards nothing of value.
- `bootstrap()` fires from `DOMContentLoaded`, so reload re-runs the flow cleanly with no risk of
  a stale interval or a half-reset `sessionState` surviving.
- Rate budget is `session_create_ip` 30/hour. Honest use burns at most ~20/hour at 3-minute
  sessions, so the button is safe — but **debounce it with a 2-3s cooldown** so it is not a spam
  target.

Prefer reload over an in-page soft restart. A soft restart means resetting `sessionState.closed`,
`lastObservedState`, `sessionPathId`, `consumedHere`, and clearing `countdownTimer` — more code
and a real risk of a zombie timer holding a reference to a wiped session. YAGNI.

**Show the button for `expired`, `timeout`, `locked` and `rate_limited`.** For `closed` it is
optional (the user chose to close). For `error` show it too, since a transient failure is the
common cause.

New string: **Get a new code**.

**Say no to these if asked** — they are impossible without a protocol change:
- *Re-showing the same code after expiry.* `SessionDO.create` throws `session_already_created`
  on a second create against the same DO id; keys are immutable by design. Expiry always means a
  **new** code the phone must re-scan. Never phrase the CTA as "show the code again".
- *Re-delivering the payload after a successful reveal.* `consumePayload` deletes the payload and
  challenge on success. CONSUMED is terminal. The owner must approve again from the phone.

### R4 — Surface the invisible hidden-tab autolock

Two minutes of `document.hidden` wipes the session and the user gets no warning and no indication
the rule exists. Add the static hint line from R1 to `#view-rendered`. No new timer, purely copy.

`[DESIGN-PENDING]` — whether this is a persistent hint or a warning banner that appears at, say,
90 seconds hidden. A static line is the low-risk default.

### R5 — Bound the approved/verifying state

`renderApproved()` clears the countdown (`render.ts:163`), so the verifying view is an unbounded
spinner. Server-side the claim arms a 90s window and the PoP challenge lives 30s. If the round
trip stalls the user watches a spinner forever and then gets a generic error.

Show either a bounded progress indication or the remaining consume budget.
`[DESIGN-PENDING]` — which. A determinate 90s bar is honest; a spinner with a "this is taking
longer than usual" line after ~10s is calmer.

### R6 — Distinguish rate limiting

`postJson` (`flow.ts:31-38`) has `res.status` in hand and throws it away, so a 429 surfaces as a
generic "Unavailable". Capture the status and route 429 to the new `rate_limited` terminal
reason. Page-local change, not a protocol change.

### R7 — Announce state changes to assistive tech

Detail is in phase-07, but the structural part belongs here because it is about state, not
styling:
- `role="status" aria-live="polite"` on `#view-approved` and `#view-terminal`.
- On state entry, move focus to the newly shown view's heading (`tabindex="-1"` + `.focus()`).
- **Countdowns must not be live regions** — they tick every 1000ms and a naive `aria-live` gives
  a once-per-second announcement flood. Set `aria-live="off"`, mark them `role="timer"`, and add
  one visually-hidden polite region updated only at milestones: 2:00, 1:00, 0:30, 0:10.

---

## Files to modify

- `workers/loox-quick-view/src/open-page.ts` — terminal action button, autolock hint, ARIA
- `workers/loox-quick-view/src/open-page-script-render.ts` — `TERMINAL_COPY`, R2, R3, R5, R7
- `workers/loox-quick-view/src/open-page-script-flow.ts` — R2, R6
- `workers/loox-quick-view/scripts/test-open-page-headers.ts` — new ids

## Tests and validation

- Extend `REQUIRED_IDS` with the new nodes.
- Assert `TERMINAL_COPY` has all six keys and that `renderTerminal` on an unknown key falls back
  to `error`.
- `pnpm exec tsx scripts/test-session-state-machine.ts` — unchanged.
- Manual: force each terminal reason (let the 3-min countdown lapse; let the 5-min TTL lapse;
  hide the tab 2 min; click Done; break the consume call; hammer session create past 30/hour) and
  confirm each shows its own copy and a working restart.

## Risks

- **"Get a new code" reads as "recover my data".** It cannot recover anything — it starts a fresh
  session that the phone must approve again. The body copy must set that expectation before the
  button, especially for `timeout` where the user just lost real data.
- **Reload discards the SAS** the user may have been mid-way through verifying. Acceptable: the
  session it belonged to is already dead.
