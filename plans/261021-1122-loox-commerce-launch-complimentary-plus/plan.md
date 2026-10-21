# Loox commerce launch + 750-day complimentary Loox+

Owner request 2026-10-21: "Bật full" commerce; Loox+ free 750 days, Loox Max free 365 days.
Detailed spec: [spec.md](spec.md). Root-cause report: `plans/reports/debugger-261021-1050-loox-hub-hidden-on-app-store.md`.

## Decisions
- Apple caps free trials at 1 year and one intro offer per group, so Loox+ 750 d = IN-APP grant (no StoreKit, no card), Max = Apple 1-year free trial on Annual AND Monthly.
- Grant start = first launch of the shipping version, device-local Keychain (`loox-complimentary-start-v1`, add-only), never sent to backend.
- Heavy users above Loox+ caps: data kept, upsell on next create (no Max floor).
- `PrivacyInfo.xcprivacy`: Purchase History declared LINKED (attach binds subscription account to relay principal).

## Status
| Phase | Status |
|---|---|
| Root cause (hub hidden on App Store) | Done |
| ASC: Max Annual 1-week offer replaced, Max Annual + Monthly 1-year free trial, 175 territories | Done 2026-10-21 |
| ASC: availability all 175 territories (4 products), JA localizations (4 products) | Done 2026-10-21 |
| Code: launch flip, grant, tier split, paywall trial for both Max, hub plan section, DEBUG menu, analytics, privacy | Done (uncommitted) |
| Verify: `mise exec -- make check`; VaultifyTests 1484 pass / 0 fail | Done |
| Verify: snapshots 8 fail = same 8 as `main` (pre-existing, machine-dependent) | Done |
| Adversarial review (4 lenses + skeptic verify): 1 major + 3 minor, all fixed | Done |
| Docs: codebase-summary, deployment-guide, phase-05 | Done |
| ASC: group JA name, review screenshots, attach subs to next version, App Privacy (Purchase History linked), review notes, submit | Pending |
| Owner: accept new Paid Apps Agreement (Account Holder) | Pending |
| Backend: confirm prod `ENTITLEMENT_MODE` off/shadow; server-side complimentary rule before enforcement | Pending |
| Release: commit, PR, merge, `make release`, TestFlight | Pending owner OK |

## Unresolved
- Prod `ENTITLEMENT_MODE` value (backend repo not local).
- Legal: Terms clause for complimentary 750 days (per device) + 1-year Max trial.
