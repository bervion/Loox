---
title: Code Review — Loox Membership V1 client
branch: feat/loox-membership-v1
reviewer: code-reviewer
date: 2026-07-16
plan: plans/260716-1546-loox-membership-v1/plan.md
contract: plans/reports/proposal-260714-2231-loox-subscription-strategy.md
scope: git diff --cached (31 files, +2214/-23)
verdict: 8.5/10 — DONE_WITH_CONCERNS (advisory; no code changed)
---

# Code Review — Loox Membership V1 client

## Scope

- 31 staged files, +2214 / -23. New: `VaultifyCore/Subscription/` (4), `Vaultify/Services/Subscription/LooxEntitlementStore.swift`, `Vaultify/Features/Subscription/` (2), Profile seal/tile (2), `Loox.storekit`, 4 tests, 5 plan/phase docs. Modified: 5 gated flows + hub + AppEnvironment + Settings + Project.swift + xcstrings + docs.
- Focus: flag-off regression safety, public contracts, extension-safety, localization, StoreKit correctness, gate logic.
- Verified independently: EN+VI catalog completeness (34 keys), Tuist scheme autogeneration model, StoreKit API availability vs the 17.3 floor, `memberName` duplication claim.

## Overall Assessment

Strong, disciplined work. The launch flag is genuinely airtight: every gate is written as `if LooxMembership.purchasesEnabled, case .needsUpgrade = …` or `guard purchasesEnabled else { return proceed() }`, so with the flag OFF the second operand (`env.entitlements.tier`, quota math) is never even evaluated — the gates are zero-cost and behavior is byte-identical to pre-change. Localization is complete (all 34 new user-facing keys carry EN+VI). Tests are real and pin the commercial contract, not the implementation. No vault-data path is touched anywhere. No existing public contract or schema changed. The findings below are refinements and one plan/acceptance reconciliation, not defects that block the (already-dark) feature.

## Critical Issues

None.

## High Priority

None.

## Medium Priority

### M1 — Acceptance criterion 2 (denominators under DEBUG override) is only partially met; the denominator UI + string paths are currently unreachable at runtime
`Vaultify/Features/Profile/LooxHubScreen.swift:197-215`

Plan acceptance criterion 2 says the DEBUG tier override must flip "header title, seal, **quota denominators**." The override flips header title (`tier.displayName`) and seal tint, but denominators are gated on `LooxMembership.purchasesEnabled` (currently false), not on tier:

```swift
private func usageMetric(_ used: Int, of cap: Int?) -> String {
    if LooxMembership.purchasesEnabled, let cap { return appString("\(used) of \(cap) in use") }
    return appString("\(used) in use")
}
```

Consequences with the flag OFF (the committed state):
- Toggling the Settings override to Loox+/Max changes the title + seal but the grid still reads "N in use" / "N in 30 days" / "Full protection" — the criterion's denominators do not appear.
- The denominator/Essentials string paths (`"%lld of %lld in use"`, `"%lld of %lld in 30 days"`, `"Essentials"`) are therefore not reachable in any dev or shipping configuration without also editing the source flag, so they are effectively untested at runtime (unit tests only cover the pure `LooxTier`/`LooxGate` layer, not these view strings).

This is a *deliberate* product choice (comment: "showing a quota denominator while nothing enforces it would lie") that conflicts with the written criterion. Per the review rules I'm flagging it for the lead to reconcile rather than asserting the code is wrong. Two clean options: (a) in DEBUG, gate denominators on `(LooxMembership.purchasesEnabled || debugTierOverride != nil)` so the override exercises the path and satisfies the criterion; or (b) amend criterion 2 to state denominators intentionally stay hidden until the flag flips. Same applies to `watchtowerMetric` (`:211-215`) and `rollingMetric` (`:204-209`).

## Low Priority

### L1 — `.font(.system(size:))` in the member seal violates the "never `.font(.system(size: N))`" token rule
`Vaultify/Features/Profile/LooxMemberSeal.swift:20`

`.font(.system(size: diameter * 0.105, weight: .semibold))` is a raw system-size font, which the design system forbids (Dynamic Type). It is defensible here — the view is `.accessibilityHidden(true)`, purely decorative, and a circular ring layout can't reflow under Dynamic Type — but the exemption isn't called out the way `Font.vaultCode` is in CLAUDE.md. Recommend a one-line "// exempt from Dynamic Type: decorative, accessibilityHidden ring geometry" so a future audit doesn't re-flag it.

### L2 — Magic-number spacing in the feature tile
`Vaultify/Features/Profile/LooxFeatureTile.swift:47` uses `VStack(spacing: 2)`; `LooxMemberSeal` uses bespoke constants (`diameter: 68`, `lineWidth: 0.75`, ratio multipliers). The seal ratios are acceptable for a one-off decorative stamp, but `spacing: 2` between title and metric should be a token (there is no 2pt token; `Space.s1` is 4). Minor.

### L3 — Multiple stacked `.sheet` modifiers on one view
`PersonaSwitcherScreen.swift:41` adds `.sheet(item: $paywallContext)` immediately after `.sheet(item: $editorTarget)`; `WatchtowerScreen.swift:128` stacks a third sheet. Multiple sibling `.sheet` modifiers only behave independently on iOS 16+. Fine at the 17.3 floor and inert while the flag is off, but note the pattern. (In `QuickLinkView`/`QuickViewApprovalSheet` the paywall sheet is attached to a subview button, so it's isolated — good.)

### L4 — Approval-Mode row icon changed as part of the redesign
`LooxHubScreen.swift:229` uses `Icons.shieldPerson` where the old hub used `Icons.shield`. Reachability/binding/confirmation are unchanged (verified against the pre-change file), so this is an intentional visual redesign detail, not a regression — noting only because the task asked for "exactly as before."

## Informational / Verified-safe (cite in future reviews)

- **Flag-off regression: clean across all five touched flows.** Walked each call site against its pre-change form. Persona create (`PersonaSwitcherScreen.attemptCreate`), alias create both flows (`PersonaAliasesScreen.guardQuota`), link create (`QuickLinkView.createButton`), Quick View approve (`QuickViewApprovalSheet`, gate sits pre-`flow.approve()` so biometrics still run exactly as before), and Watchtower nav (`openCategory`) all short-circuit on `purchasesEnabled` and fall through to the identical original action. The always-present `.sheet(item: $paywallContext)` modifiers never fire (context stays nil). Hub reachability preserved: Private Email → `PersonaAliasesScreen`, Share Links → `NotificationsScreen`, Approval Mode toggle (same `approvalModeEnabled` binding + confirmation) all intact; `planSection` is correctly hidden while the flag is off.
- **Extension-safety confirmed (checklist d).** `Project.swift:241` globs `VaultifyCore/**` into the Safari appex (and `:197` into AutoFill). All four `VaultifyCore/Subscription/*.swift` import Foundation only and are `nonisolated`/`Sendable` — no StoreKit/SwiftUI/UIKit, no MainActor requirement — so they compile cleanly into both extensions. `LooxEntitlementStore` (imports StoreKit, `@MainActor`) correctly lives in the app-only `Vaultify/Services/` tree, not in Core.
- **Public contracts intact (checklist c).** Only additive change to an existing type: `AppEnvironment` gains `let entitlements` + an `entitlements.start()` call in init. No signature/schema/enum-case change to any existing type.
- **Tuist scheme addition will not break CI (checklist c).** `Project.options` does not pass `automaticSchemesOptions`, so autogeneration stays at Tuist's default (enabled); the explicit scheme is named `Vaultify-StoreKit` (distinct from `Vaultify`), so the autogenerated `Vaultify` scheme is preserved. `Makefile SCHEME := Vaultify` and `Fastfile SCHEME = "Vaultify"` both resolve. `Loox.storekit` is referenced only in the scheme `runAction` — not a target resource, so it never ships in the app bundle. Recommend a one-time `xcodebuild -list` after `tuist generate` on the runner to confirm both schemes emit (I could not run `tuist generate`).
- **StoreKit availability OK at the 17.3 floor (checklist f), with one caveat.** `SubscriptionStoreView`, `subscriptionStoreControlStyle(.prominentPicker)`, `storeButton(.visible, for: .restorePurchases)`, `subscriptionStorePolicyDestination(url:for:)`, `onInAppPurchaseCompletion` are all iOS 17.0 APIs; `manageSubscriptionsSheet` is iOS 15+ and is correctly `#if os(iOS)`-split with a macOS `Link` fallback. Caveat: `make check` runs on the dev machine's Xcode 27 beta SDK, which masks availability against the stable-Xcode CI SDK (the exact trap CLAUDE.md calls out). All APIs used are 17.0, so the stable-Xcode build should pass — but this is the one item I could not runtime-verify; confirm the paywall compiles on the CI runner before flag-flip.
- **Entitlement failure never touches vault data (criterion, §2.6).** `LooxEntitlementStore` only ever writes `storeTier`; `LooxSubscriptionState.behavior` has no data-deletion behavior (`undetermined → keepLastVerified`); gates only block a create or hide a paid view. No vault mutation anywhere in the diff.
- **Entitlement store logic sound (checklist g).** `refresh()` filters `.verified` + `revocationDate == nil`, `resolveTier` is highest-wins (tested both orders); `Transaction.updates` primed-then-listened for process lifetime with `finish()` after recompute (single grant path; paywall's `onInAppPurchaseCompletion` is feedback-only, correctly does not finish). `[weak self]` avoids a retain cycle; `start()` is idempotent. No spurious downgrade risk: `currentEntitlements` is local device state, not network-dependent.
- **Subscriber guard correct (criterion 4).** `LooxPaywallScreen` renders `LooxCurrentPlanView` when `tier > .free`, acquisition otherwise — an existing subscriber never sees the acquisition pitch.
- **No hardcoded prices in app code (criterion 5).** Prices come from live `Product`s; `LooxPriceMath` operates on `Decimal` inputs; a product-load failure returns `.notComparable` and hides the line. The only literal prices live in `Loox.storekit` (dev-only StoreKit config), which is acceptable.
- **`LooxSubscriptionState` is defined + pinned by tests but not yet consumed** by `LooxEntitlementStore` (the store relies on local `currentEntitlements` semantics instead). Expected per plan — it's the frozen contract for the later backend-projection phase, not dead code.
- **Device-local quota counts are approximations by design.** `linkCreates30d` / `quickViewCompletions30d` / `outgoingRecipientCount` (hub + `QuickLinkView`/`QuickViewApprovalSheet`) may diverge from the "never refunds a revoked/expired slot" rule if revoked records are pruned from the local stores. Acceptable for V1 — inert now, and the backend counter is the stated enforcement authority.
- **`memberName` duplication verified.** `LooxHubScreen.swift:121` matches `ProfileScreen.swift:21` byte-for-byte (`fields.first(where: { $0.label == "Full Name" })?.value`). Consistent with existing behavior; not a new locale-label concern.
- **Localization complete.** All 34 new keys resolve with non-empty `vi` values (interpolations map to `%lld`/`%@` keys as expected); no forbidden `!` / `—` / `·` in any new EN/VI copy; the seal ring `•` is decorative and `accessibilityHidden`.

## Recommended Actions

1. Reconcile M1 with the lead: either unlock denominators under the DEBUG override (so criterion 2 is met and the string paths are exercised) or amend the criterion.
2. Before flag-flip: confirm the paywall compiles on the stable-Xcode CI runner (not just the beta-SDK `make check`), and run `xcodebuild -list` post-`tuist generate` to confirm both `Vaultify` and `Vaultify-StoreKit` schemes emit.
3. Optional polish: L1 exemption comment, L2 token for the 2pt gap.

## Metrics

- Type safety: strong — all Core types `nonisolated`/`Sendable`, no `any`/force-casts introduced (`URL(string:)!` on static valid literals only).
- Test coverage: 4 new suites pin tier ordering, the frozen quota table, product-ID allowlist, gate boundaries (all tiers), price-math thresholds, and the §8.1 state table incl. CaseIterable exhaustiveness. Pure-logic layer well covered; view-string paths (M1) uncovered.
- Localization: 34/34 new keys EN+VI.
- Linting/style: 2 minor token deviations (L1, L2).

## Unresolved Questions

1. M1 — is the denominator-hidden-until-flag behavior the intended final state (amend the plan), or should the DEBUG override unlock it?
2. Paywall compilation on the stable-Xcode CI SDK is unverified from this environment (beta SDK masks availability) — needs a runner build before flag-flip.

Status: DONE_WITH_CONCERNS
Summary: Flag-off inertness is airtight across all five gated flows and the hub redesign preserves reachability; localization, tests, contracts, and extension-safety all check out. One acceptance-criteria reconciliation (DEBUG override does not surface quota denominators, leaving that UI/string path unreachable and untested) plus minor token nits.
Concerns/Blockers: M1 (denominator path vs criterion 2) needs a lead decision; confirm the paywall builds on the stable-Xcode CI runner before flipping `purchasesEnabled` (dev-side `make check` runs on a beta SDK that masks iOS availability).
