# Phase 06 — Security Review + Hardening + Release Readiness

## Context Links

- Research: `plans/reports/from-research-260712-1453-safari-web-extension-plan-report.md` §3 (security model), §7 (pitfall table)
- Release runbook: `docs/deployment-guide.md` (fastlane match, self-hosted runner)
- Prereq: Phases 01-05 complete

## Overview

- Priority: P1 (release-blocking)
- Status: pending
- Adversarial review of the whole extension against the security invariant, protocol fuzz/abuse tests, macOS deferral note, signing/CI, docs sync, App Store material. Threat model lens per `~/.claude/rules/review-audit-self-decision.md`: validate findings against what the code actually protects — no reflexive widening.

## Key Insights

- The single high-value review target is the native→JS boundary: exactly ONE cmd returns secret values (`getFillPayload`). Everything else must be provably metadata-or-less. Audit = enumerate every `Response.data` shape and grep the handler for any decrypt outside `WebExtensionReader.fillPayload`.
- Second target: content-script fill-moment checks — the page controls the DOM; every check must run at write time (P3 list), and the hidden-field trap fixture is the regression test.
- Third: suppression rules (no inline credential UI; no save overlay on nativeSave devices) — these prevent UX-level phishing/double-prompt classes, verified by fixtures + G4/G5 records.

## Requirements

- Functional: all checklist items below pass or have a documented, user-approved exception.
- Non-functional: docs updated (`docs/codebase-summary.md`, `README.md` targets list, `docs/deployment-guide.md` match profile for 3rd appex); CI green on self-hosted runner (tuist generate now emits 3rd target — match must sign it).

## Architecture

Review checklist (execute, record verdicts inline):

1. **Bridge audit**: enumerate all cmds × response payloads; assert only `getFillPayload` carries field values; assert single-item scope; grep for `vaultKey`/key bytes near any JSON encode.
2. **Protocol fuzz** (Swift tests): malformed JSON, wrong `v`, oversized payloads (1MB), itemId of another category, http origin, empty origin, unicode host tricks (punycode `xn--`) → all rejected; matching operates on ASCII/punycode host form.
3. **JS hygiene**: grep shipped JS for `console.`, `eval`, `innerHTML` with interpolation, `browser.storage` writes (allow UI-pref keys whitelist only); no source maps in appex.
4. **Fill-moment checks regression**: hidden-field trap, offscreen field, disabled field, cross-origin non-allowlisted frame, http page — all refuse.
5. **Payload lifetime**: background local-var only, cleared post-dispatch/10s; content-script captured save values 60s TTL; verify by code walk + timers exercised in fixture.
6. **Iframe allowlist review**: justify each entry; document removal procedure.
7. **Permissions minimization**: re-check manifest — can `scripting` be dropped (content_scripts are static)? Drop any unused permission; `<all_urls>`-scare onboarding screen in app (Settings → "Safari extension" explainer, EN+VI) per report §7.
8. **Keychain/App Group**: appex entitlements minimal (no CloudKit); `BiometricKeyStore` reason strings localized; key zeroing after each handler op (code walk).
9. **Rate limits**: generatePassword 5/min; listItems/getFillPayload naturally biometric-gated — confirm no cmd is both unauthenticated and vault-touching.
10. **Signing/CI**: portal capabilities final; regenerate match profiles (app + 2 appexes); dry-run `make beta` tag on runner; confirm `release.sh` version bump covers new target (inherits project base — verify).
11. **Docs**: codebase-summary (new target + protocol overview), deployment-guide (match), README targets, CLAUDE.md project note if conventions added (e.g. `_locales` EN+VI rule).
12. **macOS deferral note**: web bundle is target-independent; macOS = new appex target `com.apple.Safari.web-extension` on the mac slice + `.when([.macos])` embed + Mac App Store sandbox entitlements. Out of scope; do not pre-build (YAGNI). Backlog entry only.

## Related Code Files

- Read/audit: everything under `VaultifySafari/`, `VaultifyCore/WebExtensionReader.swift`, router tests
- Modify: `manifest.json` (permission trims), `docs/codebase-summary.md`, `docs/deployment-guide.md`, `README.md`, app Settings explainer screen (new small SwiftUI view + xcstrings EN+VI), fastlane match config
- Create: `VaultifyTests/SafariMessageRouterFuzzTests.swift`

## Implementation Steps

1. Execute checklist 1-9; file fixes as small commits; re-run `make test`.
2. Onboarding/explainer screen in app Settings (enable steps + permission rationale), EN+VI, design-dna checklist pass.
3. Signing/CI (item 10) + docs (item 11) + backlog note (item 12).
4. Full manual regression on device: iOS 17.3 floor sim + current shipping iOS device (per-release lesson: Safari extension behavior differs per iOS release, report §8).
5. Delegate final pass to code-reviewer agent; address correctness findings; observational findings → backlog.

## Todo List

- [ ] Checklist 1-9 executed, verdicts recorded here
- [ ] Fuzz tests added + green
- [ ] Permissions trimmed to minimum
- [ ] Explainer screen EN+VI
- [ ] Match profiles regenerated; runner dry-run green
- [ ] Docs synced (codebase-summary, deployment-guide, README)
- [ ] macOS backlog note filed
- [ ] Dual-iOS regression pass recorded

## Success Criteria

- Zero cmds besides `getFillPayload` return field values (test-enforced); all fuzz/regression fixtures green; CI signs and uploads a TestFlight artifact containing all 3 targets; docs current.

## Risk Assessment

| Risk | L×I | Mitigation |
|---|---|---|
| Match/portal misconfig breaks release pipeline | Med×High | Dry-run beta tag before real release; runbook update same PR |
| App Review friction (password-manager web ext) | Low×Med | 1P/Bitwarden/Dashlane precedent (report: limitations); explainer screen; review notes prepared |
| Audit finds architectural gap late | Low×High | Invariant was threaded per phase; checklist is verification, not first contact |

## Security Considerations

- This phase IS the security gate. Any checklist failure blocks release; fixes re-run the relevant fixture matrix.

## Next Steps

- Ship via `make beta` → TestFlight QA → `make release`. Backlog: passphrase mode in generator, never-save management UI, macOS Safari target, tier-3 inline expansion.
