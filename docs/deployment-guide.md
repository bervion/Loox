# Deployment Guide — CI/CD & TestFlight

Vaultify ships to TestFlight via **GitHub Actions on a self-hosted macOS runner**, signed with **fastlane match**, uploaded with an **App Store Connect API key**.

```
make release  →  bump version + AI notes + tag vX.Y.Z  →  push
                                                            │
                          GitHub Actions (self-hosted) ◄────┘  (tag v*)
                                  │
                 match (App Store certs/profiles, app + AutoFill ext)
                                  │
                 build_app → upload_to_testflight (ASC API key)
```

| Component | Value |
|---|---|
| App bundle id | `com.bervion.vaultify` |
| AutoFill ext bundle id | `com.bervion.vaultify.autofill` |
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
Both bundle ids must exist as **explicit App IDs** with the capabilities the app uses:

- `com.bervion.vaultify` → enable **App Groups** (`group.com.bervion.vaultify`) + **AutoFill Credential Provider**.
- `com.bervion.vaultify.autofill` → enable **App Groups** (same group) + **AutoFill Credential Provider**.

> match generates profiles from each App ID's enabled capabilities. If you add a
> capability later, re-run `make certificates` after `bundle exec fastlane match nuke distribution` (or `match appstore --force`) so profiles regenerate.

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
- Keep the runner online; default label `self-hosted` matches the workflows

---

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

## How it works

- `.github/workflows/ci.yml` — on push to `main` / PRs: compiles the app scheme
  (builds the embedded AutoFill extension too), no signing. Fast feedback.
- `.github/workflows/release-ios.yml` — on tag `v*`: `bundle install` → `fastlane build_and_upload`.
- `fastlane/Fastfile` `build_and_upload`: `setup_ci` (temp keychain) → `match` (readonly,
  both app + ext) → force Manual signing per target → `build_app` (app-store export with
  both profiles) → `upload_to_testflight`.

The build number is whatever is committed in the pbxproj at the tagged commit, so it is
unique and increasing for every upload (each `make release`/`make beta`/`make hotfix` bumps it).

---

## Troubleshooting

- **`No profiles for 'com.bervion.vaultify.autofill'`** → the extension App ID is missing
  or its capabilities differ. Fix the App ID (step 1), then `bundle exec fastlane match appstore --force`.
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
