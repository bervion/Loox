# Phase 03 — Payment cards list (+ persona-scope fix)

Type: reuse + **BUGFIX** · Depends: 01

## Context
- Card = `VaultItem` `.card`; fields: Cardholder, Card Number, Expiry, Security Code, PIN. Utilities in `VaultifyCore/Models/PaymentCard.swift` (brand detect, Luhn, formatting). Editors: `CardNumberFieldEditor`, `ExpiryFieldEditor`, `CardScannerSheet`.
- **BUG (live)**: `ProfileScreen` payment source uses `env.repository.items.filter { $0.category == .card }` — UNSCOPED → an anonymous persona's cards leak into another profile's picker. (Identities are correctly scoped; cards are not.)
- **User decision**: show a LIST of the active persona's cards (user may add several); scoped to the current profile only.

## Requirements
- New `PaymentCardsScreen`: persona-scoped LIST of `.card` items → each row = brand glyph + masked number (`•••• 4242`) + cardholder.
- Tap card → detail (masked fields, tap-to-copy/reveal, `Edit` via `ItemEditorScreen`) — or route to existing `ItemDetailScreen`.
- `Add card` → `ItemEditorScreen(target: .new(.card))` (+ `CardScannerSheet`).
- **Fix scoping**: source from `activePersonaItems.filter { $0.category == .card }` (or `items(for: persona)`), NEVER `repository.items`.
- `selectedPaymentCardId` (device-local): drop for a plain list, OR repurpose as an optional "default card" star. Recommend plain list for v1.

## Files
- New: `Vaultify/Features/Profile/PaymentCardsScreen.swift` (+ optional `PaymentCardRow`).
- Reuse: `PaymentCard` utils, card editors, `DetailFieldRow`.
- Modify: `ProfileScreen` (remove payment inline section).

## Validation
- `make check`.
- **Regression check**: create a card under an anonymous persona → it must NOT appear under another profile's Payment list.
- Add / edit / scan card works; fields masked by default.
