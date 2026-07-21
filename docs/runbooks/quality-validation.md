# Runbook: quality validation

Use this runbook to reproduce the pull-request quality lanes. The canonical toolchain is
Tuist 4.200.1, Xcode 26.5, the iOS 26.5 simulator runtime and iPhone 17 Pro. Version or
runtime mismatches fail; the scripts do not select a nearby fallback.

## Prerequisites

- macOS with Xcode 26.5 and the iOS 26.5 simulator runtime;
- an iPhone 17 Pro simulator device type supplied by that Xcode installation;
- `mise`, which installs Tuist 4.200.1 from `.mise.toml`;
- Python 3 and Git;
- network access the first time Tuist dependencies and Maestro are installed.

The project deployment target remains iOS 17.3. Because the quality lane executes on iOS
26.5, iOS 17.3 currently has compile-only compatibility coverage. Do not claim runtime
compatibility with 17.3 until that simulator/runtime or a device is available and tested.

## Governance gate

From the repository root, regenerate the report before checking it:

```bash
python3 scripts/quality/report.py
scripts/ci/run-quality-contract.sh
```

CI supplies the full base commit to include the candidate diff:

```bash
scripts/ci/run-quality-contract.sh <40-character-base-commit>
```

The wrapper checks generated reports, schemas and references, runs the Python test suite,
scans the working-tree or base-commit diff for anti-cheating patterns, and runs
`git diff --check`. To scan a saved diff explicitly:

```bash
python3 scripts/quality/check_diff.py --diff-file /tmp/vaultify-pr.diff
```

The gate fails on malformed JSON-compatible YAML, duplicate IDs, broken references,
missing critical fixtures, missing source/test/evidence paths, stale evidence, artifact
digest mismatch, incomplete redaction metadata, undeclared PR impact, prohibited diff
patterns or a stale generated report.

## Full local quality lane

Use fresh output paths because `xcodebuild` refuses to overwrite an existing result
bundle:

```bash
export DEVELOPER_DIR="$(scripts/ci/select-xcode.sh | tail -n 1)"
mise install
scripts/ci/prepare-project.sh

receipt_root="$(mktemp -d /tmp/vaultify-quality.XXXXXX)"
simulator_udid="$(scripts/ci/create-simulator.sh | tail -n 1)"

scripts/ci/run-xcode-suite.sh \
  VaultifyTests \
  "$simulator_udid" \
  "$receipt_root/unit-dd" \
  "$receipt_root/unit.xcresult"

scripts/ci/run-xcode-suite.sh \
  VaultifySnapshotTests \
  "$simulator_udid" \
  "$receipt_root/snapshot-dd" \
  "$receipt_root/snapshot.xcresult"

scripts/ci/run-xcode-suite.sh \
  VaultifyUITests \
  "$simulator_udid" \
  "$receipt_root/ui-dd" \
  "$receipt_root/ui.xcresult"

scripts/ci/run-maestro-critical.sh \
  "$simulator_udid" \
  "$receipt_root/ui-dd" \
  "$receipt_root/maestro"

printf 'Receipts: %s\n' "$receipt_root"
```

`run-maestro-critical.sh` installs the app produced by the native UI target, then runs
`quality/maestro/vault-edit-save-relock.yaml` with the synthetic Debug-only fixture.
Release products ignore the fixture arguments.

After retaining the receipts you need, remove the isolated simulator:

```bash
xcrun simctl shutdown "$simulator_udid"
xcrun simctl delete "$simulator_udid"
```

## Receipts and failure behavior

| Lane | Receipt | Summary |
|---|---|---|
| Unit | `unit.xcresult` | `unit.xcresult.summary.json` |
| Snapshot | `snapshot.xcresult` | `snapshot.xcresult.summary.json` |
| XCUITest | `ui.xcresult` | `ui.xcresult.summary.json` |
| Maestro | `maestro/maestro.xml` | JUnit XML plus `debug/` and `artifacts/` |

`run-xcode-suite.sh` preserves the original `xcodebuild` exit status after attempting to
write the machine-readable summary. A test failure therefore stays red even when a result
bundle was produced. CI uploads these receipts with `if: always()` for 14 days; a missing
artifact produces a warning and does not hide the failing test step.

Maestro is pinned to 2.4.0. `scripts/ci/install-maestro.sh` downloads the official archive
and verifies SHA-256
`aea22ce67ab6718997ec990c58652ede0c2be8f10ac4799039ca3dce3390d634` before installation.
It also checks the installed CLI version and disables Maestro analytics.

## Adding or changing a product surface

1. Update `.goclaw/pr-impact.yaml` before implementation.
2. Reuse a stable ID only when its user-visible semantics are unchanged.
3. Add states and directed transitions; keep journey transition chains continuous.
4. Mark new inventory `known` and link source paths.
5. Register deterministic synthetic fixtures for every critical state and journey.
6. Update the visual matrix and risk register when the new behavior changes their scope.
7. Capture independent evidence, then promote only the covered records to `verified`.
8. Regenerate the coverage report.

## Anti-cheating authorization

Repository-authored exceptions are forbidden because candidate code could approve itself.
The default-branch `Trusted PR policy` job downloads the PR diff without checking out or
executing candidate code and runs the base branch's scanner. Because
`pull_request_target` itself is associated with the base ref, the trusted job publishes a
fixed `Trusted PR policy` commit status directly onto the independently fetched PR head SHA;
branch protection must require that exact context. Policy/workflow changes,
snapshot baselines and protected test deletions proceed only after a `bervion` APPROVED
review whose `commit_id` equals the current PR head. Even that exact-head approval never
permits skipped/disabled tests, snapshot record mode or weakened precision.
The privileged workflow intentionally has no `pull_request_review` trigger because that
event can select candidate/merge-ref workflow content. After approving the exact head,
`bervion` re-runs the failed trusted-policy workflow run; the trusted base workflow queries
the current review state and replaces the same head status with success.

The protected trust base includes all workflows, GoClaw project policy, quality contracts,
quality/CI scripts, toolchain pins, Tuist test topology and test sources. This prevents a
candidate from replacing a wrapper with `exit 0`, weakening a schema, or silently swapping
the test target while leaving the visible gate green.

## Failure handling

- Fix source ledgers rather than generated reports.
- Do not change a fixture or expected output merely to make a regression disappear.
- Repeated Swift `TaskLocal`/malloc aborts on an iOS 26.2 simulator are a known runtime
  failure. Re-run on the required iOS 26.5 runtime; do not add production `deinit`
  workarounds for that simulator defect.
- If `select-xcode.sh`, `create-simulator.sh` or `prepare-project.sh` reports a missing or
  mismatched pin, install the required version. Do not relax the check in a PR.
- If Maestro cannot find `Vaultify.app`, run `VaultifyUITests` first and pass the same
  derived-data directory to `run-maestro-critical.sh`.
- If evidence contains user data or credentials, stop distribution, remove the artifact
  from the branch, rotate exposed credentials where applicable and recapture with synthetic
  data.
- If a critical proof becomes stale, set the affected record to `stale` and block release
  until independent verification runs again.

## Rollback

Revert the governance change on its feature branch and regenerate the report. This layer
does not mutate user vaults, signing state, GoClaw runtime state or GitHub protections.

See [Verification evidence contract](../testing/evidence-contract.md), [Vaultify quality
ledger](../testing/quality-ledger.md) and [CI and release operations](./ci-release-operations.md).
