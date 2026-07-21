# Runbook: CI and release operations

Vaultify separates untrusted pull-request validation from signing and TestFlight upload.
The workflows are `.github/workflows/ci.yml`, `.github/workflows/release-evidence.yml` and
`.github/workflows/release-ios.yml`.

## Pull-request and main CI

CI runs for pull requests to `main` and non-release pushes to `main`.

| Job name | Host | Purpose |
|---|---|---|
| Trusted PR policy | `ubuntu-24.04` | Base-branch scanner over the untrusted API diff; exact-head status and owner gate |
| Quality contract | `ubuntu-24.04` | Ledger, report, schema, diff and anti-cheating checks |
| Unit tests | `macos-26` | XCTest and Swift Testing in `VaultifyTests` |
| Snapshot tests | `macos-26` | Approved `VaultifySnapshotTests` comparisons |
| Critical UI journey | `macos-26` | Native XCUITest followed by independent Maestro flow |
| Ledger evidence | `ubuntu-24.04` | Emits the critical-ledger predicate for the exact SHA |
| Test evidence | `ubuntu-24.04` | Aggregates hard dependencies on unit, snapshot, XCUITest and Maestro |
| Privacy contract | `ubuntu-24.04` | Emits fail-closed until executable privacy receipts are promoted |
| Localization contract | `ubuntu-24.04` | Checks non-empty EN/VI copy and verified accessibility cases |
| Risk disposition | `ubuntu-24.04` | Rejects open critical/high or invalid dispositions |
| Release operations | `ubuntu-24.04` | Checks release notes and owner-approved monitoring inputs |

The three macOS jobs require the quality contract and use Xcode 26.5, Tuist 4.200.1,
iOS 26.5 and iPhone 17 Pro. Each job creates a fresh simulator. The macOS jobs run in
parallel after the contract succeeds.

Pull-request CI jobs are secret-free and use GitHub-hosted runners. Checkout credentials are
not persisted, and test jobs explicitly check out the PR head rather than the synthetic
merge ref so receipts bind to the candidate SHA. Candidate code can run in these jobs, so signing certificates, App Store
Connect credentials, match credentials and production tokens must never be added to this
workflow.

Artifacts are documented in [Quality validation](./quality-validation.md). The corresponding
GitHub artifact names are `unit-test-receipt-<attempt>`,
`snapshot-test-receipt-<attempt>`, `critical-ui-receipts-<attempt>`,
`ledger-evidence-receipt-<attempt>`, `test-evidence-receipt-<attempt>`,
`privacy-contract-receipt-<attempt>`, `localization-contract-receipt-<attempt>`,
`risk-disposition-receipt-<attempt>` and `release-operations-receipt-<attempt>`.
The manual recovery workflow emits `recovery-rehearsal-receipt-<attempt>`.

## Agent review trust boundary

Pull-request titles, bodies, diffs, comments and repository files are attacker-controlled.
This workflow therefore does not send PR content to the general tool-capable GoClaw webhook.
Discord receives only a no-mentions review-needed notification. Rex must be started by the
owner through a bounded verification lane. Automatic Rex review remains release-blocked
until the server provides and receipts all three controls: a read-only repository token,
an allowlisted read-only tool set with no general shell/write capability, and an ephemeral
per-PR workspace/memory scope. Prompt wording is not accepted as a substitute for those
controls.

## Required-check rollout

Do not configure branch protection from unproven job names. First push this change as a
pull request and obtain one green canary run. Confirm these exact check names in GitHub:

- `Quality contract`;
- `Trusted PR policy`;
- `Unit tests`;
- `Snapshot tests`;
- `Critical UI journey`.

The bootstrap PR that first installs `Trusted PR policy` cannot be protected by code that is
not yet on the default branch; it requires manual owner review. After it lands, run a second
green canary and only then require all five names on `main`.

Rollout status: the merged bootstrap canary (PR #134, green run 29797704103) proved
`Quality contract`, `Unit tests`, `Snapshot tests` and `Critical UI journey` under those
exact names. `Trusted PR policy` executes from the default branch only, so it is proven by
the first pull request opened after that merge; the five contexts become required on `main`
once that status reports success on the candidate head.
The required `Trusted PR policy` context is a commit status written by the trusted workflow
to the verified PR head SHA; do not substitute the base-ref workflow conclusion.
For a protected TCB change, approve the exact PR head and then re-run its existing
`pull_request_target` policy run. Do not add `pull_request_review` to this privileged
workflow: that event does not provide the same default-branch workflow trust boundary.

On a personal private repository, same-repository contributor workflows can request
`statuses: write` and post another status under the GitHub Actions App. Consequently,
required check names are defense in depth, not the sole authorization boundary. The
non-spoofable human boundary is a fresh `bervion` CODEOWNER approval: dismiss stale reviews,
require code-owner review, require approval by someone other than the last pusher, enforce
protection for admins, and require all conversations resolved. Do not claim the status itself
is unforgeable until contributions are fork-only or a separately authenticated GitHub App
owns the expected status source.
Until then, the existing review rule remains the enforced branch gate and the missing
required checks remain an explicit rollout gap.

## Release boundary

A `v*` tag triggers the release workflow. Signing and upload run only on a self-hosted
runner carrying every label below:

```text
self-hosted, macOS, ARM64, vaultify-release
```

The job is attached to the `production-ios-release` environment and proceeds only when
both `github.actor` and `github.triggering_actor` equal `bervion`. It then verifies that:

1. the tagged commit is reachable from `origin/main`;
2. the tag matches `MARKETING_VERSION` (`vX.Y.Z` or `vX.Y.Z-beta.*`);
3. `LOOX_LINK_PROD_TOKEN` is configured;
4. project generation succeeds with the pinned toolchain;
5. fastlane can retrieve signing material and upload with App Store Connect credentials.

The current private repository plan does not provide enforceable environment required
reviewers: the API request to add that protection returned HTTP 422. The environment name
must not be described as human approval enforcement. The current fallback is an immutable
release tag created by `bervion`, plus the actor and triggering-actor condition above. A
plan upgrade or another separately enforced owner-approval mechanism is still required
before claiming protected-environment approval.

## Release procedure

Before creating a release tag:

1. merge only after the green PR canary and owner review;
2. confirm all required release gates in `quality/release/readiness.yaml` have independent
   evidence for the exact commit;
3. ensure every critical/high risk is evidenced as mitigated or explicitly accepted by
   `bervion`; open critical/high risk always blocks preflight;
4. complete non-empty release notes from `docs/releases/TEMPLATE.md` and bind the exact tag,
   metrics, alerts, incident channel and fix-forward runbook in
   `quality/release/operations.yaml`;
5. download the successful gate payloads, promote their byte-identical hashes plus Actions
   run/job/artifact attestations into the evidence index, then run release preflight with a
   token that has Actions read access;
6. confirm the worktree is clean and the candidate commit is on `main`;
7. create and push the immutable version tag as `bervion`;
8. monitor `Sign and upload to TestFlight` and retain its logs without exposing secrets.

The readiness file currently starts `not-evaluated` with every gate false. A passing local
test or an uncommitted working-tree run does not authorize a tag.

## Compile-only release check

This unsigned check compiles Release configuration without touching signing state:

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

This verifies the iOS 17.3 deployment setting compiles with Xcode 26.5. It does not execute
the app on iOS 17.3 and is not a substitute for the release readiness gates.

## Troubleshooting

- **Release job is skipped:** confirm the tag creation and any rerun were initiated by
  `bervion`; both GitHub actor fields are checked.
- **Tag is not reachable from main:** do not move the tag. Merge a reviewed fix to `main`
  and create a new version tag.
- **Tag/version mismatch:** fix `MARKETING_VERSION` through the normal release process and
  create a new tag; never reuse a published tag.
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

Dispatch the default-branch recovery workflow as `bervion`; `repository_dispatch` is used so
an arbitrary branch cannot supply the workflow definition executed by the persistent runner:

```bash
gh api --method POST repos/bervion/Vaultify/dispatches \
  -f event_type=vaultify-recovery-rehearsal \
  -f 'client_payload[previous_tag]=vX.Y.Z'
```

The default-branch SHA must be reachable from `origin/main`, and the immutable prior tag must
be its ancestor. The job rebuilds the candidate and previous source, assigns the previous
source the candidate marketing version plus a higher build number, installs it over the
candidate while retaining the simulator data container, and relaunches it. This is a
fix-forward rehearsal, not an App Store/TestFlight downgrade. The gate remains failed until
the workflow can seed candidate-format encrypted vault data and functionally prove the
previous-source build unlocks and reads the sentinel; a matching container path or PID is
never sufficient production recovery evidence.
