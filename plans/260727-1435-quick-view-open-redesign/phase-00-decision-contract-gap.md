# Phase 00 — Decision: the contract gap

**Type:** decision gate, not implementation. Nothing in phase-03 or the per-category half of
phase-05 can start until this is answered.

---

## Context

Verified source:
- `Vaultify/Features/Sharing/QuickView/QuickViewPayloadComposer.swift:23-26` — the wire struct.
- `Vaultify/Features/Sharing/LooxLink/LooxLinkEnvelope.swift:68-76` — kind mapping hop 1.
- `VaultifyCore/Models/ItemCategory.swift:80-127` — the 8 category field templates.
- `workers/loox-quick-view/src/open-page-script-flow.ts:172-174` — what the page reads.

## The gap, stated precisely

```swift
// QuickViewPayloadComposer.swift:23
nonisolated struct QuickViewPayload: Codable, Sendable, Equatable {
    var version: Int = 1
    var fields: [QuickViewPayloadField]
}
```

`compose()` at line 94 builds it as `QuickViewPayload(fields: fields.map(wireField))`.
`item.category` and `item.title` are read nowhere in the file, even though the caller
(`QuickViewApprovalFlowModel.swift:186`) holds the full freshly-read `VaultItem`.

Two lossy hops flatten the kind space:
1. `LooxLinkEnvelope.viewerKind` (`:68-76`) — `.username`/`.email` → `username`;
   `.text` **and** `.multiline` → `note`; `.number`/`.phone`/`.monospace`/`.date` → `custom`.
2. `QuickViewPayloadComposer.wireKind` (`:143-152`) — re-maps, plus `otp-code`.

Net wire vocabulary: `username | password | url | note | custom | otp-code`. Six strings.
(`QuickViewFieldKind.email` is dead — hop 1 already merged it into `username`, so
`kind(fromViewerKind:)` at `:133` can never return it.)

The redesign's ask — present all 8 item types well — needs the category. The page cannot
have it without being told.

---

## Option A — additive wire change (recommended)

Add three optional keys inside the already-encrypted payload: `category`, `title`, and a
per-field `multiline` flag. Implementation is phase-03.

**Cost:** ~6 lines of Swift, 3 web files, one test extension. An app release, so old app
versions in the field still send the old shape.

**Why it is safe — verified, not assumed:**

- **AAD is unaffected.** `QuickViewPayloadSealer.aad(...)` (`:68-82`) is a pure function of six
  non-plaintext inputs: `raw(PAYLOAD_MAGIC) ‖ blob(session_id) ‖ blob(enc_key_hash) ‖
  blob(approval_id) ‖ blob(field_manifest_hash) ‖ i64(issued_at) ‖ i64(expires_at)`. The
  plaintext enters only as the first argument to `AES.GCM.seal`. The worker mirror
  (`contracts/payload-transcript.ts`) is byte-identical, and the browser does not even rebuild
  it — it uses the AAD bytes `/consume` returns verbatim. Changing the JSON shape changes only
  the ciphertext length.
- **The field manifest hash is unaffected.** `QuickViewFieldManifest.hash(orderedFields:)`
  (`:64-74`) digests `magic ‖ u32(count) ‖ per-field [stableID, kind, concealed, ordinal]` over
  `[QuickViewApprovedField]` — the app-internal array, not the wire struct. Top-level keys never
  enter it.
  **Corollary, load-bearing:** never smuggle the title in as a synthetic *field* appended to the
  array. That changes `count` and every `ordinal`, and `VaultifyTests/QuickViewFlowTests.swift`
  asserts exactly that sensitivity for the virtual TOTP field. Metadata stays top-level.
- **No contract re-freeze.** `VaultifyTests/Fixtures/quick-view-payload-vectors-v1.json` pins
  only `kdf_vectors` and `aad_vectors`. The payload plaintext JSON schema is not among the eight
  frozen artifacts. No vector regeneration, no `generate-quick-view-vectors.ts` run, no BE
  sign-off.
- **No worker change and no server change.** The server treats ciphertext and AAD as opaque.
  `payload-upload.ts:21` caps the request body at 16KB; category + title add ~80 bytes.
  Its `looksLikePlaintext` tripwire keys are the literal request-JSON keys `username`/`password`
  — ours are `category`/`title` and live inside the ciphertext regardless.
- **Compatible both directions, no version bump.** The page reads
  `(envelope && envelope.fields) || []` and gates on no version anywhere
  (`open-page-script-flow.ts:172-174`). An old page ignores new keys; a new page sees
  `envelope.category === undefined` from an old app and falls back. Keep `version: 1` — bumping
  buys nothing and risks a future strict reader.

**Is sending the title a new exposure?** The payload is end-to-end encrypted to a browser keypair
the user just SAS-verified, and it already carries plaintext passwords, SSH private keys, PINs,
CVVs and live TOTP codes. A title and a 3-bit enum are strictly less sensitive than what is
already inside the same AEAD box. The server never sees them. The one deliberate exclusion in
the composer is `stableID` (`:6-9`), excluded for being an app-internal identifier, not for being
secret — title and category are user-facing content, the opposite category of thing.

The genuine new exposure is **presentational**: a title is human-meaningful at a glance and would
sit on screen permanently, whereas values sit behind Reveal. That argues for shoulder-surfing
hygiene and two hard rules, not for withholding it:
- **Never** write the title to `document.title`, the URL, or history. Those survive
  `wipeAndClose()` and the 5-minute TTL — they persist in the tab strip, the OS window switcher,
  session restore, and browsing history. It belongs in a DOM node inside `#view-rendered` only.
- **Register its node with `wipeRendered()`.** A header rendered outside `fieldRowNodes` would
  survive the wipe in the live DOM after expired/locked/closed.

**Limitation:** users on an app version older than the release still send the old shape. Handled
by the phase-03 fallback (a neutral header, never a guess).

---

## Option B — frontend-only inference

Classify the category by reading labels and value shapes in the browser. No app change.

**Cost:** 150+ lines of classifier in the one code path that handles decrypted secrets, plus a
per-language label lexicon that goes stale the moment a third language ships.

**Honest verdict per category:**

| Category | Inference | Why |
|---|---|---|
| login | **works** | has `kind=password` or `kind=url` |
| sshKey | **works** | values start `-----BEGIN OPENSSH PRIVATE KEY-----` / `ssh-rsa AAAA` / `ssh-ed25519 AAAA` — content-based, language-independent, deterministic |
| card | **partial** | Luhn-valid 13–19 digits plus an MM/YY sibling is a strong signal, but the card number is `concealed`, so you must classify off a secret before the user reveals it, and the signal vanishes if the owner shares only Cardholder + Expiry |
| securityQuestions | **partial** | alternating unconcealed/concealed pairs where the unconcealed value ends in `?` — but a login carrying a Note plus a protected Note has the same shape |
| identity | **fails** | the only signals are label strings |
| recoveryCodes | **fails** | a single concealed note; line-count heuristics collide with any pasted list and with a protected secure note |
| note vs custom | **fails** | no signal whatsoever |

**Three things the owner does routinely defeat it:**
1. **Labels are localized to the owner's language.** `LooxLinkEnvelope.build` emits
   `Field(label: appLabel(field.label), ...)` and the comment at `:54-55` says so outright. A
   Vietnamese owner sharing a card sends "Người giữ thẻ" / "Số thẻ" / "Mã bảo mật".
2. **Users rename labels freely,** and `ItemCategory.custom` has no template at all.
3. **Partial selection.** The owner can deselect the very field the classifier keys on.

**And the decisive point:** even a perfect classifier cannot produce the item **title**, which is
the single most useful thing for answering "which of my items is this?". There is zero signal for
it on the wire.

**A wrong guess is worse than no guess.** Labelling a login as "Payment Card" on a security
product's one-time-delivery page is a trust failure.

---

## Recommendation

**Take Option A, and keep inference only as an old-client fallback — degraded to a neutral
header, never a guess.**

Option A is exact, breaks no contract, needs no re-freeze, and costs ~6 lines of Swift. Option B
is fragile, cannot produce a title, and is actively harmful when wrong. The only thing inference
buys is working with app versions already in the field, so use it there and only there, limited
to the two content-based tests that cannot be wrong (phase-03 step 3).

## Decision record

- [ ] **A** — additive wire change. Proceed with phase-03.
- [ ] **B** — frontend-only inference. Skip phase-03; phase-05 renders a neutral header for every
      item and the "all 8 categories" acceptance criterion is downgraded to "all 8 categories
      render legibly as typed field lists, without category identification".

## Risks

- Choosing B now and A later means building the category header twice.
- Choosing A means the redesign's category header is empty for old app versions until adoption
  catches up. The neutral-header fallback must therefore look deliberate, not broken — it is a
  design state, not an error state, and needs a `[DESIGN-PENDING]` treatment of its own.
