# Loox Membership V1 — client implementation plan

**Source contract:** [proposal-260714-2231-loox-subscription-strategy.md](../reports/proposal-260714-2231-loox-subscription-strategy.md)
**Status:** IMPLEMENTED 260716 (branch `feat/loox-membership-v1`) — phases 1–3 + 5 complete; phase 4 complete for 5 of 7 surfaces. Flag `LooxMembership.purchasesEnabled` remains OFF.
**Remaining before flag-flip (tracked in phase-04/phase-05):** outgoing-recipient seat gate (share-ceremony choke point needs its own scout), Free accent/theme subset with §8.3 preference preservation, §12 launch gates. ASC products CREATED 260716 (group 22241495; pending review screenshots + submit-with-version). Backend entitlement service proposal v3: `plans/reports/proposal-260716-1653-loox-entitlement-backend.md` — its B1–B6 rollout (client dormant → purchases → enforcement) governs the flag-flip order.
**Scope:** iOS client only — tier model, StoreKit 2 entitlements, Loox membership screen
(iCloud+-style redesign of `LooxHubScreen`), paywall, contextual feature gates, EN+VI.
**Out of scope (this repo, V1):** backend Loox Entitlement API, App Store Server
Notifications, server quota counters, win-back offers, Family SKU, reverse trial
(proposal §7.4, §6.2, §13). App Store Connect product creation is a manual owner task
(values frozen in §4 and phase 1).

## Naming decision (owner message 260716)

Display names: **Loox** (free) / **Loox+** (plus) / **Loox Max**. Product IDs keep
`plus` per proposal §4.2 (`com.bervion.vaultify.subscription.{plus|max}.{monthly|annual}`)
— IDs are permanent, display names are UI copy.

## Phases

| # | Phase | File | Depends on | Ships user-visible? |
|---|-------|------|-----------|---------------------|
| 1 | Entitlement foundation (tier model, StoreKit 2 store, flags, .storekit config) | [phase-01](phase-01-entitlement-foundation.md) | — | No |
| 2 | Membership hub redesign (iCloud+ vibe: tier header + member seal + feature grid) | [phase-02](phase-02-membership-hub-redesign.md) | 1 | **Yes — the focal ask** |
| 3 | Paywall (`SubscriptionStoreView`, Max Annual protagonist) | [phase-03](phase-03-paywall.md) | 1 | Behind `purchasesEnabled` flag |
| 4 | Contextual feature gates (personas, aliases, links, Quick View, recipients, Watchtower, themes) | [phase-04](phase-04-feature-gates.md) | 1, 3 | Behind flag |
| 5 | Quality: tests, EN+VI sweep, a11y matrix, docs, launch-gate checklist | [phase-05](phase-05-quality-and-launch.md) | 2–4 | — |

Phase 2 is independently shippable after phase 1: with the `purchasesEnabled` flag OFF
the hub renders the Free tier with real usage numbers and no purchase CTAs. Phases 3–4
stay dark until App Store Connect products exist.

## Key architecture decisions

- **Single source of truth for tier (client):** verified StoreKit 2
  `Transaction.currentEntitlements`, projected into `@Observable LooxEntitlementStore`
  on `AppEnvironment` (proposal §7.1 row 1). No CloudKit/UserDefaults tier authority.
- **Feature flag:** `LooxMembership.purchasesEnabled` static flag in `VaultifyCore`,
  mirroring the `WallpaperFeature.decorativeEnabled` pattern — paywall/upgrade entries
  compile always, render only when flag is on.
- **Quotas are a frozen table** (`LooxQuotas`, proposal §3.1) in `VaultifyCore`, pinned
  by unit tests. Client counters are display-only (§7.1); enforcement lands server-side
  later, out of repo scope.
- **No extension entitlement snapshot in V1:** everything AutoFill/Safari does is Free
  by principle §2.1–2.2, so nothing to gate there. Cut per YAGNI; §7.5's App Group
  snapshot becomes relevant only if a paid extension surface ever appears.
- **No entitlement failure may touch vault data** (§2.6) — gates only ever block a
  *create* action or hide a paid *view*; never delete/modify.

## Acceptance criteria (V1 client)

1. Fresh install ⇒ tier Free; hub shows "Loox" header, real usage counts, no paywall.
2. DEBUG tier override switches hub to Loox+ / Loox Max instantly (header title,
   seal, quota denominators) — simulator-testable without ASC.
3. With `.storekit` config: buying Max Annual flips tier to Max in-session and after
   relaunch; cancel/refund in the transaction manager drops back per §8.1 table.
4. Existing subscriber never sees an acquisition paywall (§5.3).
5. StoreKit product-load failure ⇒ retryable store state, vault untouched, no fake
   prices (§2.8 — no hardcoded USD/VND anywhere).
6. All new strings EN+VI; screens pass light/dark, Dynamic Type, VoiceOver, Reduce
   Motion/Transparency; 44pt targets; longest VI label doesn't clip.
7. `make check` green (app + AutoFill extension compile).

## Open questions (defaults chosen; owner can veto)

1. **Seal ring copy:** default EN `LOOX • MEMBER •` / VI `THÀNH VIÊN • LOOX •`,
   tier-independent (big title already names the tier); muted for Free, accent-tinted
   for paid. Confirm VI wording.
2. **Free accent subset** (§3.1 "Bộ accent/theme Cơ bản"): default free = blue,
   graphite, mono; Loox+/Max = all 7 presets. Confirm split.
3. **Quick View tile destination:** default reuses the share-links/notifications
   surface (`NotificationsScreen`) where Quick View history already appears; a
   dedicated screen is out of scope.
