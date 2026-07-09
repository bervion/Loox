# Phase 02 — Recipient In-App Shared-Passkey Display

## Context Links
- Overview: [plan.md](plan.md)
- Depends on: [phase-01](phase-01-owner-edit-share-passkey-management.md) (grant must actually
  carry the passkey before there is anything to display).

## Overview
- **Priority**: P1 (visibility parity; AutoFill already works)
- **Status**: pending
- **Description**: Show a read-only "Passkeys" section on the recipient's shared-item detail,
  mirroring `ItemPasskeysSection`, driven by the projection's existing `cachePasskeys`.

## Key Insights
- `ItemDetailScreen.swift:71-76` renders `ItemPasskeysSection(item:)` only for `sharedOrigin ==
  nil`; shared items fall into the `else` branch (safety-code card only).
- `SharedItemsProjection` already computes `cachePasskeys[item.id]: [SharedPasskeyEntry]`
  (`SharedItemsProjection.swift:30, 192, 248-268`) from the grant's display `PasskeyMeta` +
  capability mode — but it is consumed ONLY by the AutoFill cache, never surfaced to UI.
- `buildItem` deliberately strips passkey slots from the projected item's fields
  (`SharedItemsProjection.swift:317`), so the passkey must be surfaced via the entries, not fields.

## Requirements
Functional:
- On a shared item's detail (recipient), show a "Passkeys" section listing each shared passkey's
  relying party + username + mode (Shared / Ask each time), read-only.
- No private-key exposure in-app; tapping does not reveal the secret (AutoFill remains the only
  use path — respects decision 260705).
- Empty when the grant carries no passkeys.

Non-functional:
- Reuse the visual language of `ItemPasskeysSection` (Polaris, tokens, purple glyph).
- No new decryption or store writes — read `cachePasskeys` metadata only.

## Architecture
- Expose the entries: add `func sharedPasskeys(itemID:) -> [SharedPasskeyEntry]` (or a lightweight
  display struct) on `SharedItemsProjection`.
- New `SharedItemPasskeysSection` view (mirrors `ItemPasskeysSection`) rendering those entries.
- `ItemDetailScreen` shared branch (`else` at :74-76): add `SharedItemPasskeysSection(itemID:)`
  above/near the safety-code card.

## Related Code Files
Modify:
- `Vaultify/Services/Sharing/SharedItemsProjection.swift` — expose shared passkey entries for UI.
- `Vaultify/Features/ItemDetail/ItemDetailScreen.swift` — render the shared-passkeys section.
Create:
- `Vaultify/Features/Passkeys/SharedItemPasskeysSection.swift` — read-only recipient view.

## Implementation Steps
1. Add a UI accessor on `SharedItemsProjection` returning the item's shared passkey display data.
2. Build `SharedItemPasskeysSection` from that data (RP, username, mode badge).
3. Wire it into `ItemDetailScreen`'s shared branch.
4. Localize section title + mode labels EN + VI.
5. `tuist generate` + `make check`.

## Todo List
- [ ] Projection UI accessor for shared passkeys
- [ ] `SharedItemPasskeysSection` view
- [ ] Wire into shared item detail
- [ ] Localize EN + VI
- [ ] `tuist generate` + `make check`

## Success Criteria
- Recipient opening a shared login that includes a passkey sees a Passkeys row (RP + username +
  mode); no passkey ⇒ no section.
- No secret is shown in-app; AutoFill still the only sign path.

## Risk Assessment
- **Projection observation**: ensure the accessor reads observed state so the section updates on
  refresh. Low risk (read-only).

## Security Considerations
- Metadata-only display; private key never surfaced in-app (decision 260705 intact).

## Next Steps
- Phase 3 QA covers recipient display + AutoFill together.
