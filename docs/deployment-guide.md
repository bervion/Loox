# Deployment Guide — CI/CD & TestFlight

Vaultify ships to TestFlight via **GitHub Actions on a self-hosted macOS runner**, signed with **fastlane match**, uploaded with an **App Store Connect API key**.

> **Temporary (since 2026-09-28):** the self-hosted Mac mini is offline, so the macOS jobs of `ci.yml` and `release-ios.yml` run on GitHub-hosted `macos-26` (the release's tag and CI evidence checks run first on `ubuntu-latest`). See `docs/runbooks/ci-release-operations.md` ("Temporary: GitHub-hosted runners") for what changes and how to switch back.

```
make release  →  bump version + AI notes + tag vX.Y.Z  →  push
                                                            │
                          GitHub Actions (self-hosted) ◄────┘  (tag v*)
                                  │
                 match (App Store certs/profiles, app + AutoFill ext + Safari ext)
                                  │
                 build_app → upload_to_testflight (ASC API key)
```

| Component | Value |
|---|---|
| App bundle id | `com.bervion.vaultify` |
| AutoFill ext bundle id | `com.bervion.vaultify.autofill` |
| Safari ext bundle id | `com.bervion.vaultify.safari` |
| App Group | `group.com.bervion.vaultify` |
| Team ID | `WDNL2F75V7` |
| Certs repo (match) | `github.com/bervion/vaultify-ios-certificates` (private) |
| App locales | en, vi |

---

## Project generation (Tuist)

The Xcode project is **not committed** — it is generated from `Project.swift` by
[Tuist](https://tuist.dev). This lets a beta-Xcode dev and a stable-Xcode runner each
generate a project file their own Xcode can open (no "future project format" error).

- Install once on **dev + runner**: `brew install tuist`
- After cloning / pulling / adding or removing source files: `make gen` (= `tuist generate`)
- `Vaultify.xcodeproj` and `Vaultify.xcworkspace` are gitignored — regenerate anytime
- Version (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`) lives in `Project.swift`; `make release` bumps it there
- CI runs `tuist generate` before building, so each runner uses its own Xcode

> Tuist fixes the project **format** mismatch, not SDK/API differences. Don't use APIs
> newer than the runner's Xcode SDK, or the runner build will fail to compile.

---

## One-time setup

Do these once. Steps 1–5 are prerequisites; the pipeline cannot upload until they exist.

### 1. Apple Developer Portal — App IDs & capabilities
All three bundle ids must exist as **explicit App IDs** with the capabilities each target uses:

- `com.bervion.vaultify` → enable **App Groups** (`group.com.bervion.vaultify`) + **Keychain Sharing** (`com.bervion.vaultify.shared`) + **AutoFill Credential Provider**.
- `com.bervion.vaultify.autofill` → enable **App Groups** (same group) + **Keychain Sharing** (`com.bervion.vaultify.shared`) + **AutoFill Credential Provider**.
- `com.bervion.vaultify.safari` → enable **App Groups** (same group) + **Keychain Sharing** (`com.bervion.vaultify.shared`) only. **No AutoFill capability, no iCloud/CloudKit** — the Safari extension reads the local vault only, and its entitlements deliberately carry nothing else.

> The **Keychain Sharing** capability (group `com.bervion.vaultify.shared`) is **required** for both extensions to access the biometric-gated Vault Key stored by the app. Ensure every App ID has this capability enabled before provisioning profiles are generated. match generates profiles from each App ID's enabled capabilities. If you add a capability later, re-run `make certificates` after `bundle exec fastlane match nuke distribution` (or `match appstore --force`) so profiles regenerate.

#### Adding the Safari web extension appex (one-time, before the first release that includes it)
The Safari extension ships **embedded in the app** — no separate App Store record, no separate upload. Release readiness needs exactly:

1. **Portal**: register the explicit App ID `com.bervion.vaultify.safari` with **App Groups** (`group.com.bervion.vaultify`) + **Keychain Sharing** (`com.bervion.vaultify.shared`) as above.
2. **match**: regenerate profiles so the third App Store profile exists —
   `bundle exec fastlane match appstore --force` (or `make match-setup` from the seeding Mac). The `Matchfile`/`Fastfile` already list all three identifiers; the release lane maps `match AppStore com.bervion.vaultify.safari` onto the `VaultifySafari` target.
3. **Dry run**: push a `make beta` tag and confirm the runner signs and uploads an artifact containing all three targets (check the IPA's `PlugIns/` for `VaultifyAutoFill.appex` + `VaultifySafari.appex`).

Version numbers need no extra step: the appex inherits `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` from the `Project.swift` project base, which `release.sh` bumps.

### 1b. App ID capability — App Attest (manual, once)

The app's entitlements declare `com.apple.developer.devicecheck.appattest-environment`,
and codesign refuses any entitlement the provisioning profile does not grant. Without
this the archive dies with *"Provisioning profile … doesn't include the App Attest
capability"* about ten minutes in.

**It cannot be automated.** The App Store Connect API rejects `capabilityType
APP_ATTEST` — it is not in the list the API manages — and `produce` still authenticates
with an Apple ID and 2FA. Do it by hand, once:

1. developer.apple.com → Certificates, Identifiers & Profiles → Identifiers
2. open `com.bervion.vaultify` → tick **App Attest** → Save
3. `bundle exec fastlane match appstore --force` to mint profiles that carry it

Skipping this does not just fail the build. Without the entitlement in the signed app,
`DCAppAttestService.attestKey` fails on device, and every quick link and private email
alias fails with a generic error while the server never sees a request.

### 2. App Store Connect — create the app record
App Store Connect → Apps → **＋** → New App. Platform iOS, bundle id `com.bervion.vaultify`. The app must exist before TestFlight accepts a build.

### 3. Private certificates repo (match storage)
Create an **empty private** GitHub repo `bervion/vaultify-ios-certificates`, then seed it from your Mac (has Xcode + the signing account):

```bash
bundle install
make match-setup        # = bundle exec fastlane match appstore
```

`match` will prompt for a passphrase (the **MATCH_PASSWORD**) and store the encrypted
App Store distribution cert + both provisioning profiles in that repo. Remember the passphrase.

### 4. App Store Connect API key (.p8)
App Store Connect → **Users and Access → Integrations → App Store Connect API → Team Keys** → Generate.
Role **App Manager**. Download the `.p8` **once** (cannot re-download). Note the **Key ID** and the **Issuer ID** (top of the page).

### 5. GitHub repository secrets
Repo → Settings → Secrets and variables → Actions → **New repository secret**:

| Secret | Value |
|---|---|
| `MATCH_PASSWORD` | the passphrase from step 3 |
| `MATCH_GIT_AUTH` | base64 of `username:PAT` → `echo -n "bervion:<GitHub-PAT-with-repo-scope>" \| base64` |
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID from step 4 |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Issuer ID from step 4 |
| `APP_STORE_CONNECT_API_KEY` | full contents of the `.p8` file (incl. BEGIN/END lines) |

`MATCH_GIT_AUTH` lets the runner clone the private certs repo over HTTPS. The PAT
needs `repo` scope (read) on `vaultify-ios-certificates`.

### 6. Self-hosted runner (you configure)
Repo → Settings → Actions → Runners → **New self-hosted runner** (macOS). The runner host needs:

- macOS + a recent **stable Xcode** + Command Line Tools (the project is generated to match it — no need to mirror the dev's beta Xcode)
- **Tuist** (`brew install tuist`) — workflow runs `tuist generate`
- **Ruby** is provided by the `ruby/setup-ruby` action in CI (the runner's system Ruby 2.6 is too old) — no manual Ruby setup needed on the runner
- `git`, and access to clone `vaultify-ios-certificates`
- `claude` CLI is **not** needed on the runner (notes are generated locally during `make release` and committed)
- Repo secret **`LOOX_LINK_PROD_TOKEN`** (Settings → Secrets → Actions): the interim Loox Link create token (matches the Worker's `APP_CREATE_TOKEN --env production`). The release workflow exports it as `TUIST_LOOX_LINK_PROD_TOKEN` for `tuist generate`, which bakes it into the app's Info.plist — never committed; the workflow fails early if the secret is missing. Rotate anytime (`wrangler secret put` + `gh secret set`). Retired when App Attest ships (loox-link C7).
- Keep the runner online; default label `self-hosted` matches the workflows

---

### 7. Firebase Analytics (GA4) config

Done for this repo: Firebase project `loox-63383`, iOS app `com.bervion.vaultify`,
`GoogleService-Info.plist` committed in **`Vaultify/Resources/`** (ships inside every IPA;
not a secret). A fork repeats: console.firebase.google.com → add iOS app → download the
plist into that folder. Without it, builds succeed and analytics stays dark, so CI/forks
are unaffected. The app-level privacy manifest lives at
`Vaultify/Resources/PrivacyInfo.xcprivacy` (no-tracking declaration + UserDefaults
required-reason; Firebase SDK bundles carry their own manifests). Verify events with the DEBUG console mirror (Console.app, category `analytics`)
or Firebase DebugView (`-FIRDebugEnabled` launch argument). At the next App Store
submission, declare **Product Interaction — not linked to identity**, plus **Crash Data**
and **Other Diagnostic Data — not linked to identity** in App Privacy (the SDKs ship their
own privacy manifests; no IDFA/tracking declaration needed since the build links
`FirebaseAnalyticsCore`, and `FirebaseCrashlytics` pulls no ad identifiers either).

### 8. Crashlytics

Same Firebase project and the same committed plist — no extra config. The release lane uploads
dSYMs via `upload_symbols_to_crashlytics` after `build_app`; there is deliberately NO Xcode
run-script phase, because its canonical path depends on the derived-data layout and differs
between a dev machine and the self-hosted runner, where it fails silently. Collection is off in
DEBUG builds and is gated at runtime by its own `crashReportingEnabled` setting (separate from
the analytics toggle). Extensions carry no Firebase, so appex crashes never appear.

### 9. CloudKit schema deploy (MANDATORY before any tag)

CloudKit **Production has no just-in-time schema creation**. A record type that exists only in
Development is rejected in Production: the affected sync plane fails silently (planes are
fault-isolated, so everything else keeps syncing) and that data never reaches a second device.
This has already shipped past twice.

Before tagging a release that adds or changes a record type:

1. Run a Debug build once against **Development** so the type is JIT-created with all fields.
2. CloudKit Console → container `iCloud.com.bervion.vaultify` → **Deploy Schema Changes to
   Production**.
3. Verify each record type is listed in the Production schema afterwards — deploying is
   all-or-nothing and irreversible, so confirm rather than assume.

Known types to check: `VaultItem`, `VaultFolder`, `VaultPasskey`, `VaultPersona`,
`VaultEmailAlias`, `VaultForwardingInbox`, `AuditReport`, `AuditFindingState`, `OwnerDevice`,
`DeviceRevocation`. `VaultPasskey` carries `sealed` (Bytes), `largeBlobSealed` (Bytes),
`createdAt` (Date/Time), `updatedAt` (Date/Time), `deletedAtMs` (Int64).

Never use Erase Vault to troubleshoot sync: it deletes the whole zone, every device's synced
copy, and the recovery envelope.

## Day-to-day

```bash
make release     # auto bump (conventional commits) + AI notes + tag → TestFlight
make beta        # quick build, no semver bump → TestFlight (vX.Y.Z-beta.N)
make hotfix      # force patch bump → TestFlight
make version     # show current version / build / last tag
make changelog   # commits since last tag
make notes       # preview AI release notes without committing
make check       # local compile check (app + AutoFill extension)
make submit-ios  # submit the latest TestFlight build to App Store review
```

**Version bump** is driven by conventional commit prefixes since the last tag:
`feat!`/`BREAKING CHANGE` → major · `feat` → minor · `fix`/`perf`/other → patch.
`make release` writes `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` into the pbxproj
(app and extension together), generates EN/VI release notes via the Claude CLI,
updates `CHANGELOG.md`, commits, tags `vX.Y.Z`, and pushes. The tag triggers
`release-ios.yml`.

Release notes live in `metadata/apple/<locale>/release_notes.txt` and become the
TestFlight "What to Test" text. Edit them during the `make release` prompt (`edit`)
or commit changes before tagging.

---

## Releasing from your own Mac (runner fallback)

`make release` tags and lets the self-hosted runner build. When that runner cannot do
the job — it has run out of disk and blocked a shipped-bug fix for a day — build and
upload from the dev Mac instead:

```bash
scripts/release-local.sh --dry-run   # everything except the upload
scripts/release-local.sh             # verify, build, sign, upload
```

It mirrors `release-ios.yml` step for step so the artifact is the one CI would have
produced: same `scripts/ci/prepare-project.sh`, same `fastlane build_and_upload`, same
match profiles. It is not a way around the release gates — it refuses unless HEAD is
on `main`, the tree is clean, and HEAD is the commit tagged `vX.Y.Z`, and it runs the
same unit target CI gates on. `--skip-tests` exists for when CI is already green for
that exact commit, and it says so on screen.

Still run `make release` first: that is what bumps the version, writes the notes and
creates the tag. This script only replaces the runner half.

**Secrets** go in `fastlane/.env.release` (gitignored) or the environment:
`MATCH_PASSWORD`, `MATCH_GIT_BASIC_AUTHORIZATION`, `APP_STORE_CONNECT_API_KEY_KEY_ID`,
`APP_STORE_CONNECT_API_KEY_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_KEY` (the .p8
contents), `TUIST_LOOX_LINK_PROD_TOKEN`. They are the same values as the GitHub
secrets in §5.

`CI` is deliberately left unset so fastlane uses your login keychain rather than
building a throwaway one — the opposite of what a shared runner needs.

---

## How it works

- `.github/workflows/ci.yml` — on push to `main` / PRs: compiles the app scheme
  (builds the embedded AutoFill extension too), no signing. Fast feedback.
- `.github/workflows/release-ios.yml` — on tag `v*`: `bundle install` → `fastlane build_and_upload`.
- `fastlane/Fastfile` `build_and_upload`: `setup_ci` (temp keychain) → `match` (readonly,
  app + AutoFill ext + Safari ext) → force Manual signing per target → `build_app`
  (app-store export with all three profiles) → `upload_to_testflight`.

The build number is whatever is committed in the pbxproj at the tagged commit, so it is
unique and increasing for every upload (each `make release`/`make beta`/`make hotfix` bumps it).

---

## Troubleshooting

- **`No profiles for 'com.bervion.vaultify.autofill'` (or `….safari`)** → that extension's
  App ID is missing or its capabilities differ (esp. Keychain Sharing). Fix the App ID (step 1), ensure both **Keychain Sharing** and **App Groups** are enabled, then `bundle exec fastlane match appstore --force`.
- **`Authentication credentials … invalid` (match clone)** → `MATCH_GIT_AUTH` wrong; regenerate
  the base64 of `user:PAT` and confirm the PAT can read the certs repo.
- **`Invalid App Store Connect API key`** → `APP_STORE_CONNECT_API_KEY` must be the full `.p8`
  text including the `-----BEGIN/END PRIVATE KEY-----` lines.
- **`errSecInternalComponent` while codesigning** → ensure `setup_ci` runs (it does when `CI=true`,
  which GitHub Actions sets automatically).
- **Build rejected: duplicate build number** → re-run after another bump (`make beta`); TestFlight
  requires a strictly increasing `CFBundleVersion` per marketing version.
- **TestFlight upload: "no app record"** → create the app in App Store Connect (step 2).

## Open questions
- Certs repo name assumed `bervion/vaultify-ios-certificates` — update `fastlane/Matchfile` if you use a different name.

## Private Email on TestFlight

TestFlight uses CloudKit Production. Verify the private `Vault` zone supports record type
`RelayPrincipalEscrow` and its `sealed` field in the deployed Production schema. A missing
schema, inaccessible iCloud account, or an escrow that cannot be opened with this vault key
can block both email verification and alias creation before any relay request is sent.
Do not delete or replace an existing escrow to troubleshoot: it owns existing relay aliases.
Vault-item sync does not need to be enabled for this escrow.

Use the `com.bervion.vaultify` / `relay` log category to distinguish `Principal escrow failed`,
`App Attest failed`, and `Relay command failed`. Logs contain error codes, not inboxes or keys.
A successful `GET https://api-relay.looxpassword.com/v1/relay/service-state` confirms only
service availability, not successful CloudKit access, App Attest, or mail delivery. Validate
on a physical TestFlight device: confirm inbox, open the verification link, refresh status,
activate an alias, then verify forwarding. Simulator tests cannot validate App Attest.

`Principal escrow failed: domain=CKErrorDomain code=9` means CloudKit authentication is
unavailable (`notAuthenticated`), before the relay call. On Simulator, check iCloud sign-in
inside Simulator Settings. This is distinct from a missing Production schema. Use a real
iPhone for the complete App Attest-protected relay flow; simulator logs cannot establish
the cause of a separate TestFlight failure. The app surfaces an account-specific message.
