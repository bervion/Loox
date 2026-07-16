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
- [ ] ASC: group + 4 products + EN/VI metadata, Max L1/Plus L2, Family Sharing OFF
- [ ] Intro offer 7d on Max Annual only; Billing Grace 16d paid-to-paid prod+sandbox
- [ ] `Loox.storekit` matrix pass (phase 3 list) + sandbox pass on device
- [ ] Subscriber never sees acquisition paywall; outage ≠ paywall state (§2.7)
- [ ] Free still identifies Critical/High Watchtower items
- [ ] Privacy Policy / App Privacy / About copy aligned (§10.1) — owner
- [ ] Only then: `LooxMembership.purchasesEnabled = true` + release via `make release`

## Out of scope reminders
Backend entitlement API, Server Notifications V2, server quota counters, win-back
offers, `appAccountToken` device sync (§7.3) — all later, outside this repo.
