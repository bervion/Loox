# Phase 06 — Security Review + Hardening + Release Readiness

## Context Links

- Research: `plans/reports/from-research-260712-1453-safari-web-extension-plan-report.md` §3 (security model), §7 (pitfall table)
- Release runbook: `docs/deployment-guide.md` (fastlane match, self-hosted runner) — updated this phase with the 3rd-appex delta
- Deferred findings source: `plans/reports/from-code-reviewer-260712-2312-safari-signup-assist-review-report.md` (L4/L5/L6), `from-code-reviewer-260712-2355-safari-inline-menu-review-report.md` (per-site kill switch)
- Prereq: Phases 01-05 complete (all merged to main)

## Overview

- Priority: P1 (release-blocking)
- Status: **code complete (260713)** — `make check` + `make test` green (716/716), node harnesses green. Remaining items are USER-OWED: portal/match signing steps + the consolidated device-QA checklist below.
- Adversarial review of the whole extension against the security invariant, protocol fuzz tests, per-site kill switch, token palette pass, deferred-Low hardening, macOS deferral note, signing/CI, docs sync.

## Delivered this phase

1. **Per-site kill switch ("Hide on this site")** — per-host list in shared App Group defaults (`web_extension_hidden_hosts`, bare hostnames only). Native gate runs BEFORE any session/key access: `listItemsSession` → `hiddenSite` (no inline menu), `saveGate` → `offer:false` and `saveLogin` → `forbidden` (no save overlay, belt included). Popup-driven fill deliberately stays available (explicit user surface). Toggle surfaces: popup footer (hide + show, consent-bound to the displayed origin) and inline-menu footer (HIDE-only — a page can never re-enable UI the user turned off; abuse only removes our UI from the abuser's own host). Fail safe: the content script latches `hiddenForPage` immediately on tap even if the native round trip fails. EN+VI in `_locales`. Tests: `WebExtensionSiteVisibilityTests` (10).
2. **Palette → design tokens** — `save-overlay.js`, `inline-menu.js`, `popup.css` now mirror `Design System/tokens/colors.css` + `elevation.css` values (surface-elevated, text-primary/secondary, accent, on-accent, surface-pressed, separator, elevation-3/sheet shadows), light + dark via `prefers-color-scheme`, token names documented inline. No ad-hoc hex remains where a token exists.
3. **Deferred Lows** — L4: overlay Save button arms after 600 ms (`SAVE_ARM_DELAY_MS`) so a page-layered `pointer-events:none` decoy cannot bait an instant tap onto Save; overlay stays brand-titled + max z-index. L5: "Never for this site" now awaits the native write, shows a failure status, and re-enables for retry instead of fire-and-forget. L6 = the palette pass above.
4. **Protocol fuzz suite** — `VaultifyTests/WebExtensionRouterFuzzTests` (7): malformed shapes, version gate, unknown cmds, 1 MB payload bounding, hostile origins across all origin-taking cmds (all rejected before unlock/session), confusable-host property, and a serialized-response sweep proving `getFillPayload` stays the only value-returning command.
5. **Signing/CI** — `Fastfile` + `Matchfile` now carry `com.bervion.vaultify.safari` (match sync, manual signing, export profile map). Portal + match regen + beta dry-run are user-owed (runbook: deployment-guide §1 "Adding the Safari web extension appex").
6. **Docs sync** — codebase-summary (new Safari section), deployment-guide (3rd-appex runbook), README (target + structure), CLAUDE.md (three targets, `_locales` EN+VI rule, bridge-invariant don't).

## Review checklist — verdicts (260713)

1. **Bridge audit** — PASS. Grep + code walk: `getFillPayload` is the only cmd whose response carries field values; `copyValue` releases only native-whitelisted non-secret kinds; `listItems`/`listItemsSession` metadata only (no logins on the inline variant); no decrypt outside `WebExtensionReader`. Test-enforced by the fuzz sweep + `testSaveLoginResponseNeverEchoesThePassword` + `testRouterResponseCarriesNoUnrequestedSecrets`.
2. **Protocol fuzz** — PASS (suite added, green; rejections asserted before unlock).
3. **JS hygiene** — PASS. Grep of shipped JS: `console.`/`eval`/`innerHTML`/`browser.storage`/`localStorage`/`document.write` appear in comments only. No source maps.
4. **Fill-moment checks** — PASS (unchanged from P3/P5; node harnesses + fixtures green: hidden-field trap, off-screen, ancestor opacity, disabled, non-allowlisted frame, http).
5. **Payload lifetime** — PASS by code walk: background locals nulled in `finally`, 10 s cap; content capture 60 s TTL + pagehide/scroll dismissal.
6. **Iframe allowlist** — Justified: `js.stripe.com`, `checkout.stripe.com` (Stripe Elements/Checkout), `pay.google.com` (GPay button iframe). Removal procedure: delete the host from BOTH `CC_FRAME_HOSTS` (background.js) and `CC_FRAME_HOSTS` (fill-engine.js), re-run `fill-engine-node-tests.mjs`.
7. **Permissions** — Verdict: already minimal. `nativeMessaging` (bridge), `tabs` (trusted origin derivation — load-bearing for the whole auth model), `activeTab` (user-gesture host access), `https://*/*` content scripts. `scripting` never requested. **Consciously skipped:** the in-app Settings "Safari extension" explainer screen — onboarding UX, not a security control; needs its own design-DNA pass. Backlogged below.
8. **Keychain/App Group** — PASS. `VaultifySafari.entitlements` = App Group + shared keychain group only, no CloudKit. Key zeroing: `unlockedKey` wraps into `SecureBytes` + `secureZero`s the transient array; `listItemsSession` mirrors it.
9. **Rate limits** — PASS. `generatePassword` 5/min, `saveLogin` 5/min/host, both pre-unlock; `listItems`/`getFillPayload` biometric/session-gated; `listItemsSession` session-gated + `isTrusted` focus gate. No cmd is both unauthenticated and vault-touching (`status`/`echo`/`ping`/`saveGate`/`siteSettings`/`setSiteHidden`/`neverSave` are metadata-only).
10. **Signing/CI** — code DONE (Fastfile/Matchfile); portal registration + `match appstore --force` + `make beta` dry-run USER-OWED.
11. **Docs** — DONE (codebase-summary, deployment-guide, README, CLAUDE.md).
12. **macOS deferral** — noted below; not built (YAGNI).

## Consolidated device-QA release checklist (USER-OWED — run before shipping Safari)

Run on: iOS 17.3-floor simulator/device AND a current-iOS device (Safari extension behavior differs per iOS release). Record results inline here.

**Install + discovery**
- [ ] G2: fresh install → Settings → Safari → Extensions shows Loox; enable; toolbar icon + popup render localized EN and VI (manifest/_locales discovered under Tuist packaging)
- [ ] G1: popup open triggers Face ID from the headless handler (popup-initiated, never content-initiated); cancel lands on the manual Unlock button

**Permissions + origin (G3)**
- [ ] Per-site grant flow ("Allow for One Day" / "Always Allow") works; popup lists correct items for 3 real sites
- [ ] Wrong-origin site lists nothing; http:// page → "not supported"; reader mode/about: → "not supported"
- [ ] Safari populates `sender.url` for content-script messages (L1 belt is live, not a no-op)

**Fill engine (P3 matrix)**
- [ ] 5 fixtures (`VaultifySafari/DevFixtures/*.html`) + 6 real sites: 2 CC checkouts, 2 address forms, 1 VI-language site, 1 React SPA — identity + card fill ≥5/6
- [ ] Hidden-field exfiltration trap fixture receives ZERO values; React controlled inputs keep their values (no framework reversion)

**Signup assist (G4 — decides the H1/H2 policy)**
- [ ] iOS 26.2+ device: generated-password signup → NO extension overlay; observe whether the native save sheet fires for a `setNativeValue`-filled password
- [ ] iOS 26.2+ device with Vaultify NOT enabled as credential provider: verify the user is not left with NEITHER save prompt (if so: flip gate to provider-enablement AND version — change native `WebExtensionSaveGate` + overlay together)
- [ ] iOS 17.x-26.1: overlay appears on signup submit; Save creates an item visible in app + QuickType; duplicate save → graceful "Already saved"
- [ ] Test BOTH a classic full-page-navigation signup AND a fetch/SPA signup (H2: full-nav capture dies on pagehide — record which classes work)

**Inline menu + iframe CC (G5)**
- [ ] Top-20 sample: 8 checkout pages (≥2 Stripe-iframe), 6 address/signup forms, 3 VI sites, 3 login-only pages (expect NO inline UI); ≥17/20 pass with failures triaged
- [ ] Safari fires `focusin` with `isTrusted === false` for scripted `.focus()` (the zero-click-oracle fix relies on it)
- [ ] iPad: popup renders as popover, usable width; inline menu positions correctly

**Phase 6 additions**
- [ ] Popup footer: "Hide on this site" hides inline menu + save overlay on that host after reload; "Show on this site" restores; hint line shows while hidden; popup fill still works on a hidden site
- [ ] Inline-menu footer "Hide on this site": menu dismisses immediately and never returns on that host; re-enable only possible from the popup
- [ ] Save overlay: Save is briefly disabled right after appearing (arm delay); "Never for this site" failure path shows "Could not save" and allows retry (test by toggling airplane-mode-ish native failure if reachable)
- [ ] Overlay/menu/popup colors verified in light + dark; nothing invisible under Increased Contrast

**Release pipeline (checklist item 10)**
- [ ] Portal: `com.bervion.vaultify.safari` App ID registered (App Groups + Keychain Sharing, nothing else)
- [ ] `bundle exec fastlane match appstore --force` regenerates 3 profiles
- [ ] `make beta` tag dry-run: runner signs + uploads; IPA `PlugIns/` contains BOTH `.appex` bundles

## macOS deferral (backlog note)

The web bundle is target-independent. macOS Safari = a new appex target (`com.apple.Safari.web-extension` on a mac slice), `.when([.macos])` embed, Mac App Store sandbox entitlements. Deliberately NOT pre-built (YAGNI). Also backlogged: Settings "Safari extension" explainer screen (enable steps + permission rationale, EN+VI, design-DNA pass), passphrase mode in the generator, never-save/hidden-hosts management UI in app Settings (both lists already live in shared defaults, readable by a future screen), background-parked save capture for full-navigation signups (review H2), per-tab `listItemsSession` throttle (defense-in-depth).

## Todo List

- [x] Checklist 1-9 executed, verdicts recorded here
- [x] Fuzz tests added + green (`WebExtensionRouterFuzzTests`, 716/716 suite green)
- [x] Permissions verdict recorded (already minimal; nothing to trim)
- [x] Per-site kill switch (popup + inline footer, native gate, EN+VI, 10 tests)
- [x] Deferred Lows applied: L4 arm delay, L5 never-save retry, L6 token palette
- [ ] Explainer screen EN+VI (consciously deferred — backlog, not release-blocking)
- [ ] Match profiles regenerated; runner dry-run green (USER — portal + match + beta tag)
- [x] Docs synced (codebase-summary, deployment-guide, README, CLAUDE.md)
- [x] macOS backlog note filed
- [ ] Consolidated device-QA checklist executed + recorded (USER)

## Success Criteria

- Zero cmds besides `getFillPayload` return field values (test-enforced — fuzz sweep green); all fixtures/harnesses green; CI signs and uploads a TestFlight artifact containing all 3 targets (pending user dry-run); docs current.

## Risk Assessment

| Risk | L×I | Mitigation |
|---|---|---|
| Match/portal misconfig breaks release pipeline | Med×High | Fastfile/Matchfile pre-wired; dry-run beta tag before real release; runbook in deployment-guide |
| App Review friction (password-manager web ext) | Low×Med | 1P/Bitwarden/Dashlane precedent; review notes prepared; explainer screen backlogged |
| G4 gate leaves 26.2+ users with no save prompt | Med×Med | Explicit G4 checklist step + documented fix direction (provider-enablement AND version) |

## Security Considerations

- This phase IS the security gate. The kill switch only narrows exposure (hide-only from content, hostnames only, gated natively before any key access). Any device-QA checklist failure blocks release.

## Next Steps

- USER: portal + match + `make beta` dry-run, then execute the device-QA checklist above. Ship via `make beta` → TestFlight QA → `make release`.
