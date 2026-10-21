# Phase 5 — Membership launch (`launchEnabled = true`)

**Decision, revised 2026-08-04 (R2 resolved):** attach the four IAPs to this submission and
keep `LooxMembership.launchEnabled = false`. Apple requires a first subscription to be
submitted *with* an app version; it does **not** require production purchases to be live on
day one. The flip is **gated, not scheduled**: it happens only after a **signed TestFlight
build** passes purchase and restore end to end together with the backend. If that is not
green before the tag, the release ships with the flag off.

**Superseded 2026-10-21 by owner decision:** commerce is live (`launchEnabled = true`). §5.4 records the offers and the complimentary Loox+ grant; §5.6 records the status of the remaining gates.

So this phase now has two halves:

- **In scope for this release** — everything the reviewer and the four attached products
  need: working policy links, correct product state in ASC, sandbox purchase/restore, and
  the paywall rendering completely.
- **Gated behind the E2E** — §5.6, the flag flip itself.

**Good news up front:** the purchase stack is genuinely done and sandbox-tested. Paywall,
restore, storefront repricing, in-hand-transaction tier grant and Ask-to-Buy all have
on-device fixes landed 2026-07-17. The backend is live-deployed on both staging and
production with a real Apple ASSN E2E verified. Roughly 3–6 focused dev days plus owner
ASC work.

---

## Backend gate status — B5 does **not** block the flip

The rollout order in `plans/reports/proposal-260716-1653-loox-entitlement-backend.md` §6 is
**client dormant → purchases on → enforcement**. Purchases go live at **B4** while the
backend stays `off`/`shadow`. `phase-05-quality-and-launch.md`'s checklist line saying the
backend must "reach its B5 gate" is superseded by its own parenthetical on the next line.

| Gate | Status | Evidence |
|---|---|---|
| B1-0 spike | DONE | Spike report; taxonomy pinned in `apple-verify.ts:1-18`; 13 tests green |
| B1 worker + reducer | DONE | `attach.ts:4-6` statuses-check before any grant; `webhook.ts` ASSN v2 verify→inbox→reducer; `migrations/0001` 10 tables append-only; 19 reducer tests green; real Apple ASSN TEST verified on staging |
| B2 RPC + grants/leases | PARTIAL | All code shipped and deployed (three named entrypoints, 22 quota/bind SQL tests green), but every worker runs `ENTITLEMENT_MODE=off` — never flipped to `shadow`. Coverage counters and Quick View staging `ASSERTION_MODE=required` still owed |
| B3 dormant client | DONE (code) / PARTIAL (gate) | Merged to iOS main at `04eb9f1a`, shipped v1.35.0 plus on-device fixes `2ac419e1`, `541c8739`. The coverage measurement has never run; the legacy-cohort snapshot has no recorded evidence |
| B4 purchases ON | **Flipped 2026-10-21** (client) | `launchEnabled = true` by owner decision. Backend stays `off`/`shadow` until observed (§5.6) |
| B5 enforcement canary | NOT STARTED | Mode `off` everywhere; C7 App Attest ladder for `/attach` pending |
| B6 wind-down | NOT STARTED | Separate migration + job, after B5 |

Backend deployment is real, not aspirational: staging and production D1 IDs provisioned,
custom domains `entitlement{-staging}.looxpassword.com`, all four Apple secrets loaded, ASSN
URLs configured in ASC. Known Apple behavior: the production App Store Server API returns
401 until the app is released — attach for production JWS self-heals post-release, and the
client's tier never depends on it (StoreKit-local authority,
`LooxEntitlementStore.swift:9-11`).

Both repos' entitlement branches are **merged**; nothing is stranded.

---

## Apple-compliance status of the purchase flow — verified

| Requirement | Status |
|---|---|
| Restore Purchases affordance | **Present.** `LooxAcquisitionPaywallView.swift:323` (`restore()` at `:473-496` via `AppStore.sync()`), and `LooxPaywallScreen.swift:115` `.storeButton(.visible, for: .restorePurchases)` |
| Title, length, price per period near the button | **Present.** `LooxAcquisitionPaywallView.swift:212-227` — live `displayPrice`, "a year / a month", per-month equivalent. Auto-renew and trial disclosure at `:379-386`. Nothing monetary is hardcoded |
| Terms + Privacy links on the purchase screen | **Present on the acquisition paywall** (`:188-195`) but the URLs 404 → Phase 1C. **Absent entirely on `SubscriptionStoreView`** (`LooxPaywallScreen.swift:113`) → Phase 1C item 2 |
| No data held hostage on lapse | **Clean.** Gates are create/approve-only by contract (`LooxGate.swift:10-13`, `LooxEntitlementStore.swift:22-23`). Vault items, read, copy, AutoFill and export are never gated. Watchtower keeps score, audit and every Critical/High finding free |
| In-app account deletion (5.1.1(v)) | **Not applicable.** No accounts. `appAccountToken` is an app-generated pseudonymous UUID in the Keychain; the onboarding name/email step is local-only |

---

## Work

### 5.1 — Wire the two deferred feature gates

Both were explicitly deferred by `phase-04` to "pre-flag-flip QA" and neither has a call
site today.

- **Outgoing-recipient seat gate.** `LooxGate.canAddOutgoingRecipient` exists
  (`LooxGate.swift:44-46`) but is never called; only 5 of 7 gate surfaces are wired. The
  share-ceremony choke point needs its own scout before wiring — do not guess at it.
  Effort M.
- **Themes gate + §8.3 stored-preference preservation on downgrade.** No `fullThemes` call
  site. Touches `ThemeStore.setAccent` and the accent picker. Effort S/M.

Both leak revenue if skipped and neither can harm a user, so the owner may consciously waive
them for the launch release. **Record the waiver if taken** — do not let it become an
undocumented gap.

### 5.2 — `binding_conflict` support surface

`LooxEntitlementCoordinator.apply()` currently drops it silently
(`guard auth.error == nil else { continue }`). Slated for B4 by `phase-06`. Small UI; the
owner may defer consciously.

### 5.3 — Run and record the §8.2 attach E2E

A real Sandbox purchase from a TestFlight build, verified end to end against the backend.
`phase-06` lists this as "verify before B4" and **no report exists in either repo**. If it
was run informally, record it; if not, it is a pre-flip task. Write the report to
`reports/`.

### 5.4 — ASC mechanics (owner)

**The four products.** Source of truth is `VaultifyCore/Subscription/LooxTier.swift:85-90`,
mirrored in `Loox.storekit`. Subscription group **"Loox Membership", id `22241495`**.

| Product ID | Reference name | Period | StoreKit price (USD tier) | Intro offer |
|---|---|---|---|---|
| `com.bervion.vaultify.subscription.max.annual` | Loox Max Annual | P1Y | 34.99 | **yes** — 1-year free trial (from 2026-10-21) |
| `com.bervion.vaultify.subscription.max.monthly` | Loox Max Monthly | P1M | 4.99 | **yes** — 1-year free trial (from 2026-10-21) |
| `com.bervion.vaultify.subscription.plus.annual` | Loox Plus Annual | P1Y | 19.99 | no |
| `com.bervion.vaultify.subscription.plus.monthly` | Loox Plus Monthly | P1M | 2.99 | no |

Prices above are the local StoreKit config, which is a **dev fixture, not ASC truth**.
Phase 5's checklist row on VN pricing records the values the owner kept
(Max Annual 349k, Max Monthly 49k, Plus Annual 199k, Plus Monthly 29k) against Apple's
comparable-price suggestions. Verify the live ASC values rather than trusting either file.

Group "Loox Membership" `22241495` exists with all four products. Owner-reported status on
2026-10-21:

- EN, VI and JA localizations are in place. All four products are priced in 175 territories.
- Max Annual and Max Monthly carry a **1-year free-trial intro offer** (175 territories, starts
  2026-10-21, no end date). It replaces the former 7-day offer. Plus products carry none.
- Annual availability is "1 Year Upfront". Monthly with a 12-month commitment is intentionally
  not configured. A 16-day billing grace was configured earlier.
- App Store Server Notifications V2 URLs are configured (Production and Sandbox).
- All four products are still **Prepare for Submission**.

Full ASC checklist: `docs/deployment-guide.md` §2b.

- **Complimentary Loox+ (not an Apple product).** Every install gets Loox+ quotas free for
  750 days from the first launch of the version that ships it. It is an in-app grant,
  device-local and never sent to the backend, because Apple's longest trial is 1 year.
  Owner decision 2026-10-21.
- Upload the review screenshot to **each** of the four products. Run the
  `Vaultify-StoreKit` scheme (purchase surfaces are on with `launchEnabled`; the DEBUG
  "Purchase Surfaces" toggle was removed), then Profile → Loox → Upgrade to Loox Max,
  capture on a 6.7" simulator. **TestFlight only loads products in "Ready to Submit" or
  later**, so this gates TestFlight testing too, not just submission.
- Submit the subscriptions **with** the new app version (first-subscription rule).

### 5.5 — Phase-05 QA rows still unchecked

- `Loox.storekit` matrix pass plus a sandbox pass on a real device.
- A subscriber never sees the acquisition paywall.
- A backend outage renders as an outage, never as a downgrade to Free (§2.7).
- Free still surfaces every Critical/High Watchtower finding.

### 5.6 — Flip the flag — flipped 2026-10-21 (owner decision); gates still open

`launchEnabled` is `true` in `VaultifyCore/Subscription/LooxMembership.swift` by owner
decision 2026-10-21.

**Status 2026-10-21.** Evidence on record: App Store Server Notifications V2 URLs configured
(Production and Sandbox); all four products priced in 175 territories; Max Annual and Max
Monthly 1-year intro offers configured. None of this closes a box below on its own. The
products are still Prepare for Submission, and production `ENTITLEMENT_MODE` has not been
observed. Boxes stay unticked until evidenced.

Waiver, not a §5.6 box (see §5.1): outgoing-recipient seats (`LooxGate.canAddOutgoingRecipient`)
and `fullThemes` have no call sites and are ungated. The Loox quota screen hides its Sharing
row. **Owner to confirm.**

Remaining gates:

- [ ] Terms and Privacy live, without placeholders, counsel signed off. **Pending:** counsel sign-off
- [ ] Four products in a submittable state in ASC with review screenshots. **Pending:** still Prepare for Submission on 2026-10-21
- [ ] Purchase and restore pass end to end on a **signed TestFlight build**, with the
      backend in the loop, and the run is recorded in `reports/`. **Pending**
- [ ] §8.2 attach E2E recorded (5.3). **Pending**
- [ ] Backend modes settled and observed, not assumed. **Pending:** production `ENTITLEMENT_MODE`
      must be observed as `off` or `shadow` before submission; under `enforce`, every
      complimentary user (who sends no lease) would move to Free
- [ ] Real-device matrix green. **Pending**

The policy-pages precondition is stated in `LooxMembership.swift`. Selling auto-renewing
subscriptions under placeholder terms is legal exposure independent of App Review, so the
Terms and Privacy box stays open until counsel signs off.

### 5.7 — After launch, not before

B4's 7-day paid-binding observation, backend coverage counters, `shadow` mode, the C7 App
Attest ladder, B5 canary, and B6 wind-down. Explicitly sequenced after purchases by the
proposal itself.

## Phase exit criteria

- [ ] Both purchase surfaces expose working Terms and Privacy links (Phase 1C)
- [ ] Terms include subscription, renewal, trial, grace and cancellation clauses (Phase 1B)
- [ ] Recipient-seat and themes gates wired, or waived with a recorded decision
- [ ] §8.2 attach E2E run against a TestFlight build and reported in `reports/`
- [ ] Four products Ready to Submit with review screenshots, attached to the version
- [ ] Sandbox purchase, restore, upgrade, downgrade and cancel all pass on a real device
- [ ] Outage ≠ downgrade verified
- [ ] `launchEnabled` is `true` in the submitted build (owner decision 2026-10-21, supersedes the 2026-08-04 hold). **Pending:** set in the working tree, not yet in a submitted build
- [ ] Remaining §5.6 gates closed with evidence. **Pending**
