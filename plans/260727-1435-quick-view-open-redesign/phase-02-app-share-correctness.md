# Phase 02 — App-side share correctness

**Depends on:** nothing. Required under **both** decision options.
**Why:** without this, "supports all vault item types" is false at the source — sharing a card
today is a three-tap trap that ends in a blank page, and no amount of page work fixes it.

---

## Context

- `Vaultify/Features/Sharing/LooxLink/LooxLinkEnvelope.swift:44-51`
- `Vaultify/Features/Sharing/QuickView/QuickViewApprovalFlowModel.swift:68-73, 186`
- `Vaultify/Features/Sharing/QuickView/QuickViewApprovalSheet.swift` (approve button)
- `Vaultify/Features/ItemDetail/ItemDetailScreen.swift:289`
- `Vaultify/Features/Sharing/QuickLinkView.swift:39`

## The bug

```swift
// LooxLinkEnvelope.swift:44 — verified
static func defaultSelectedFieldIDs(of item: VaultItem) -> Set<String> {
    Set(shareableFields(of: item).filter { field in
        switch field.kind {
        case .username, .email, .url, .password: true
        default: false
        }
    }.map(\.id))
}
```

Only the credential trio is pre-selected. Cross-referenced against
`ItemCategory.fieldTemplate` (`ItemCategory.swift:80-127`), the default selection is:

| Category | Template field kinds | Default selection |
|---|---|---|
| login | username, password | both |
| note | multiline | **empty** |
| card | text, monospace, text, monospace, number | **empty** |
| identity | text, email, phone, multiline, date, monospace | Email only |
| sshKey | multiline, multiline | **empty** |
| recoveryCodes | multiline | **empty** |
| securityQuestions | text ×4 | **empty** |
| custom | text | **empty** |

`ItemDetailScreen.swift:289` feeds that straight into `QuickViewApprovalFlowModel`
(`:73 self.selectedFieldIDs = defaultSelectedFieldIDs`). The Approve button carries **no
`.disabled`** (verified — no `disabled` occurrence in `QuickViewApprovalSheet.swift`), and
`compose()` happily returns `fields: []`.

**Result:** for six of eight categories the owner opens Quick View, sees nothing pre-selected,
taps Approve with Face ID, and the browser renders an empty fields card under a
"One-time delivery" badge and a countdown. A successful-looking approval that delivered nothing,
and it burns one of the owner's rolling quota approvals.

## Requirements

### R1 — A Quick-View-specific default selection

When the credential-trio intersection is empty, select **all shareable fields**.

Do **not** change `defaultSelectedFieldIDs` in place. `QuickLinkView.swift:39` shares the same
helper and its default must not shift silently — Loox Link is a different product surface with
its own sharing semantics. Add a sibling:

```swift
/// Quick View default: the credential trio when the item has one, otherwise every
/// shareable field. A category whose template contains no username/url/password
/// (card, sshKey, recoveryCodes, securityQuestions, note, custom) would otherwise
/// open the approval sheet with nothing selected and seal an empty payload.
static func quickViewDefaultSelectedFieldIDs(of item: VaultItem) -> Set<String> {
    let trio = defaultSelectedFieldIDs(of: item)
    return trio.isEmpty ? Set(shareableFields(of: item).map(\.id)) : trio
}
```

Call it from `ItemDetailScreen.swift:289` only.

**Open design question, `[DESIGN-PENDING]`:** for `identity`, the trio is non-empty (Email
alone), so the fallback does not fire and the owner sees a 6-field item with 1 selected. That
is arguably correct (identities carry an ID number) and arguably surprising. Two options:
(a) leave it, (b) treat a selection covering under some fraction of the item as "empty" too.
Recommend (a) — the owner reviews the sheet before Face ID, and over-selecting personal data by
default is the worse failure. Confirm with the user.

### R2 — Gate approval on a non-empty payload

`compose()` must never be reachable with an empty result. Add to the Approve button in
`QuickViewApprovalSheet.swift`:

```swift
.disabled(flow.selectedFieldIDs.isEmpty && !flow.includeCurrentTOTP)
```

A disabled primary button with no explanation is its own UX failure, so pair it with an inline
hint in `QuickViewApprovalFieldsSection` shown only in that state:

> **EN** Select at least one field to share.
> **VI** Chọn ít nhất một trường để chia sẻ.

Design for the longest localized label, per `docs/design-dna-standard.md`.

### R3 — Defence in depth in the composer

The UI gate can regress. Make the invariant explicit at the boundary:

```swift
nonisolated enum ComposeError: Error, Equatable {
    case totpWaitExceedsSessionBudget
    case totpSeedUnreadable
    case noFieldsSelected      // new
}
```

Throw it in `compose()` after the array is assembled and before the manifest hash, when
`fields.isEmpty`. Fail closed rather than sealing a payload that renders as a blank card.

Surface it through the flow model's existing error path with copy that names the cause rather
than a generic failure.

---

## Files to modify

- `Vaultify/Features/Sharing/LooxLink/LooxLinkEnvelope.swift` — R1 (add, do not alter existing)
- `Vaultify/Features/ItemDetail/ItemDetailScreen.swift` — R1 call site
- `Vaultify/Features/Sharing/QuickView/QuickViewApprovalSheet.swift` — R2
- `Vaultify/Features/Sharing/QuickView/QuickViewApprovalFieldsSection.swift` — R2 hint
- `Vaultify/Features/Sharing/QuickView/QuickViewPayloadComposer.swift` — R3
- `Vaultify/Localizable.xcstrings` — new strings, EN + VI (phase-08)

## Tests and validation

- `VaultifyTests/LooxLinkEnvelopeTests.swift` — assert
  `quickViewDefaultSelectedFieldIDs` returns every shareable field for a card / sshKey /
  recoveryCodes / securityQuestions / note item, and still returns exactly the trio for a login.
- Assert `defaultSelectedFieldIDs` behaviour is **unchanged** (guards the Loox Link surface).
- `VaultifyTests/QuickViewFlowTests.swift` — assert `compose()` throws `.noFieldsSelected` on an
  empty selection with `includeCurrentTOTP == false`.
- Assert the existing `fieldManifestHash` expectations are untouched by this phase.

```bash
cd /Users/bervion/Developer/Projects/mobile/ios/Vaultify
tuist generate --no-open
make check
```

Manual: open a Payment Card → Quick View. All five fields pre-selected, Approve enabled.
Deselect all → Approve disabled with the hint. Verify in EN and VI.

## Risks

- **Broader default = more data shared by default.** This is the real trade-off. Mitigation: the
  owner still reviews the full selection on the approval sheet before Face ID, and every field is
  individually deselectable. The alternative — a silent empty share — is worse because it teaches
  the owner that the feature is broken.
- **`shareableFields` already hard-excludes** TOTP seeds, extra-protected (`guard2`) values,
  attachments and empty values (`LooxLinkEnvelope.swift:35-40`), so "select all shareable" can
  never reach a seed or a guard2 value. Verified.
