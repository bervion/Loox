# Out of scope — hard exclusions

---

## 1. QR encoding and `drawQr` geometry — DO NOT TOUCH

**Frozen files and functions:**
- `workers/loox-quick-view/src/qr-encoder.ts` — the whole module
- `drawQr` in `workers/loox-quick-view/src/open-page-script-render.ts:32-129`
- The locator string built by `qrLocatorString()` in `open-page-script-flow.ts:50-52`

**Frozen specifics inside `drawQr`:**
- the module matrix and the `quiet = 4` margin
- `modulePx = Math.max(4, Math.floor(480 / (qr.size + quiet * 2)))` and the canvas backing size
  it writes with `canvas.width` / `canvas.height`
- the body radius `R = modulePx / 3` and the neighbour-aware corner fusing
- the **stroked** finder ring: `lineWidth = modulePx`, `ring = modulePx * 6`, `ringR = ring / 3.5`,
  and the `dot = modulePx * 3`, `dotR = dot / 3.5` centre
- the unconditional ink-on-white fill (`#ffffff` background, `#000000` ink) regardless of theme
- the `arcTo`-based `rrPath` helper, which exists because `ctx.roundRect` needs Safari 16.4+ and
  is not feature-detected anywhere on this page

**Why.** This code was fixed after an outage. A previous pass drew the finders as three
*filled* concentric rounded squares. A filled 7-module square loses its corner modules entirely
once the radius passes ~1.707 — the corner module's centre sits at (0.5, 0.5) from the corner and
falls outside the arc. At the 2.2 that shipped, all four corners of all three finders rendered
white and nothing could read the code: not the app, not the iOS camera. Recovering the module
matrix from a screenshot showed exactly 13 finder mismatches. A stroke does not have that failure
mode, because the ink is centred on the path and the ring stays a full module thick all the way
round however tightly it is rounded.

**The QR is decorative in the new design.** That is a reason to restyle its *surroundings*, not
its geometry.

**What you may do:** restyle the `.qr-card` wrapper (`open-page.ts:53-54`) — padding, radius,
border, shadow, background — and the CSS box of `#qr-canvas` (`:55`, currently
`width: min(280px,72vw); height: auto`).

**What you may not do:** change the canvas backing size from JS, alter any of the geometry above,
recolour the ink or the paper, add a logo overlay, or change the module shape. If a design ask
implies any of these, refuse it and point at this file.

**Guard:** `pnpm exec tsx scripts/test-qr-decode.ts` must pass unchanged after every phase.

## 2. The crypto transcripts

`QuickViewPayloadSealer.aad()`, `QuickViewFieldManifest.hash()`, their worker mirror in
`contracts/payload-transcript.ts`, `VaultifyTests/Fixtures/quick-view-payload-vectors-v1.json`,
and `scripts/generate-quick-view-vectors.ts`.

Phase-03 is designed specifically so none of these change. The proof is that
`test-open-page-crypto-parity.ts` and `test-quick-view-transcripts.ts` must pass **unchanged** —
if either moves, metadata leaked into a transcript and the change is wrong. Stop and re-read
phase-03 R1.

Never add the item title as a synthetic *field*. It would change the manifest count and every
ordinal and break the AAD binding against every app version in the field.

## 3. The server and the protocol

No change to `session-do.ts`, `session-do-mailbox.ts`, `sessions.ts`, `pop-consume.ts`,
`payload-upload.ts`, or any TTL. Specifically ruled out as impossible without a protocol change,
and to be refused if asked:

- **Re-showing the same code after expiry.** `SessionDO.create` throws `session_already_created`
  on a second create against the same DO id; keys are immutable by design. Expiry always means a
  new code the phone must re-scan. The restart CTA must never be phrased as "show the code again".
- **Re-delivering the payload after a successful reveal.** `consumePayload` deletes the payload
  and challenge on success. CONSUMED is terminal.

## 4. Trusted Types

Do not create a policy named `loox-quick-view-open`. The CSP declares the name but no policy is
ever created (verified: zero occurrences of `createPolicy` or `trustedTypes` in the worker).
Creating one would reintroduce an HTML sink into the one code path that handles decrypted secrets.
Phase-01 R6 asserts this by test.

## 5. Dark mode

Explicitly deferred, not forgotten. See phase-07 R3. `color-scheme: light` stays pinned for v1.

## 6. Stale documentation

Do not plan against `looxpassword/docs/design-guidelines.md` or `docs/design-brief.md`. Both
describe systems that were never built or have since been retired. `globals.css` and the shipped
components are the source of truth.
