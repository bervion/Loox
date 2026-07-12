# Phase 05 — Inline Menu + Cross-Origin Iframe CC + iPad

## Context Links

- Research: `plans/reports/from-research-260712-1453-safari-web-extension-plan-report.md` §4 (1P inline menu, suppression), §3.4 (iframe deny-by-default), §7 (inline vs QuickType conflict)
- 1P suppression precedent: [inline menu hidden when system AutoFill enabled](https://www.1password.community/1password-at-home-31/me-271-feedback-inline-menu-hidden-in-safari-on-ios-when-system-autofill-is-enabled-24290)
- Prereq: Phase 04 complete

## Overview

- Priority: P2 (v1-included per user decision, sequenced last among features — highest breakage risk, report §4 takeaway)
- Status: pending
- Field-anchored inline menu for **identity and card fields ONLY** (never credential fields — suppression rule is absolute on iOS), opt-in per-frame CC fill for cross-origin payment iframes (Stripe-class) with per-frame origin checks, and iPad destination enablement.

## Key Insights

- Inline menu scope is narrower than 1P desktop: iOS QuickType owns logins; our menu appears only on focus of a field classified `cc-*` or identity keys with tier 1-2 evidence. Tier-3-only pages get popup-driven fill, no inline (false-anchor risk).
- Menu must survive hostile pages: closed shadow root, position via `getBoundingClientRect` + scroll/resize observers, dismiss on outside tap, never intercept keystrokes, VoiceOver labels. Item TITLES only (e.g. "Personal · Visa 4242" — wait: "·" banned in copy → use "Visa 4242, Personal" layout separation) — no field values in the menu DOM until user taps.
- Iframe CC: flip `all_frames: true` for content scripts BUT fill-engine refuses any frame whose `location.origin` is not (a) the top origin or (b) an allowlisted payment processor origin (initial allowlist: `js.stripe.com`, `checkout.stripe.com`, `pay.google.com` — data constant, reviewed in P6). Background addresses frames by `frameId`; payload for an iframe fill carries the expected frame origin and the frame self-verifies before writing (both sides check).
- Tapping an inline menu entry triggers the SAME native `getFillPayload` path (Face ID) — inline is a different entry point, not a different trust path. No payload pre-fetch on focus.
- iPad: add `.iPad` to destinations + `TARGETED_DEVICE_FAMILY: "1,2"` on the appex; popup renders as popover — verify layout at both size classes.

## Requirements

- Functional: focus on eligible field → compact anchored menu listing matching items (metadata only) → tap → Face ID → fill (existing engine). "Open Loox" row deep-links `vaultify://` for management. Iframe CC fill works on a Stripe test checkout.
- Non-functional: menu inject/anchor < 100ms; zero layout shift for page content (position: fixed overlay); EN+VI; Reduce Motion respected (no entrance animation when set — media query `prefers-reduced-motion`).

## Architecture

```
inline-menu.js   # anchor lifecycle, shadow-DOM menu, focus/blur orchestration
(fill-engine.js) # + frame-origin verification branch
(manifest.json)  # content_scripts.all_frames: true; matches unchanged
```

**Data flow (inline fill):** field focus → classifier verdict (cached from page scan) eligible → content asks background `listItems(origin)` IF not cached this page-load (metadata cache: background memory, per-tab, cleared on navigation) → menu renders titles → user tap → `getFillPayload` (Face ID) → fill via engine (frame-verified) → menu dismiss + payload cleared.

## Related Code Files

- Create: `VaultifySafari/Resources/inline-menu.js`, iframe fixture under `VaultifySafari/DevFixtures/` (cross-origin simulated via localhost ports where possible; real Stripe test page for device QA)
- Modify: `manifest.json` (`all_frames: true`), `content.js`, `fill-engine.js` (frame checks), `background.js` (frameId routing + per-tab metadata cache), `_locales/en|vi`, `Project.swift` (appex `destinations: [.iPhone, .iPad]`, `TARGETED_DEVICE_FAMILY: "1,2"`)
- Read: `plans/reports/from-research-260712-1453-safari-web-extension-plan-report.md` §3

## Implementation Steps

1. Per-tab metadata cache in background (memory only, invalidated on `tabs.onUpdated` navigation) so inline menu doesn't Face-ID on every focus — Face ID only at fill.
2. `inline-menu.js`: eligibility (tier 1-2 identity/CC fields only), anchor + reposition, dismissal rules, accessibility labels, EN+VI.
3. Enforce credential suppression in code: menu never attaches to `password`/`username`/`current-password`/`new-password` classified fields (assert in classifier consumer + fixture test page with a login form must show NO menu).
4. `all_frames: true` + frame-origin verification in fill-engine (both background pre-check by `frameId`→origin and in-frame self-check); payment-processor allowlist constant.
5. iPad: Project.swift destinations change, `tuist generate`, popup/popover layout pass, menu on iPad pointer + touch.
6. Device QA **G5**: top-20 sample = 8 checkout pages (≥2 Stripe-iframe), 6 address/signup forms, 3 VI sites, 3 login-only pages (expect NO inline UI). Record pass/fail table here.
7. `make check` + `make test` (frame-verification logic mirrored in a Swift routing test where applicable).

## Todo List

- [ ] Per-tab metadata cache (memory, navigation-invalidated)
- [ ] Inline menu with tier 1-2 eligibility + a11y + EN+VI
- [ ] Credential-field suppression asserted by fixture
- [ ] all_frames + dual-side frame-origin checks + allowlist
- [ ] iPad enablement + layout pass
- [ ] G5 site matrix recorded
- [ ] make check/test green

## Success Criteria

- Inline menu appears ONLY on identity/CC fields (login fixture shows none); fill parity with popup path; Stripe test checkout CC fill succeeds via allowlisted frame; non-allowlisted cross-origin frame refused (fixture-proven); iPad popup usable; G5 ≥ 17/20 pass with failures triaged (fix or documented site quirk).

## Risk Assessment

| Risk | L×I | Mitigation |
|---|---|---|
| Inline menu breaks page layout/JS on some sites | High×Med | Fixed-position shadow root, no DOM mutation of page tree; per-site kill switch: long-press menu → "Hide on this site" (host list, shared defaults, reuses neverSave storage shape) |
| Menu anchored to spoofed/moving field | Med×Med | Re-verify classification + visibility at tap time (fill-moment checks unchanged) |
| Iframe allowlist too permissive/stale | Med×High | Small initial list, data constant, P6 security review owns it; default deny everything else |
| Metadata cache leaks across origins | Low×High | Cache keyed by tabId+origin; navigation invalidation; metadata only (no values) |
| iPad regressions in app target | Low×Med | Appex-only destination change; app target untouched |

## Security Considerations

- Inline path shares the single payload-issuing cmd (`getFillPayload`) — no new trust surface natively. Menu DOM contains titles/last-4 only. Frame fills double-checked (background + in-frame). Cache is metadata-only, memory-only.

## Next Steps

- P6 security review audits: allowlist, suppression assertions, payload lifetimes, protocol fuzzing; then release readiness (match profiles, App Store notes).
