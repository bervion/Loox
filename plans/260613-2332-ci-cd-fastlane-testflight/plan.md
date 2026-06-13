# CI/CD + Fastlane + TestFlight (self-hosted runner)

Status: implemented (validated) · Branch: main · Date: 2026-06-13

## Goal
`make release` (and `make beta`) → auto bump version (conventional commits) → AI release notes (EN/VI) → tag `v*` → GitHub Actions on **self-hosted** runner → fastlane **match** sign (app + AutoFill ext) → upload **TestFlight** via App Store Connect **API key**.

Pattern ported from `/Users/bervion/Developer/Projects/mobile/flutter/blink-flutter`, adapted for native Xcode.

## Decisions (user-confirmed)
- Signing: **fastlane match** (private certs repo, appstore type)
- Trigger: push tag `v*` + `make release` automation (auto bump + AI notes)
- Auth: **App Store Connect API key (.p8)**
- Scope: **CI** (compile check) + **CD** (TestFlight)

## Key facts
- Targets: `Vaultify` (`com.bervion.vaultify`) + `VaultifyAutoFill` (`com.bervion.vaultify.autofill`); Team `WDNL2F75V7`
- Version in pbxproj (4× each setting) → sed bump keeps app+ext lockstep
- Locales en+vi · no test target · zero-backend · `VaultifyCore` = synchronized folder (not SPM)
- Entitlements: App Group `group.com.bervion.vaultify` + AutoFill Credential Provider (+passkey). iCloud OFF (compile-flag gated, not in entitlements).

## Phases / Todo
- [x] P1 fastlane scaffold: `Gemfile`(+lock), `fastlane/{Appfile,Matchfile,Fastfile}`
- [x] P2 release automation: `scripts/{release.sh,release-beta.sh,generate-release-notes.sh}`, `Makefile`
- [x] P3 GitHub Actions: `.github/workflows/{ci.yml,release-ios.yml}`
- [x] P4 `.gitignore` secrets/fastlane; `metadata/apple/{en-US,vi}` seed
- [x] P5 `docs/deployment-guide.md` (manual prereqs runbook)
- [x] P6 validate: bash -n ✓ · ruby -c ✓ · yaml ✓ · 3 lanes parse ✓ · 6 actions exist ✓ · pbxproj bump dry-run rewrites all 4 configs ✓

## Not committed
Files are staged as untracked — NOT committed/pushed (awaiting user go-ahead + manual prereqs). Pushing workflows is harmless until a `v*` tag fires release-ios.yml, which needs secrets + runner first.

## Manual prereqs (USER — outside repo)
1. Apple Dev Portal: App IDs for both bundle ids w/ App Group + AutoFill caps; App Group `group.com.bervion.vaultify`.
2. Create App Store Connect app record (bundle `com.bervion.vaultify`).
3. Create private certs repo `bervion/vaultify-ios-certificates`; run `make match-setup` once locally to seed.
4. Create ASC API key (.p8); note Key ID + Issuer ID.
5. GitHub secrets: `MATCH_PASSWORD`, `MATCH_GIT_AUTH`, `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY`.
6. Register self-hosted runner (macOS + Xcode + ruby/bundler + `claude` CLI optional).

## Open questions
- Certs repo name: assumed `bervion/vaultify-ios-certificates` (change in Matchfile if different).
