# Vaultify quality ledger

The quality ledger is a source-controlled map from product behavior to deterministic
proof. It complements tests; it does not turn the existence of a test file into a
coverage claim.

## Identity contract

- `SurfaceID` (`SURF-<AREA>-NNN`) identifies a user-visible screen, sheet, flow or
  extension surface. A SwiftUI type is not automatically a surface.
- `StateID` (`STATE-<AREA>-<NAME>`) identifies an observable state on exactly one
  surface.
- `TransitionID` (`TRANS-<AREA>-<ACTION>`) identifies an observable, directed move
  between two states.
- `journey_id` is stable kebab-case and orders transitions into a continuous user
  journey.
- `fixture_id` (`FIX-<NAME>`) identifies a deterministic synthetic setup mechanism.
- `evidence_id` (`EVID-<NAME>`) identifies immutable proof for one `tested_sha` and git tree.

IDs are never recycled. Rename display names freely, but retain the ID. If semantics
change, retire the old record and add a new ID so prior evidence is not silently
reinterpreted.

## Verification status

- `known`: imported or reviewed inventory. This is not a passing test.
- `verified`: fresh independent evidence covers the exact ID at the exact commit.
- `stale`: prior proof exists but is outside its freshness window or no longer matches
  the implementation.
- `blocked`: verification cannot currently run; the blocker must be explicit in the
  associated task.

The initial registry was imported from `docs/app-feature-map-ui-ux.md`, observed on
2026-07-10. Every imported record intentionally starts as `known`.

## Current bootstrap status

As of 2026-07-21, the generated report contains 11 surfaces, 20 states, 12 transitions and
3 journeys. All remain `known`, `quality/verification/evidence-index.yaml` is empty and the
release readiness status is `not-evaluated`. Local runs made while the production-quality
change is uncommitted are diagnostic only; exact-commit independent evidence is still
pending.

Do not change these records to `verified` merely because the unit, snapshot, XCUITest or
Maestro lane passed locally. Promotion requires the exact committed candidate and the full
evidence contract.

## Source files

- `quality/coverage-ledger/`: surfaces, states, transitions and freshness policy.
- `quality/journeys/journeys.yaml`: ordered journey contracts.
- `quality/fixture-registry.yaml`: synthetic fixture implementations and paths.
- `quality/verification/evidence-index.yaml`: immutable evidence metadata.
- `quality/visual-matrix.yaml`: minimum appearance, locale and accessibility cases.
- `quality/risk-register.yaml`: product risks linked back to stable IDs.
- `.goclaw/pr-impact.yaml`: the current PR's declared impact.

All `.yaml` governance documents are JSON-compatible YAML so local checks use only the
Python standard library. Paths are repository-relative; portable manifests never store
developer-specific checkout paths.

## Promotion to verified

1. Run the production behavior with deterministic synthetic fixtures at the exact PR-head
   candidate commit; record its commit SHA, `git rev-parse <sha>^{tree}` and canonical
   evidence-input digest.
2. Store artifacts below `quality/verification/evidence/<task-id>/`.
3. Record tool version, command, environment, artifact SHA-256 and redaction metadata.
4. Have an independent verifier review the result and set `independent: true`.
5. In a later promotion-only commit, add the evidence ID to both the registry's `covers`
   fields and each covered ledger row, then change only those rows to `verified`.
6. Regenerate the report with `python3 scripts/quality/report.py`.
7. Run `python3 scripts/quality/validate.py --all`.

The validator requires `tested_sha` to be an ancestor, verifies its git tree and compares
the tested/current canonical input digests. Ledger status/evidence links may be promoted,
but changing behavior semantics, app code, tests, fixtures, workflow or validator logic
requires fresh evidence.

Do not hand-edit `quality/generated/coverage-report.json` or `.md`. Their source digest
must match the ledgers.

See [Verification evidence contract](./evidence-contract.md) and [Quality
validation](../runbooks/quality-validation.md).
