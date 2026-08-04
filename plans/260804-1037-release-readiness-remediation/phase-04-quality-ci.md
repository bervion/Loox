# Phase 4 — Quality gates and CI truth

One agent, no product-code overlap. Pull the tutorial-isolation fix forward — it is
S-effort and unblocks both failing UI tests, which every other phase's verification needs.

**Owns:** `VaultifySnapshotTests/**`, `VaultifyUITests/**` fixtures, `scripts/ci/**`,
`Makefile`, `.github/workflows/release-ios.yml`, `docs/runbooks/ci-release-operations.md`,
`docs/deployment-guide.md`, and the final doc pass on `README.md` / `AGENTS.md` /
`CLAUDE.md`.

---

## The three red suites — real causes, not the audit's hypotheses

### Snapshot: scale-bound references, not a rendering bug

All three snapshot tests fail. The failure is a **size** mismatch, not a pixel diff:

```
Newly-taken snapshot@(390.0, 700.0) does not match reference@(260.0, 466.67)
```

Every reference PNG is an **@2x** render (780×240 and 780×1400) being compared on an **@3x**
device — including CI's pinned iPhone 17 Pro (`scripts/ci/create-simulator.sh`). At
`displayScale` 3 they resolve to 260×466.67pt, so `SnapshotTesting` bails before comparing
a single pixel.

The arrow renders **complete** — shaft and head — on Xcode 27.0 / iOS 26.3. There is no SVG,
mask, or symbol-configuration bug. `ic_arrow_right.svg` is a single evenodd path with
`preserves-vector-representation` and template rendering intent, drawn through
`VaultIcon(Icons.arrowRight, …)` at `SlideToUnlock.swift:44`.

Fix: pin `displayScale` in the snapshot traits so the suite is device-independent, then
re-record all three references.

**One real visual regression is hiding behind this.** Commit `05444954` (2026-07-31) changed
the LockControl knob ring from `primaryText` to `accentForeground` and nobody re-recorded.
Human-review the new render against design intent before accepting the baseline — do not
just record to green.

### `VaultEditSaveRelockUITests` — the tutorial scrim, not a toolbar bug

The test never reaches the `item.detail.more` lookup. It dies three lines earlier at
`item.tap()`:

```
Failed to not hittable: Button, identifier: 'vault.item.ui-test-login.all'
```

The exported UI-hierarchy attachment at the moment of failure contains
"Add your first item", "Step 1 of 3", "Next", "Skip" — the first-run tutorial is on screen
and eating the taps.

`item.detail.more` is set correctly at `ItemDetailScreen.swift:302` on the `Menu` inside
`ToolbarItem(placement: .platformPrimaryAction)`. There is **no evidence** it is
unreachable on any toolchain; it has never been exercised. Do not refactor the toolbar.

### `VaultPanicRestartUITests` — same root cause

The last frame of the screen recording shows "Step 2 of 3 — Check your security" over Home:
the test's taps were advancing the tutorial rather than reaching `home.settings`.

**One fix for both:** mark tutorial flows `.skipped` under UI-test isolation in
`AppEnvironment.init` (implemented by Agent 2B, who owns that file) and add a launch
argument so a test that *does* want to exercise the tutorial can opt in. Per-test fixture
state, not a global.

### A fourth suite crashes

`TutorialTooltipSnapshotTests.testClosingStepCardWithoutSkip` does not merely fail — it
**crashes** the test host. Reproduce it on the pinned toolchain **before** touching app
code; it may be an Xcode 27 beta artifact rather than a product defect.

---

## M15 — the toolchain pin is one runner update from breaking every release

`scripts/ci/select-xcode.sh` hard-pins Xcode 26.5, which is installed nowhere on the
maintainer machine. Consequences:

- An unattended update on the self-hosted `vaultify-release` runner turns every `v*` tag
  into a job that fails **before** signing. It looks like an infrastructure outage, not a
  pin.
- The maintainer cannot reproduce the CI/release toolchain locally at all — which is
  precisely how the three suites above stayed misdiagnosed.

Fix: either bump `EXPECTED_XCODE_VERSION` to a version actually installed on the runner, or
relax to a documented minimum (accept ≥ 26.5 and print what was selected). Make the same
call for `EXPECTED_IOS_RUNTIME_VERSION` in `create-simulator.sh` so the two pins cannot
drift independently. Record the pin policy in the runbook next to the existing
"Runner is queued" entry.

## `make test` is guaranteed red

The documented local quality command fails because of the auto-generated scheme it targets.
Point `test` at `Vaultify-Quality`, drop the literal `build` action (the local hook blocks
the bare word), and fix `DEST` — `name=iPhone 16` does not resolve here; use
`generic/platform=iOS Simulator`.

## Release gate — close the hole without reversing the owner's decision

`.github/workflows/release-ios.yml` triggers directly on `v*` and has no dependency on a
green quality run for the same SHA. A tag can ship with zero test evidence.

**Add only the same-SHA gate.** Commit `1d64d656` removed the snapshot and critical-UI CI
jobs as an explicit owner decision with a stated reason — they tripled every run on the
self-hosted runner. Do not reverse that. The release job should verify that the exact tag
SHA has a green receipt from the required workflow, and refuse otherwise.

Same verdict on adding an iPad destination matrix to CI: not on this runner budget, and not
before OPEN-1 is settled.

## Runbook truth

`docs/runbooks/ci-release-operations.md` references `.github/workflows/release-evidence.yml`
and `quality/release/readiness.yaml`. **Neither file exists.** Rewrite the runbook to the
one-job / one-artifact reality rather than inventing the machinery to match the doc.

## Release compiler warnings

Seven code-level warnings in the Release configuration. Six are actor-isolation warnings
that become errors under Swift 6 strict concurrency; one ignores the return value of
`remove(group:)`.

- `IconPickerSheet.swift:21`
- `SpaceSeedIdentity.swift:23`
- `HomeAttention.swift:87`
- `Level2BiometricKeyStore.swift:137`
- `AttachmentStore.swift:33-34`
- `TutorialStore.swift:46`

Not blocking, but clean them here rather than carrying them into the next release branch.

## Docs — last, after the code is final

Per the sequencing rule, run the doc pass at the end of this phase, once Phases 1–3 have
landed. Read each file, then change only what is still false.

- `README.md:3-6` — "never leaves the device" and "the only telemetry is anonymous usage
  statistics" are both false as shipped (favicon egress, CloudKit, relay, Loox Link,
  entitlement). Qualify them.
- `README.md:20`, `:62`, `:117-118`, `AGENTS.md:138-139`, `CLAUDE.md:168` — after Phase 2D
  these describe reality again. **Verify before editing; do not "fix" docs that the code fix
  has already made correct.**
- `docs/deployment-guide.md` — currently has zero mentions of IAP, paywall, subscription or
  export compliance. Add a submission section (Phase 7 depends on it).
- `VaultifySafari/Resources/manifest.json:6` — `"version": "1.0"` vs `MARKETING_VERSION`.
  Cosmetic (Safari surfaces the host app's version), but generate it from `release.sh` and
  add a parity test. Do not gate on it.

## Phase exit criteria

- [ ] 3/3 snapshot tests green on the pinned toolchain, references re-recorded after human
      review of the LockControl visual change
- [ ] 2/2 UI tests green three consecutive times on an isolated simulator
- [ ] `TutorialTooltipSnapshotTests` crash reproduced and either fixed or documented as a
      toolchain artifact
- [ ] `make test` and `make check` green locally on the maintainer machine
- [ ] Toolchain pin policy documented and reproducible locally
- [ ] A tag whose SHA lacks a green required-workflow receipt cannot reach the upload path
- [ ] Runbook describes machinery that exists
- [ ] Zero Release compiler warnings
