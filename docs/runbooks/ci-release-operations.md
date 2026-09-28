# Runbook: CI and release operations

Vaultify separates untrusted pull-request validation from signing and TestFlight upload.
There are exactly two workflows:

| File | Trigger | Runner |
|---|---|---|
| `.github/workflows/ci.yml` | pull requests to `main`, non-tag pushes to `main` | self-hosted `vaultify-ci` |
| `.github/workflows/release-ios.yml` | `v*` tags | self-hosted `vaultify-release` |

Nothing else exists. Earlier revisions of this runbook described a `release-evidence.yml`
workflow, a `quality/release/readiness.yaml` gate file and seven extra CI jobs; none of
them were ever committed. Treat any gate not listed below as absent, not as pending.

## Pull-request and main CI

`ci.yml` runs one job.

| Job name | Host | Purpose |
|---|---|---|
| Unit tests | self-hosted `vaultify-ci` | `VaultifyTests` (XCTest + Swift Testing) via `scripts/ci/run-xcode-suite.sh` |

It creates a throwaway simulator, runs the suite, uploads
`unit-test-receipt-<attempt>` (the `.xcresult` plus its `summary.json`), and deletes the
simulator. `create-simulator.sh` also sweeps orphan `Vaultify Quality *` devices left by
cancelled jobs, because the runner is persistent.

Snapshot and critical-UI jobs are **deliberately not** in CI. They were removed in
`1d64d656` because they tripled the wall time of every run on the single self-hosted
runner. `Vaultify-Quality` still carries all three test targets, so run them locally with
`make test` before tagging.

Pull-request CI is secret-free by design. Candidate code executes on the runner host, so
`vaultify-ci` must stay a separate runner instance from `vaultify-release`, must never hold
signing material, and any future third-party contribution model requires revisiting this.
Checkout credentials are not persisted, and the job checks out the PR head rather than the
synthetic merge ref so the receipt binds to the candidate SHA.

## Toolchain pin policy

`scripts/ci/toolchain-pin.sh` is the single source of truth. Both other scripts source it,
so the Xcode pin and the simulator-runtime pin cannot drift apart.

| Constant | Value | Meaning |
|---|---|---|
| `MINIMUM_XCODE_VERSION` | `26.5` | oldest Xcode allowed to test or release |
| `MINIMUM_IOS_RUNTIME_VERSION` | `26.0` | oldest simulator runtime allowed to host the suites |
| `SIMULATOR_DEVICE_TYPE` | `iPhone 17 Pro` | device the suites run on |

This is a **minimum**, not an exact match. An exact `26.5` string pin was the previous
policy and it failed the moment a machine took a patch update; with three machines
(maintainer, `vaultify-ci`, `vaultify-release`) updating independently, nobody could say
whether a tag would build until it already had not.

Selection rules:

- `select-xcode.sh` considers every `/Applications/Xcode*.app` plus whatever `xcode-select`
  points at, rejects any install whose `xcodebuild -showsdks` fails (an unaccepted license
  is the common case, and `-version` alone does not catch it), and picks the **lowest**
  qualifying version so a beta install is never selected silently. Every rejection is
  printed with its reason.
- `create-simulator.sh` picks the lowest available iOS runtime that meets the minimum
  **and** whose major does not exceed the selected Xcode's major, because a runtime newer
  than the toolchain is installed but unusable. It prints the full runtime inventory when
  nothing qualifies.
- Both print their selection, so a job log always records the toolchain that produced it.

Reproduce the CI toolchain locally:

```bash
export DEVELOPER_DIR="$(scripts/ci/select-xcode.sh | tail -n 1)"
udid="$(scripts/ci/create-simulator.sh | tail -n 1)"
```

`make test` does exactly this, runs `Vaultify-Quality` against that UDID, then deletes the
simulator. `make check` is a compile check only, so it uses a generic destination.

Snapshot references are recorded at a pinned `displayScale` (see
`VaultifySnapshotTests/SnapshotEnvironment.swift`), so they are valid on any device. They
are still tied to the rendering of one iOS version: re-record after a runtime bump and
review the diff instead of accepting it.

## Release boundary

A `v*` tag triggers `release-ios.yml`. Signing and upload run only on a self-hosted runner
carrying every label below:

```text
self-hosted, macOS, ARM64, vaultify-release
```

The job is attached to the `production-ios-release` environment and proceeds only when both
`github.actor` and `github.triggering_actor` equal `bervion`. It then verifies, in order:

1. the tagged commit is reachable from `origin/main`;
2. **the exact tag SHA has a completed, successful `ci.yml` run** — evidence is bound to the
   commit, so a green run on a later `main` commit does not qualify;
3. the tag matches `MARKETING_VERSION` (`vX.Y.Z` or `vX.Y.Z-beta.*`);
4. `LOOX_LINK_PROD_TOKEN` is configured;
5. project generation succeeds with the pinned toolchain;
6. fastlane retrieves signing material, uploads dSYMs to Crashlytics, and uploads to
   TestFlight.

The current private repository plan does not provide enforceable environment required
reviewers: the API request to add that protection returned HTTP 422. The environment name
must not be described as human approval enforcement. The fallback is an immutable release
tag created by `bervion`, plus the actor and triggering-actor condition above. A plan
upgrade or another separately enforced owner-approval mechanism is still required before
claiming protected-environment approval.

## Release procedure

Before creating a release tag:

1. merge only after a green PR run and owner review;
2. confirm the candidate commit on `main` has a green `ci.yml` run — that same run is what
   the release job re-checks, so a red or missing one blocks the tag;
3. run `make test` locally on the pinned toolchain and confirm unit, snapshot and UI targets
   are green; CI does not cover snapshot or UI;
4. complete non-empty release notes (`docs/releases/TEMPLATE.md`) and the localized
   `metadata/apple/*/release_notes.txt` that `make notes` generates;
5. confirm the worktree is clean and the candidate commit is on `main`;
6. create and push the immutable version tag as `bervion` (`make release` does the bump,
   notes and tag);
7. monitor `Sign and upload to TestFlight` and retain its logs without exposing secrets.

A passing local test run is necessary but not sufficient: the release job trusts the
`ci.yml` receipt for the tagged SHA, nothing else.

## Compile-only release check

This unsigned check compiles the Release configuration without touching signing state:

```bash
export DEVELOPER_DIR="$(scripts/ci/select-xcode.sh | tail -n 1)"
mise install
scripts/ci/prepare-project.sh
release_root="$(mktemp -d /tmp/vaultify-release.XXXXXX)"
xcodebuild \
  -workspace Vaultify.xcworkspace \
  -scheme Vaultify \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$release_root/dd" \
  CODE_SIGNING_ALLOWED=NO
```

This verifies the iOS 17.3 deployment setting compiles on the selected toolchain. It does
not execute the app on iOS 17.3.

## Troubleshooting

- **Release job is skipped:** confirm the tag creation and any rerun were initiated by
  `bervion`; both GitHub actor fields are checked.
- **"No successful ci.yml run for `<sha>`":** the tagged commit was never validated. Do not
  move the tag. Push the commit to a branch, let CI run it, then tag a commit that has a
  green receipt.
- **Tag is not reachable from main:** do not move the tag. Merge a reviewed fix to `main`
  and create a new version tag.
- **Tag/version mismatch:** fix `MARKETING_VERSION` through the normal release process and
  create a new tag; never reuse a published tag.
- **"No installed Xcode satisfies the minimum":** the step prints every install it found
  and why each was rejected. An "unusable: You have not agreed to the Xcode license
  agreements" line means `sudo xcodebuild -license accept` on that runner, not a version
  bump.
- **"No installed iOS simulator runtime satisfies the policy":** the step prints the runtime
  inventory. Either install the runtime through Xcode, or move
  `MINIMUM_IOS_RUNTIME_VERSION` deliberately and re-record snapshot references.
- **`vaultify.icon` "is a directory", or actool "no icon stack named vaultify" / "attempt
  to insert nil object":** Launch Services on that machine does not know the Icon Composer
  `.icon` type, which Tuist needs to keep the app icon and actool needs to compile it.
  `prepare-project.sh` registers the selected Xcode's `Icon Composer.app` on every run. If
  the icon is still dropped, run that `lsregister -f` command as the runner user in its
  logged-in session and re-run the job. If actool still crashes afterwards, `killall
  ibtoold` (actool reuses that daemon) and re-run. Do not glob the icon to silence Tuist;
  that only moves the failure into actool.
- **Runner is queued:** verify the online runner has all four required labels.
- **Protected reviewer API returns HTTP 422:** the current plan cannot enforce that rule.
  Keep the owner-tag fallback and record the residual gate; do not report it as resolved.
- **Missing secret:** configure it in the appropriate GitHub secret scope. Never print the
  value or place it in a pull-request workflow.
- **Upload fails after signing:** retain the failed job log, correct the cause and publish a
  new build number/tag. Do not overwrite or re-point an immutable tag.

## Rollback

Before TestFlight upload, cancel the job and fix forward on a new reviewed commit. After an
upload, TestFlight artifacts are immutable: expire the affected build in App Store Connect
when appropriate, then ship a corrected build with a higher build number. Reverting source
or workflow files does not withdraw an uploaded binary.

There is no automated recovery-rehearsal workflow. Downgrade rehearsal, if it is ever
needed, is a manual local exercise: check out the previous tag, give it the candidate
marketing version with a higher build number, install it over the candidate on a simulator
while retaining the data container, and confirm it unlocks and reads real candidate-format
vault data. A matching container path or PID is not recovery evidence.
