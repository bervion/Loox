# Phase 3 — Paywall

**Goal:** the §5 purchase surface — Loox merchandising above, native
`SubscriptionStoreView` below. Max Annual is the protagonist. Entirely behind
`LooxMembership.purchasesEnabled` until ASC products exist.

**Context:** proposal §5 (spec), §6.1 (trial), §2.8 (StoreKit-only prices), §5.3
(context rules). Deployment target 17.3 — `SubscriptionStoreView` is iOS 17.0+ ✓;
avoid 18+ control styles without `#available` (CI stable-Xcode ceiling).

## Files

### Create — `Vaultify/Features/Subscription/LooxPaywallScreen.swift`
- `LooxPaywallContext` enum: `.profile, .personaLimit, .aliasLimit, .linkQuota,
  .quickViewQuota, .recipientLimit, .watchtower, .themes` — picks the one-line
  context header; no other behavioral difference (keeps App Review deterministic).
- Layout per §5.1, top→bottom:
  1. Merchandising header: `BrandSymbol` / seal, short title naming the offer.
  2. Three Max benefits with Polaris icons: Private Email, secure sharing, full
     security maintenance (Watchtower). Concrete copy, no superlatives.
  3. `SubscriptionStoreView(groupID:)` for the "Loox Membership" group — StoreKit
     renders plan choice (Plus/Max), period picker (default YEAR — verify default
     selection API on 17.3; if the default-select-Max-Annual control isn't reachable
     at 17.3, fall back to `SubscriptionStoreView(productIDs:)` ordered Max-first;
     decide at impl, note in code why),
     `.subscriptionStoreControlStyle` chosen for one filled primary action,
     `.storeButton(.visible, for: .restorePurchases)`,
     `.subscriptionStorePolicyDestination(url:for:)` Terms + Privacy.
  4. Renewal disclosure under the action (StoreKit supplies pricing/trial text from
     live `Product`s — never hardcode price or "7 days" eligibility; §5.2, §6.1).
- Trial button copy follows eligibility automatically via StoreKit; if custom copy is
  ever needed, gate on `Product.SubscriptionInfo.isEligibleForIntroOffer`.
- Purchase completion: rely on `LooxEntitlementStore`'s `Transaction.updates` listener
  (single grant path); on success dismiss + subtle success haptic (`Haptics` vocab).
  Handle pending (Ask to Buy) with a calm "pending" note; user-cancelled silently;
  failure with retry, never implying vault risk (§5.4).
- **Subscriber guard:** if `tier != .free` on appear, render manage-style content
  (current plan + Manage subscription), never the acquisition pitch (§5.3).
- Comparison line "Max Annual ≈/< Plus Monthly per-month" ONLY when computed true from
  live `Product.price` decimals (§4.3) — computed, else hidden.

### Modify — call sites
- Hub (phase 2): free upgrade card + "Change plan" present this screen (sheet).
- Gate sheets (phase 4) present it with their context.

## Tests
- Pure helpers extracted + unit-tested: per-month price math from `Decimal` (year/12,
  currency-preserving display via `Product.priceFormatStyle` at call site), comparison
  eligibility (`maxAnnualPerMonth <= plusMonthly`), context → header copy mapping.
- Manual matrix on `Loox.storekit`: buy each product, upgrade Plus→Max, downgrade
  Max→Plus (pending state renders §8.1 row), cancel, refund via transaction manager,
  restore, interrupted purchase, Ask to Buy.

## Validation
- `make check`; EN+VI; light/dark; a11y matrix; §5.2 checklist walked item-by-item
  against a screenshot before calling done.

## Risks / notes
- `SubscriptionStoreView` visual customization at 17.3 is limited — accept native
  look below the merchandising header rather than fighting it (proposal explicitly
  prefers native purchase surface).
- Do not create ASC products from code/CI; owner creates them per §4.2/§12 checklist.
  Until then everything stays behind the flag; the `.storekit` file is the only
  product source in dev.
