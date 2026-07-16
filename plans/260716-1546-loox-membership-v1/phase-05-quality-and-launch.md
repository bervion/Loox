# Phase 5 — Quality, localization, docs, launch gates

**Goal:** everything §12 requires from the *client* before the flag can ever flip,
plus repo docs kept honest.

## Work

### Tests (beyond phase-local ones)
- `VaultifyTests/LooxSubscriptionStateTests.swift`: §8.1 state table as a pure
  mapping test — (apple state) → (expected Loox behavior class: full / keep-until-
  expiry / block-new-premium / free). Extract that mapping into
  `VaultifyCore/Subscription/` so it's testable and the UI reads it.
- Full suite green on booted sim; `make check` (app + extension).

### Localization + a11y sweep
- Audit every new string in `Localizable.xcstrings`: EN source + VI value present
  (missing VI = bug, CLAUDE.md). Copy rules: no "!", no "—", no "·" in sentence copy.
- Matrix per design-dna-standard: light/dark, Reduce Motion/Transparency, increased
  contrast, Dynamic Type (largest), VoiceOver labels on seal-adjacent header, tiles,
  paywall; 44pt targets; longest-VI-label layout.

### Docs (documentation-management rules — read before editing)
- `docs/codebase-summary.md`: subscription layer (tier model, entitlement store,
  flag, hub redesign).
- `README.md`: soften absolute claims per §1.2 ("zero backend", "no subscription")
  ONLY when the flag actually flips — until then add nothing user-facing; leave a
  TODO note in the plan, not the README.
- This plan's `plan.md` status updates per phase.

### Launch-gate checklist (client rows of §12 — owner-driven, tracked here)
- [x] ASC: group + 4 products + EN/VI metadata, Max L1/Plus L2, Family Sharing OFF
      — DONE 260716. Group "Loox Membership" id **22241495** (recorded in
      `LooxProductID.subscriptionGroupID` + synced into `Loox.storekit`).
      All four products "Missing Metadata" pending ONLY the review screenshot.
      Apple comparable-price suggestions for VN (recorded per §4.3, ours kept):
      Max Annual đ999k→**349k**, Max Monthly đ149k→**49k**,
      Plus Annual đ599k→**199k**, Plus Monthly đ99k→**29k**.
- [x] Intro offer 7d on Max Annual only (free trial, 1 week, 175 countries, no
      end date); Billing Grace 16d paid-to-paid prod+sandbox — DONE 260716.
- [ ] Review screenshot (paywall image) uploaded to each of the 4 products —
      run the `Vaultify-StoreKit` scheme in Xcode, flip Settings → Debug →
      "Purchase Surfaces" ON (no code flip needed), then Profile → Loox →
      Upgrade to Loox Max; capture on a 6.7" simulator.
      NOTE: TestFlight only loads products in "Ready to Submit" or later, so
      screenshots gate TESTFLIGHT TESTING too, not just submission.
- [ ] First subscription submits WITH a new app version (ASC warning noted).
- [ ] `Loox.storekit` matrix pass (phase 3 list) + sandbox pass on device
- [ ] Subscriber never sees acquisition paywall; outage ≠ paywall state (§2.7)
- [ ] Free still identifies Critical/High Watchtower items
- [ ] Privacy Policy / App Privacy / About copy aligned (§10.1) — owner;
      Terms + Privacy pages must be live at looxpassword.com/terms + /privacy
- [ ] Backend entitlement service per
      `plans/reports/proposal-260716-1653-loox-entitlement-backend.md` (v3)
      reaches its B5 gate (enforcement active) — flag-flip rollout order is
      defined THERE (client dormant → purchases on → enforcement) and
      supersedes any earlier phase ordering here.
- [ ] Only then: `LooxMembership.purchasesEnabled = true` + release via `make release`

## Out of scope reminders
Backend entitlement API, Server Notifications V2, server quota counters, win-back
offers, `appAccountToken` device sync (§7.3) — all later, outside this repo.
