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
| App locales | en, vi, ja |

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
make test TEST_TARGETS=VaultifyTests  # local unit scope used by CI/release
make submit-ios  # submit the latest TestFlight build to App Store review
```

**Version bump** is driven by conventional commit prefixes since the last tag:
`feat!`/`BREAKING CHANGE` → major · `feat` → minor · `fix`/`perf`/other → patch.
`make release` writes `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` into `Project.swift`
(app and extensions together), generates EN/VI release notes via the Claude CLI,
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

- `.github/workflows/ci.yml` — on push to `main` / PRs: runs `VaultifyTests` (XCTest +
  Swift Testing) through `Vaultify-UnitTests`, with ad-hoc signing for hosted Keychain tests.
  Snapshot/UI tests are optional local checks through `Vaultify-Quality`; `make test`
  still selects all three targets by default.
- `.github/workflows/release-ios.yml` — on tag `v*`: requires successful unit CI on the
  exact tag SHA, then `bundle install` → `fastlane build_and_upload`. The signed archive
  continues to use the app's `Vaultify` scheme.
- `fastlane/Fastfile` `build_and_upload`: `setup_ci` (temp keychain) → `match` (readonly,
  app + AutoFill ext + Safari ext) → force Manual signing per target → `build_app`
  (app-store export with all three profiles) → `upload_to_testflight`.

`scripts/ci/prepare-project.sh` validates exact manifest package versions against the
tracked `.package.resolved` and seeds the generated workspace's lockfile for both CI
and signed releases. Unit CI caches only Swift package repositories/checkouts, keyed
to the lock and selected toolchain. It still compiles the candidate and creates a fresh
simulator; binary-package downloads are not cached. Timing savings have not been measured.
Detailed test scope and release boundaries are in the [CI runbook](runbooks/ci-release-operations.md).

The build number is whatever is committed in `Project.swift` at the tagged commit, so it is
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

## Private Email device setup and verification

Normal **Debug and Release/TestFlight use production App Attest** and the production
relay API (`https://api-relay.looxpassword.com`), whose mail ingress is production-only.
The signed domain registry also uses production
(`https://config.looxpassword.com/v1/domain-registry`) in both normal configurations.
Debug's **APNs remains development**. CloudKit's configuration is separate: Debug
uses Development, while TestFlight uses Production. Link and Quick View retain their
existing staging API defaults in Debug.

For a normal Xcode device run:

1. Run `make gen` after pulling changes, switching branches, or changing generation
   settings. Open **`Vaultify.xcworkspace`**.
2. Select the app scheme **Vaultify**, its **Debug** configuration, and a physical
   iPhone. Simulator cannot exercise App Attest.
3. Sign with team `WDNL2F75V7` and a current app provisioning profile that grants
   **App Attest**, plus the existing iCloud/CloudKit capability. If App Attest was
   just enabled on the App ID, refresh the development profile too; the App Store
   profile used by TestFlight must also grant it (§1b).
4. Sign into iCloud on the iPhone and unlock the existing vault. Vault-item sync may
   remain off; Private Email's encrypted relay identity uses its own CloudKit path.
5. Open **Settings → Private Email diagnostics** in Debug. Its Configuration section
   should show relay host `api-relay.looxpassword.com`, App Attest environment
   `production`, and App Attest supported. Retry the inbox-confirmation action and
   refresh the log to locate the failing stage.

Apple sandbox enrollment tests are opt-in at **project generation time**:

```bash
TUIST_APP_ATTEST_DEBUG_ENVIRONMENT=development make gen
```

This changes only Apple's attestation environment in Debug. The relay API stays
production in every normal app configuration, keeping persisted aliases and
destination ids on the backend that owns them. Release remains production even if
the variable is present during generation. Run `make gen` again without it to return
to normal device testing. Use this option for targeted enrollment tests, not the
normal inbox-confirmation or mail-forwarding checks.

App Attest key id, registration and install markers are scoped by relay host **and
Apple's attestation environment**. Ambiguous host-only predecessor state starts a
fresh device-key enrollment, preserving the relay principal, escrow and aliases.
An explicit `attestation_key_unknown` response permits one re-enrollment retry with
a fresh command transcript. The reset atomically matches the rejected key id so a
late response cannot clear a newer enrollment. A generic 401 does not retry. Do not
delete the app, erase the vault, or replace its relay principal as part of this
verification.

The inbox-first path (`beginDestinationVerification`, kind 7) now carries its
genesis public key at epoch 1. The deployed backend already supported kind-7
principal genesis. The **recovery-only hotfix was deployed on 2026-10-07** and these
versions were verified active at 100% traffic:

| Relay environment | Active version | Traffic |
|---|---|---|
| Production | `e2959c69-8dc7-4a2c-b7f3-22bf6328ee3b` | 100% |
| Staging | `4aa037db-0e70-4d98-8617-6017e259c9b3` | 100% |

Downloaded active code from both environments matches SHA-256
`67963ab0371fa54c780bf84a94d438f79ecbd44e18d1c54c0086ee949bc5c74c`.
Compiled baseline tests had **9 passes and 2 expected recovery-signal failures per
environment**; patched tests passed **11/11 per environment**. Three live negative
checks per environment verified: unknown App Attest key returns **401
`attestation_key_unknown`**, a missing assertion remains `unauthorized`, and an
invalid principal signature remains `bad_signature`. `/health/ready` was `true`
on both environments. These checks did not send email or reset identities, DB
schema or vault data.

The upload used captured live bindings, and the promotion configuration contained
only version/traffic selection; nonversioned Worker settings were not synchronized.
Captured live configuration remained unchanged. The local audit receipt is
`/tmp/vaultify-relay-auth-release-20261007/deployment-receipt.json`. It records the
previous production version `ee6a8439-04bb-4143-a597-b3f3a368fce6` and staging version
`4b6d56f4-8f21-44f3-9d6d-632e34e07b60` for version rollback, together with their
original code hash
`c13d41c249cfe8aa991bfcc8f7b44623390da3d68ceb8195641c330f290c0d57`.
Any rollback should promote those captured versions while preserving the live
bindings and nonversioned settings.

**Native/device status:** release **1.56.6 (95)** includes the client fixes. The
pre-release investigation used a working Debug binary and TestFlight **1.56.4**;
the Debug binary still displayed **1.56.5 (94)** before the release bump. Confirm
the new build has finished App Store Connect processing before testing it. Record
the actual installed TestFlight version and available Console relay failure metadata
(error domain/code, stage, HTTP status and backend code) before diagnosing that
binary. Older binaries may have only the `relay` category; `relay-diagnostics`
requires a binary containing the new client diagnostics. Physical-iPhone Apple
attestation and production mail delivery remain **unverified by us**; backend
negative checks do not establish those device results.

| Device run | App Attest / relay | Required verification |
|---|---|---|
| Xcode Debug, normal generation | Production / production | Confirm inbox first, open its verification email, refresh to verified, activate an alias, then verify external mail forwarding. Inspect the Debug diagnostics log. |
| Xcode Debug, optional Apple sandbox generation | Development / production | Confirm supported device and production relay host, then inspect targeted enrollment results. Return to normal generation for inbox confirmation and forwarding. |
| TestFlight on physical iPhone | Production / production | Repeat inbox confirmation and forwarding with CloudKit Production schema deployed. Also verify an existing alias remains visible and manageable after the new device-key enrollment. Collect Console `relay-diagnostics` metadata. |

Debug diagnostics store only sanitized technical metadata in
`Documents/relay-diagnostics.log`; the Settings entry can copy, refresh or clear that
log. Release/TestFlight binaries containing the new diagnostics have no diagnostics
file or Settings entry. Use Console with subsystem **`com.bervion.vaultify`**,
category **`relay-diagnostics`**. Logs omit inboxes,
vault values, principal/device identifiers, request bodies and keys.

### CloudKit and escrow diagnosis

TestFlight uses CloudKit Production. Verify the private `Vault` zone supports record type
`RelayPrincipalEscrow` and its `sealed` field in the deployed Production schema. A missing
schema, inaccessible iCloud account, or an escrow that cannot be opened with this vault key
can block both email verification and alias creation before any relay request is sent.
Do not delete or replace an existing escrow to troubleshoot: it owns existing relay aliases.
Vault-item sync does not need to be enabled for this escrow.

A successful `GET https://api-relay.looxpassword.com/v1/relay/service-state` confirms only
service availability, not successful CloudKit access, App Attest, or mail delivery. Validate
on a physical TestFlight device: confirm inbox, open the verification link, refresh status,
activate an alias, then verify forwarding. Simulator tests cannot validate App Attest.

`Principal escrow failed: domain=CKErrorDomain code=9` means CloudKit authentication is
unavailable (`notAuthenticated`), before the relay call. On Simulator, check iCloud sign-in
inside Simulator Settings. This is distinct from a missing Production schema. Use a real
iPhone for the complete App Attest-protected relay flow; simulator logs cannot establish
the cause of a separate TestFlight failure. The app surfaces an account-specific message.

`Principal escrow failed: domain=...EscrowFailure code=3` (`cannotOpenWithVaultKey`) means
the escrow loaded but this vault's key cannot open it. Deleting the app deletes the vault
and its key, while the escrow (and its Keychain cache) survives, so the next install's new
vault can never open it: the usual cause is reinstalling without restoring the vault. The
app surfaces "Private Email was set up with another vault". Preserve that escrow and the
existing vault while diagnosing. If the original vault is available on another device or
in its recovery material, restore that vault to regain access to the same relay identity.

The Production schema is not the cause when the record type is listed: CloudKit Console's
Production **Record Types** page shows "No record types found" for a few seconds while it
loads, which is easy to misread as a missing deploy.

### UI overhaul acceptance and domain readiness

The 2026-10-07 native UI changes are separate from the previously released
**1.56.6 (95)** attestation fixes. They have not bumped the app version or uploaded a new
candidate. Follow the existing release boundary after validating the final source tree.
The internal implementation report
separates synthetic native evidence from physical and production checks.

| Check | Required observable result |
|---|---|
| Inbox verification | Confirm in the browser, return to a relevant unlocked app screen and observe server-verified state. Pending visible polling resumes without a restart; no resend is triggered by a status check. |
| Recipient privacy | Open inbox detail to identify/copy its local email. Background, lock and exit conceal it; returning to foreground keeps it concealed. Alias detail separates last confirmed destination from a pending desired change. |
| Create/retry | Create without a Login, then link one later. A mint followed by routing failure retries the same reserved namespace/inbox. A domain losing creation eligibility before mint requires an explicit valid selection. |
| Linked services | Link one address to multiple owned Logins. Unlink one with confirmation; ordinary Email/username, sibling associations and alias forwarding remain intact. Restore an edited Login draft without losing its original relation baseline. |
| Resume forwarding | A paused alias is active only after backend resume acknowledgment on its original namespace. A policy refusal leaves it paused and surfaces the error. |
| Member destinations | Share Links, Send to Browser and Family open their own roots. Persona changes affect counts, lists and choosers consistently. Link history cannot reconstruct a working key; Browser history cannot replay a session. |
| Family | With two iCloud accounts/devices, exercise item and Space invitation, acceptance, ceremony, use, update and revoke. Approval Mode on with vault-item sync off must work. |
| Upgrade/offline | Existing aliases retain their suffix. A valid historical signed mapping resolves an issued nonlegacy alias; an unknown/unproved mapping remains unavailable for copy. |

On 2026-10-08, the missing production `loox.pw -> email-pw` ingress mapping was
provisioned by migration 0008. The owner confirmed fresh legacy-alias and apex
operational-inbox receipts, then D1 and signed production registry v15 were both
changed to `active`. Existing primary choices and issued suffixes were preserved.
Normal new-alias creation and mail receipt still require the physical app check.

The registry transport must bypass the OS HTTP cache on an explicit refresh.
Before the refresh fix, `refreshNow()` could accept cached v14 again for an hour
and the picker still showed "not open for new addresses" after v15 publication.
The picker now requests refresh on entry and pull-to-refresh through the existing
coordinator. Signature, environment, signed expiry and anti-rollback checks remain
mandatory; this does not enable an unverified domain. A registry that has not been
accepted still uses the bundled legacy-only fallback.

Before enabling `email-pw`, obtain read-only access to the correct live D1 configuration,
verify namespace and ingress routing, and prove actual production-apex delivery to a
verified controlled inbox while preserving a legacy-delivery regression receipt. An
OAuth login, health endpoint, simulator fixture or signed registry alone is not a mail
receipt. Keep the production catch-all on production during isolated staging checks.
Coordinate server lifecycle and a signed registry with a strictly increasing version
only after delivery proof. A UI-only release can keep `email-pw` disabled.

Rollback of new creation uses server and signed-registry `createDisabled` while preserving
existing ingress. Publish a new higher signed version; do not replay an older registry,
retire a namespace with issued aliases, delete vault data or replace the relay principal
to repair presentation. Native views/routes can be reverted independently of the sealed
backward-compatible fields and state guards.
