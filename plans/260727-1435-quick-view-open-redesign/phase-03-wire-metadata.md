# Phase 03 — Wire metadata: category, title, multiline

**Depends on:** phase-00 answered **A**. Skip entirely under B.
**Blast radius:** app + page. **No worker change, no server change, no contract re-freeze.**

---

## Context

- `Vaultify/Features/Sharing/QuickView/QuickViewPayloadComposer.swift`
- `Vaultify/Features/Sharing/QuickView/QuickViewFieldManifest.swift:64-74` (must stay untouched)
- `Vaultify/Features/Sharing/QuickView/QuickViewPayloadSealer.swift:68-82` (AAD, must stay untouched)
- `workers/loox-quick-view/src/open-page-script-flow.ts:172-174`
- `workers/loox-quick-view/src/open-page.ts:169-174`
- `workers/loox-quick-view/src/open-page-script-render.ts:169-202`

Safety analysis is in `phase-00-decision-contract-gap.md` and is not repeated here.

## Requirements

### R1 — Three new optional keys on the wire (app)

`QuickViewPayloadComposer.swift:23`. Keep `version: Int = 1` — the page gates on no version
anywhere, so a bump buys nothing and risks a future strict reader.

```swift
nonisolated struct QuickViewPayload: Codable, Sendable, Equatable {
    var version: Int = 1
    var fields: [QuickViewPayloadField]
    /// ItemCategory.rawValue — presentation grouping for /open. Metadata, inside
    /// the AEAD box like every field value. Top-level ON PURPOSE: a synthetic
    /// field would change the manifest count and every ordinal.
    var category: String?
    /// Owner-authored item title. User-facing content, never an app-internal id.
    var title: String?
}
```

Per-field, at `:10-21`, one optional flag. This is what makes the markdown requirement safe —
`.text` and `.multiline` both arrive as `kind: "note"` today, so the page has no way to tell a
one-line "Cardholder" from a 40-line note:

```swift
var multiline: Bool?
// CodingKeys: case multiline
```

Populate at `:94`:

```swift
let payload = QuickViewPayload(
    fields: fields.map(wireField),
    category: item.category.rawValue,
    title: item.title.isEmpty ? nil : item.title)
```

`wireField` (`:154`) needs the source `DynamicField.kind` to set `multiline`. Cleanest minimal
change: carry it on `QuickViewApprovedField` alongside `kind`, set from `source.kind == .multiline`
in the `zip` at `:70`.

**Hard constraint: do not add `multiline` to `QuickViewFieldManifest.hash`.** The manifest
transcript stays `[stableID, kind, concealed, ordinal]`. Any change there breaks the AAD binding
against every app version in the field.

### R2 — Send it (page)

`open-page-script-flow.ts:172-174`:

```js
var envelope = JSON.parse(new TextDecoder().decode(plainBytes));
renderFields((envelope && envelope.fields) || [], {
  category: (envelope && envelope.category) || null,
  title: (envelope && envelope.title) || null
});
```

### R3 — Render it (page)

New header nodes inside `#view-rendered`, above `#fields-container` (`open-page.ts:169-174`).
Add the new ids to the phase-01 `REQUIRED_IDS` list.

```html
<div id="item-header" class="item-header">
  <div id="item-title" class="item-title"></div>
  <div id="item-category" class="item-category"></div>
</div>
```

`[DESIGN-PENDING]` — layout, whether a category icon appears, and where the header sits
relative to the badges row.

In `renderFields(fields, meta)`:

- `#item-title.textContent = meta.title || ''`
- `#item-category.textContent = CATEGORY_LABELS[meta.category] || CATEGORY_LABELS._unknown`
- **An unknown rawValue must fall back, never render raw.** A future app version can add a
  category this page has never heard of.

```js
var CATEGORY_LABELS = {
  login: 'Login', note: 'Secure Note', card: 'Payment Card', identity: 'Identity',
  sshKey: 'SSH Key', recoveryCodes: 'Recovery Codes',
  securityQuestions: 'Security Questions', custom: 'Custom',
  _unknown: 'Shared fields'
};
```

These labels mirror `ItemCategory.title` (`ItemCategory.swift:17-29`) verbatim so the page and
the app name the same thing the same way. VI values in phase-08.

### R4 — Two hard security rules on the title

Both were established in phase-00 and are release blockers:

1. **Never** write the title to `document.title`, the URL, or history. Those survive
   `wipeAndClose()` and the 5-minute TTL, persisting in the tab strip, the OS window switcher,
   session restore and browsing history. The page hardcodes `<title>Loox Quick View</title>`
   (`open-page.ts:147`) — leave it. Phase-01 R6 adds a `document.title` grep that enforces this.
2. **Register the header nodes with `wipeRendered()`.** `wipeRendered` (`:222`) iterates
   `fieldRowNodes` only; a header rendered outside it survives the wipe in the live DOM after
   expired / locked / closed. Push `{root: headerEl, valueEl: titleEl}` into `fieldRowNodes`, or
   add a parallel array the wipe also walks. Phase-06 R3's `wipeSubtree()` covers it either way.

### R5 — Old-client fallback: neutral, never a guess

When `meta.category` is null (app older than this release), render the neutral
`Shared fields` header and apply **only** the two content-based, language-independent
refinements that cannot be wrong:

- Value starts with `-----BEGIN `, `ssh-rsa `, `ssh-ed25519 ` or `ecdsa-sha2-` → monospace,
  wrap-anywhere, **never** markdown.
- `kind === 'password'` or `'otp-code'` → the existing concealed / countdown treatment.

**Skip card, identity, recoveryCodes and securityQuestions inference entirely.** A neutral
header is honest; a wrong category badge on a security product is a trust failure. Rationale in
phase-00.

`[DESIGN-PENDING]` — the neutral header is a design state, not an error state. It needs a
treatment that reads as deliberate.

---

## Files to modify

**App**
- `Vaultify/Features/Sharing/QuickView/QuickViewPayloadComposer.swift` — R1
- `Vaultify/Features/Sharing/QuickView/QuickViewApprovedField.swift` — carry `multiline`

**Page**
- `workers/loox-quick-view/src/open-page-script-flow.ts` — R2
- `workers/loox-quick-view/src/open-page.ts` — R3 markup
- `workers/loox-quick-view/src/open-page-script-render.ts` — R3, R4, R5
- `workers/loox-quick-view/scripts/test-open-page-headers.ts` — new ids

**Must NOT be modified:** `QuickViewFieldManifest.swift`, `QuickViewPayloadSealer.swift`,
`contracts/payload-transcript.ts`, `VaultifyTests/Fixtures/quick-view-payload-vectors-v1.json`,
`scripts/generate-quick-view-vectors.ts`, `payload-upload.ts`, any server file.

## Tests and validation

Extend `VaultifyTests/QuickViewFlowTests.swift`:

1. `category == item.category.rawValue` and `title` round-trips through JSON.
2. `title` is `nil` for an empty item title.
3. `multiline` is `true` exactly for `.multiline` source fields, absent otherwise.
4. **The critical one:** freeze one expected `fieldManifestHash` hex for a fixed item and assert
   it is byte-identical before and after this change. A future refactor that leaks metadata into
   the manifest then fails loudly rather than silently breaking the AAD binding.

Page and cross-stack:

```bash
pnpm exec tsx scripts/test-open-page-crypto-parity.ts    # must pass UNCHANGED
pnpm exec tsx scripts/test-quick-view-transcripts.ts     # must pass UNCHANGED
pnpm exec tsx scripts/test-quick-view-e2e.ts             # larger ciphertext still under 16KB
pnpm exec tsx scripts/test-open-page-headers.ts
```

If either of the first two moves, metadata leaked into a transcript and the change is wrong —
stop and re-read R1.

Manual matrix: old app + new page (neutral header), new app + old page (keys ignored, no crash),
new + new (full header).

## Risks

- **Someone "helpfully" adds the title as a field.** That changes the manifest count and every
  ordinal and breaks decryption. The frozen-hash test in step 4 is the guard. Call it out in
  review.
- **Rollout skew.** Old apps keep sending the old shape indefinitely; the fallback is permanent
  code, not temporary.
- **A long title inflates the payload.** Irrelevant against the 16KB cap (~80 bytes), but the
  header must truncate visually rather than break the layout.
