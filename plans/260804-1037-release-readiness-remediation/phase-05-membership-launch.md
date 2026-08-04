# Phase 5 — Membership launch (`launchEnabled = true`)

Per D3, subscriptions ship live to real users in this release, not merely attached for
review. This phase is the difference between "reviewer can buy in sandbox" and "customers
can buy".

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
| B4 purchases ON | **NOT STARTED** | `launchEnabled = false`; purchases open only in beta env via `betaPurchaseAccess` |
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

Group "Loox Membership" `22241495` exists with all four products and EN/VI metadata; intro
offer (7-day trial on Max Annual) and 16-day billing grace are configured.

- Upload the review screenshot to **each** of the four products. Run the
  `Vaultify-StoreKit` scheme, flip Settings → Debug → "Purchase Surfaces" ON (no code flip
  needed), then Profile → Loox → Upgrade to Loox Max, capture on a 6.7" simulator.
  **TestFlight only loads products in "Ready to Submit" or later**, so this gates TestFlight
  testing too, not just submission.
- Submit the subscriptions **with** the new app version (first-subscription rule).
- Confirm current product state in ASC. Repo evidence is ambiguous — the checklist says
  screenshots pending, but on-device sandbox purchases succeeded on 2026-07-17, which
  suggests they may already be past "Missing Metadata". **Verify, do not assume.**

### 5.5 — Phase-05 QA rows still unchecked

- `Loox.storekit` matrix pass plus a sandbox pass on a real device.
- A subscriber never sees the acquisition paywall.
- A backend outage renders as an outage, never as a downgrade to Free (§2.7).
- Free still surfaces every Critical/High Watchtower finding.

### 5.6 — Flip the flag

`VaultifyCore/Subscription/LooxMembership.swift:17` → `launchEnabled = true`, then release.
Do this **last**, after Phase 1's Terms and Privacy are live and legally reviewed —
`LooxMembership.swift:19-20` makes that a stated precondition, and selling auto-renewing
subscriptions under placeholder terms is legal exposure independent of App Review.

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
- [ ] `launchEnabled = true` committed only after the policy pages are live and signed off
