# Loox — Release Readiness Remediation (next release)

**Status: NO-GO.** Phase 0 in progress (owner inputs outstanding).

Phase 1A and 1B are **merged** to `looxpassword-web` `main` via
[PR #5](https://github.com/bervion/looxpassword-web/pull/5) (`a5d7965`, 17 files, +888/-176),
but **not deployed**, **not independently reviewed on the real diff**, and the policy pages
still carry six legal placeholders (OPEN-3). One Phase 1A item, the contact-form honesty fix
(1A.4), was **not implemented** — see [phase-01](phase-01-submission-blockers.md).
Report: [reports/frontend-260804-1120-phase-1a-1b-implementation.md](reports/frontend-260804-1120-phase-1a-1b-implementation.md).

Nothing here flips to READY on the strength of an implementation report. See
[reports/review-260804-1330-external-plan-review.md](reports/review-260804-1330-external-plan-review.md)
for the second-reviewer pass and which of its points were accepted, adjusted, or referred
back to the owner.

**Version naming:** this milestone is "the next release". Do not write `v1.51.0` anywhere
until the owner picks the number — the current RC may claim it.
**Created:** 2026-08-04
**Source audit:** `plans/reports/audit-260804-1000-ios-release-readiness-v1.50.0.md`
**Verification:** 11-cluster independent verification + completeness critic, 2026-08-04.
Raw findings archived at `reports/verification-260804-1037-findings.json`.
**Repos in scope:**
- iOS — `/Users/bervion/Developer/Projects/mobile/ios/Vaultify`
- Web + Workers — `/Users/bervion/Developer/Projects/frontend/looxpassword`

## Context that reframes the whole plan

This is the **first App Store submission**, not an update. Evidence: `metadata/apple/*`
contains only `release_notes.txt` (no description, subtitle, keywords, categories);
the production App Store Server API still answers 401, which is Apple's documented
behavior until an app is released. Consequences:

- There are no live users to protect, so no fix is an emergency hotfix.
- Apple requires a first subscription to be submitted **with** an app version, so
  bundling the membership launch into this release is correct, not extra risk.
- App Store Connect metadata is a **hard blocker**, not paperwork.

Build 78 (tag `v1.50.0`) **was uploaded to TestFlight** on 2026-08-02 (`Release iOS`
run succeeded). Keep it out of App Review and out of wide external testing. Do not
move or reuse the `v1.50.0` tag; this work ships as a new tag.

## Owner decisions — locked 2026-08-04

| # | Decision | Choice | Impact |
|---|---|---|---|
| D1 | Analytics / Crashlytics | Analytics **opt-in (default OFF)**, Crashlytics **opt-out (default ON)** | Drives `SettingsStore` defaults, `AboutView` copy, privacy policy, ASC labels |
| D2 | Favicon | **Keep current behavior** (default ON, Google s2) | Network design unchanged; local cache hygiene tracked separately as P2-FAV. **Contested — see R1** |
| D3 | Subscriptions | **Ship live** — `launchEnabled = true`, 4 IAPs attached | Adds Phase 5; makes Terms/Privacy 3.1.2-blocking. **Contested — see R2** |
| D4 | iPad multitasking | **Full support** (Split View / Stage Manager) | Adds Phase 6 + iPad 13" screenshot session. **Contested — see OPEN-1** |

### Contested decisions — owner must re-confirm or accept the risk in writing

A second reviewer recommends reversing three of these. The decisions stand as recorded;
what changes is that each now carries an explicit, written acceptance rather than an
unstated default. None of them may be flipped by an implementer.

- **R1 — Favicon default ON.** Reviewer position: a password manager should not send the
  hostname of a stored credential to Google to decorate a row, so it should default OFF.
  If D2 stands, the plan records it as a **privacy-risk acceptance** that must go through
  legal and the App Store Connect privacy review, and the mechanical fixes in Phase 2C
  become mandatory rather than optional. The label decision stays as ruled in Phase 1D
  (no `BrowsingHistory` entry), and that too is now an owner-visible call rather than an
  engineering one.
- **R2 — `launchEnabled = true` at submission.** Reviewer position: attaching the four
  IAPs to the submission satisfies Apple's first-subscription rule on its own; flipping
  production purchases on for every user the same day is a separate, larger risk that
  should wait until policies, backend modes, product states, purchase/restore E2E and the
  real-device matrix are all green. If D3 stands, Phase 5 is fully in scope and the owner
  accepts a day-one paid launch on top of a first submission.
- **OPEN-1 — iPad in v1.** Unchanged below. If Branch A stands, Phases 6 and 7 may **not**
  be trimmed: full Split View and Stage Manager, portrait/landscape and resize with the
  editor open, hardware keyboard, iPad 13" screenshots in EN and VI, and AutoFill plus the
  Safari extension exercised on a real iPad.
| D5 | iCloud sync on fresh create | **Explicit consent step**, no preselect | Depends on OPEN-2 |
| D6 | Erase Vault | **Two modes** + durable/observable remote teardown | Scoped down per verification — see Phase 2 |
| D7 | Sample data for review | **Review Notes + public test form**, no seeded fake credential | Phase 7 |

## What the source audit got wrong — do not spend effort here

Verified and dismissed. Recorded so nobody re-opens them.

| Audit claim | Verdict | Why |
|---|---|---|
| P1-11 `VaultifyAutoFillMac` can leak into the iOS archive | **REFUTED** | Tuist `condition: .when([.macos])` emits real pbxproj platform filters; built `Vaultify.app/PlugIns` contains exactly two appexes |
| P0-03 item 6 — `iCloudSyncEnabled` / `approvalModeEnabled` cross-gated | **REFUTED** | 35 call sites read; sharing gates only on approval, sync only on iCloud. Only joint writes are the two deliberate teardowns |
| P2 — AutoFill UI violates the Polaris/token contract | **REFUTED** | The appex links `VaultifyAutoFill/** + VaultifyCore/**` only; `VaultIcon`, `Icons`, `themedForeground` are not in the target and zero Polaris glyphs ship. "Fixing" it = multi-day bundle refactor for a system-drawn sheet |
| P0-05 — slide-to-unlock arrow head disappears (SVG/toolchain) | **REFUTED** | Failure is a **size** mismatch (`@(390,700)` vs `@(260,466.67)`); all 3 reference PNGs are @2x renders compared on @3x devices, so pixels are never compared. Arrow renders complete |
| P0-05 — `item.detail.more` unreachable on iOS 26 | **REFUTED** | Test dies 3 lines earlier at `item.tap()`; the first-run tutorial scrim makes the row non-hittable. The identifier is correctly set at `ItemDetailScreen.swift:302` and has never been exercised |
| P0-04 — AutoFill/Safari appex perform favicon lookups | **REFUTED** | `FaviconService`/`FaviconView` live under `Vaultify/` only, outside every appex source glob |
| P1-08 — missing `UIRequiresFullScreen` blocks submission | **REFUTED** | The key is absent entirely and 8 releases shipped on this Info.plist. Real rotation UX defect, not a gate |
| P2 — Japanese metadata missing | **STALE** | Already fixed: `metadata/apple/ja/release_notes.txt`, `generate-release-notes.sh` ja handling, `InfoPlist.xcstrings` ja. Only `defaultKnownRegions` residue, which has no shipping effect |
| P0-01b — `CA92.1` vs `1C8F.1` is an upload blocker | **OVERSTATED** | `CA92.1` is a valid UserDefaults reason so the validator passes. It is a false declaration worth one word to fix, not a release gate |

Two verifier claims that conflicted are resolved in favor of the evidence:
**ITMS-91053 for first-party code is a post-upload notice, not an upload failure.**
The hard-reject path applies to third-party SDKs on Apple's list. Fix it anyway
(15 minutes), but do not schedule around it as a gate.

## What the audit missed — these cost real review cycles

| # | Missed item | Where | Phase |
|---|---|---|---|
| M1 | **iPad 13" screenshots are mandatory and do not exist.** `TARGETED_DEVICE_FAMILY = "1,2"` declares iPad; ASC will not accept the submission without them. No `metadata/apple/*/screenshots/` exists; `Fastfile:135` sets `skip_screenshots: true` | ASC | 7 |
| M2 | **ASC metadata is empty.** No description, subtitle, keywords, categories, age rating, support/marketing URL, review notes. `fastlane submit` passes `skip_metadata: false, force: true` and would push an incomplete record with no prompt | `metadata/apple/**`, `fastlane/Fastfile` | 7 |
| M3 | **"Mac (Designed for iPad)" defaults ON** because iPad is a supported family. macOS does not surface an iPad app's AutoFill extension → a password manager whose AutoFill silently never works | ASC checkbox | 0 |
| M4 | **App Review notes for enabling AutoFill + the Safari extension.** Password managers are rejected under 2.1 for "could not locate the functionality" more than anything else. `host_permissions: ["https://*/*"]` needs an explicit justification | Review notes | 7 |
| M5 | **In-app claim is false.** `AboutView.swift:175` ships "Loox collects no analytics and has no accounts" in EN/VI/JA while the same build declares three collected data types and defaults both toggles ON. `:159-160` "Nothing is sent to a server" is false too | `AboutView.swift` | 1 |
| M6 | **False comparative advertising.** `home-compare.tsx:13` renders ✓ for "No analytics or tracking SDKs" against six **named** competitors while the app ships Firebase Analytics + Crashlytics on by default | web | 1 |
| M7 | **Second purchase surface has no policy links.** `LooxPaywallScreen.swift:113` presents `SubscriptionStoreView` with no `subscriptionStorePolicy*` anywhere in the repo → 3.1.2 not closed by fixing `LooxMembership` constants alone | iOS | 1 |
| M8 | **Erase never revokes Quick Links** — it deletes the revoke tokens instead, leaving up to **30 days** of live, permanently unrevokable ciphertext whose content key is in the URL fragment | `AppEnvironment.swift` | 2 |
| M9 | **macOS Erase bypasses relay teardown entirely.** The fail-closed guard exists only on the iOS Settings screen; the Mac path drops the CloudKit zone so the alias list is destroyed everywhere and aliases keep forwarding forever | `MacSettingsView.swift:180` | 2 |
| M10 | **A malicious backup's `Level2Wrap.kdf` is persisted verbatim** into the device key bundle, turning a transient import DoS into a permanent one that the user cannot undo (turn-off demands the foreign password). The AutoFill appex, which halves Argon2 memory for jetsam headroom, dies first | `VaultSession+Level2.swift` | 3 |
| M11 | **L2 wrap collision silently strands data.** Restoring your own backup onto a device that already has a different Extra Password imports every protected field as permanently unopenable ciphertext, reported as success | `VaultSession+Level2.swift` | 3 |
| M12 | **A size-class flip wipes the open item-editor draft** and sweeps staged attachments. Dragging the Split View divider mid-edit silently destroys typed secret material | `ItemEditorScreen.swift` | 6 |
| M13 | **Plus/Max-class iPhones in landscape get routed into the iPad sidebar shell** because `AdaptiveRootView` keys only off `horizontalSizeClass`. Tab bar vanishes, `navigator` becomes nil, and rotating back triggers M12. **Mandatory regardless of the iPad decision** | `AdaptiveRootView.swift` | 2 |
| M14 | **Production backend liveness is unverified.** Release builds use production hosts (`api`, `s`, `config`, `api-relay`, `entitlement`, `invite`, `open`). Only `api-relay` has a health probe. A reviewer hitting a network error on Loox Link is a 2.1 rejection. AASA at `invite.looxpassword.com` unprobed | pre-submit gate | 7 |
| M15 | **`scripts/ci/select-xcode.sh` hard-pins Xcode 26.5**, which is not installed on the maintainer machine. One unattended runner update turns every `v*` tag into a job that dies before signing | `scripts/ci/**` | 4 |
| M16 | **`make certificates` has not been run** since the AutoFill entitlements started requesting iCloud/CloudKit. `match` runs `readonly: true`, so a stale profile is a hard failure at signing time on a tagged release | run today | 0 |
| M17 | **Export compliance is likely misdeclared.** `ITSAppUsesNonExemptEncryption = false` with the justification "standard algorithms protecting on-device data" — that is not one of Apple's listed exemptions, and the app ships vendored Argon2id providing data confidentiality | owner + legal | 0 |
| M18 | **Google Signals must stay OFF** in the GA4 property console, or "not used for tracking" becomes false and an ATT prompt is owed with no code to show it. Console setting, outside both repos | owner | 0 |

**ATT is not required.** `FirebaseAnalyticsCore` is the `AdSupport`-free flavor;
`strings` on the archive shows `identifierForVendor` and no `advertisingIdentifier`.
Conditions: `NSPrivacyTracking` stays false, tracking domains stay empty, and M18 holds.

**Account deletion (5.1.1(v)) does not apply** — Loox creates no accounts. Watch item:
the relay stores a principal bound to a verified destination inbox, reachable for
deletion only through the nuclear Erase. Add a "Delete my relay data" affordance (Phase 6).

## Phases

| Phase | Title | Blocks release | Parallel | File |
|---|---|:--:|:--:|---|
| 0 | Owner decisions and inputs | yes | — | [phase-00-owner-inputs.md](phase-00-owner-inputs.md) |
| 1 | Submission blockers — legal, privacy manifests, honesty | yes | 5 agents, 2 repos — **1A, 1B done** | [phase-01-submission-blockers.md](phase-01-submission-blockers.md) |
| 2 | Consent, defaults, erase completeness | yes | 5 agents, serialized on hot files | [phase-02-consent-defaults-erase.md](phase-02-consent-defaults-erase.md) |
| 3 | Import / export / artifact data safety | yes | 3 agents | [phase-03-data-safety.md](phase-03-data-safety.md) |
| 4 | Quality gates and CI truth | yes | 1 agent | [phase-04-quality-ci.md](phase-04-quality-ci.md) |
| 5 | Membership launch (`launchEnabled = true`) | yes (D3) | 1 agent + owner | [phase-05-membership-launch.md](phase-05-membership-launch.md) |
| 6 | iPad, accessibility, polish | yes (D4) | 2 agents | [phase-06-ipad-a11y.md](phase-06-ipad-a11y.md) |
| 7 | Signed RC, ASC metadata, submission | yes | owner-led | [phase-07-signed-rc-submission.md](phase-07-signed-rc-submission.md) |

## Dependencies

```
Phase 0 ──┬─> Phase 1 ──┬─> Phase 2 ──┐
          │             │             ├─> Phase 7
          ├─> Phase 4 ──┤             │
          │             ├─> Phase 3 ──┤
          ├─> Phase 5 ──┘             │
          └─> Phase 6 ────────────────┘
```

Hard sequencing constraints, all verified:

1. **Policy content lands before or with the iOS URL change.** Repointing
   `LooxMembership` at `/policies/terms` while that page says "This is a starter
   template… replace with terms reviewed by qualified legal counsel" converts a 404
   rejection into a 5.1.1 rejection. Phase 1B gates Phase 1C's value.
2. **App Privacy questionnaire is filed last**, after D1, the Device ID declaration,
   and D2 are frozen in code.
3. **`AboutView` copy depends on D1.** Write the string after the default is set.
4. **The iCloud consent fix has a product prerequisite (OPEN-2).** Deleting
   `OnboardingFlow.swift:143` breaks `pushRecoveryEnvelopeIfNeeded()` (gated on
   `iCloudSyncEnabled` at `SyncCoordinator.swift:90`), which makes the Emergency Kit
   PDF's own printed restore instructions false and dead-ends `JoinByRecoveryView`
   on `.noEnvelope`.
5. **Phase 4's tutorial fix unblocks both UI tests** — pull it forward, it is S-effort
   and every phase wanting UI-test verification depends on it.
6. **`tuist generate` after every `Project.swift` edit and every new file.** Bake into
   each phase's exit criteria.
7. **Doc corrections (README / AGENTS / CLAUDE) come last**, after the code they
   describe is final. Do not edit docs to match a bug you are about to fix.

## File ownership — collision control

`Localizable.xcstrings` is a JSON blob with no merge semantics. Parallel edits corrupt
it. **No agent edits it directly.** Each writes proposed keys (EN + VI + JA) to
`plans/260804-1037-release-readiness-remediation/reports/strings-<agent>.json`; one
integrator merges at the end of each phase and verifies every key has all three values.

| File | Sole owner | Phase |
|---|---|---|
| `Project.swift` + both `PrivacyInfo.xcprivacy` | Agent 1D | 1 |
| `Vaultify/App/SettingsStore.swift` | Agent 2A | 2 |
| `Vaultify/App/AppEnvironment.swift` (+ erase paths) | Agent 2B | 2 |
| `Vaultify/Services/FaviconService.swift` | Agent 2C | 2 |
| Onboarding flows | Agent 2D | 2 |
| `Vaultify/Features/ImportExport/ImportView.swift` | Agent 3C | 3 |
| `src/messages/{en,vi}.json` (web) | Agent 1A | 1 |
| `content/policies/**` (web) | Agent 1B | 1 |
| `Makefile` | Agent 1D in Phase 1, then Phase 4 agent | 1, 4 |
| `fastlane/Fastfile` | Phase 4 agent | 4 |
| `Vaultify/Features/Settings/MacSettingsView.swift` | Agent 2B | 2 |
| `VaultStore` and any migration files | Phase 3 agent 3A | 3 |

Independent lanes run in parallel. Serialize only the four real dependencies:

1. Live legal pages → production subscription launch.
2. Emergency Kit semantics settled (OPEN-2) → consent implementation.
3. Phase 1C membership URLs and gates → Phase 5.
4. The localization integrator runs after each wave, never during one.

## Open questions blocking work

| # | Question | Blocks | Recommendation |
|---|---|---|---|
| OPEN-1 | **Does iPad ship in v1 at all?** D4 chose full multitasking, but verification surfaced two facts the decision did not account for: iPad 13" screenshots are mandatory and do not exist (M1), and the iPad shell has four real defects. Dropping to `TARGETED_DEVICE_FAMILY = "1"` removes ~30% of remaining engineering **and** the screenshot session | Phase 6 scope, Phase 7 screenshots | Owner call; second reviewer recommends iPhone-only for a first submission. If the calendar is tight, ship iPhone-only and land iPad in a later release. If iPad stays, Phases 6 and 7 may not be trimmed. **M13 must be fixed either way** — it is an iPhone bug |
| OPEN-2 | **What does the Emergency Kit mean when iCloud sync is off?** The printed PDF instructs the user to sign into the same iCloud and scan the Setup Code. With sync off that is false | Phase 2D | Make the kit's copy conditional, and make the consent step explain that cross-device recovery needs sync |
| OPEN-3 | **Legal entity name, registered address, governing law** for the Terms rewrite | Phase 1B | Required input; nothing in either repo names them |
| OPEN-4 | **Does the `ja` App Store localization ship in v1?** `metadata/apple/ja/release_notes.txt` exists but there is no Japanese description or keywords | Phase 7 | If yes, point the ja listing's Privacy Policy URL at the English page — Apple accepts one URL for all localizations. **Do not build `messages/ja.json`**, it is off the critical path |
| OPEN-5 | **Is the Loox Link cleanup cron live in production?** `docs/fe-cloudflare-spec.md:42` marks it maintenance-only | Phase 1B retention section, M8 blast radius | Verify before writing the retention clause |

## Acceptance — NO-GO → GO

All true on the **same tag/SHA**:

1. Every Phase 1–5 exit criterion met, with tests.
2. `/policies/terms`, `/policies/privacy`, `/terms`, `/privacy`, `/support` all 200,
   in both locales, and the routes gate asserts it in the deploy path.
3. No "starter template" text on any live page; policy signed off by owner + counsel.
4. Privacy policy, in-app copy, `PrivacyInfo.xcprivacy`, and ASC App Privacy answers
   all describe the same runtime behavior.
5. Signed archive + Transporter validation pass; correct entitlements and a correct
   `PrivacyInfo.xcprivacy` in each of the **three** executable bundles the iOS IPA
   contains (app, AutoFill appex, Safari appex); privacy report clean.
6. Fresh install, v1.49.1 upgrade, erase, and import/export data-safety scenarios pass.
7. AutoFill + Safari verified on a real iPhone (and iPad if OPEN-1 keeps it) at the
   17.3 floor and current OS.
8. Production hosts and the AASA all respond correctly from a Release build (M14).
9. IAPs attached, sandbox purchase/restore/upgrade/cancel pass, `launchEnabled = true`.
10. ASC metadata complete: description, subtitle, keywords, categories, age rating,
    URLs, review notes and contact, iPhone 6.9" + iPad 13" screenshots.
11. Mac availability decided (M3); macOS version not submitted this round.
12. New tag cut; `v1.50.0` untouched.
