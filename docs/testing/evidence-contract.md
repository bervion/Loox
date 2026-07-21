# Verification evidence contract

Evidence is an auditable record of what ran, where it ran and what behavior it proved.
A screenshot or green console line without this metadata is an observation, not release
evidence.

Evidence is commit-bound. Output captured from an uncommitted or dirty working tree may be
used to diagnose the change, but it cannot promote ledger records to `verified`. Commit the
candidate first, check out and rerun the PR head SHA (not GitHub's synthetic merge SHA), and
have a verifier other than the implementer review the result. A later evidence-promotion
commit is expected: the validator proves the tested SHA is its ancestor, verifies the tested
git tree and compares a canonical behavior/input digest before accepting the later promotion.

Each `quality/verification/evidence-index.yaml` entry must include:

- capture time in UTC, the full lowercase `tested_sha`, its `tested_tree` git tree SHA and
  canonical `tested_input_digest` SHA-256;
- explicit release-gate claims that the independent verifier actually assessed;
- an independent verifier (the implementer cannot self-verify);
- tool name, version and exact command;
- OS, Xcode, device/simulator, locale and appearance;
- one or more repository-relative artifacts with SHA-256 digests;
- explicit SurfaceID, StateID, TransitionID and journey coverage;
- redaction metadata confirming review, no user data and the method used.

Release-gate evidence also requires `ci_attestations`. Each attestation binds one claim to
the exact GitHub Actions repository, workflow path, run/attempt, successful named job, head
SHA, artifact ID/name/API digest, payload path and payload SHA-256. Release preflight
re-queries the Actions API, confirms the exact run/job/head, downloads the bounded artifact
without forwarding GitHub authorization to the storage host, checks the archive digest and
then hashes the exact JSON payload. A repository file cannot attest itself. Historical
registry entries may remain after their 30-day Actions artifact expires; only evidence IDs
referenced by the current release gates are remotely revalidated.

| Gate | Workflow job | Payload artifact |
|---|---|---|
| Critical ledger | `Ledger evidence` | `ledger-evidence-receipt-<attempt>` |
| Tests | `Test evidence` | `test-evidence-receipt-<attempt>` |
| Privacy | `Privacy contract` | `privacy-contract-receipt-<attempt>` |
| EN/VI + accessibility | `Localization contract` | `localization-contract-receipt-<attempt>` |
| Risk disposition | `Risk disposition` | `risk-disposition-receipt-<attempt>` |
| Release notes/monitoring | `Release operations` | `release-operations-receipt-<attempt>` |
| Recovery | `Recovery rehearsal` | `recovery-rehearsal-receipt-<attempt>` |

The recovery producer lives in `.github/workflows/release-evidence.yml`; the others live in
`.github/workflows/ci.yml`. A gate payload with `status: fail` is retained for diagnosis but
cannot be promoted. Recovery evidence deliberately remains failed until a candidate-format
encrypted vault sentinel is functionally unlocked and read by the higher-build
previous-source artifact; install paths and launch PIDs alone are not health.
The recovery producer is entered through `repository_dispatch`, which loads its definition
from the default branch; it does not accept a branch-selected `workflow_dispatch` ref on the
persistent release runner.

Critical/high risks must be `mitigated` with registered evidence or `accepted` with a dated,
reasoned `bervion` acceptance. `quality/release/operations.yaml` must bind the exact release
ID to non-empty release notes, metrics, alerts, an incident channel and the fix-forward
runbook. These are checked directly by preflight as well as through gate artifacts.

Only synthetic fixtures are allowed. Never record real vault item names or values,
websites, search terms, passphrases, recovery keys, CloudKit identifiers, bearer tokens,
signing keys, profiles or raw production logs. Crop or redact simulator chrome when it
contains personal account information.

Artifact paths must remain below `quality/verification/evidence/`. Result bundles can be
summarized into deterministic text/JSON when the raw bundle is too large, but the summary
must name the source command and preserve failures. Never delete failures from a report or
use `continue-on-error` to manufacture a passing gate.

The CI scripts preserve this rule mechanically: `run-xcode-suite.sh` writes an
`xcresulttool` JSON summary when a result bundle exists, then exits with the original test
status. Maestro writes JUnit XML plus its debug and test artifact directories. GitHub
uploads the receipts even on failure for diagnosis, but upload alone does not make them
independent repository evidence.

Promotion is a separate reviewed commit: download each successful small gate payload,
place a redacted copy below `quality/verification/evidence/`, compute its SHA-256, record the
Actions attestation fields in the evidence index, disposition critical/high risks, complete
release notes and monitoring, and update readiness. Never edit a payload to change failure
to success. The release job re-downloads the original Actions bytes and rejects divergence.

Freshness defaults to seven days and three days for critical states, transitions and
journeys. A code or fixture change that invalidates the proof makes it stale immediately,
even inside the time window.

The digest excludes evidence registry/artifacts, generated reports and release readiness.
For ledgers, journeys, freshness and the visual matrix it ignores only
`verification_status`, `evidence_ids` and freshness records while hashing IDs, semantics,
criticality, transition chains and policy. It also hashes app code, tests, fixtures, CI and
validator logic. This avoids a self-referential commit hash without allowing old proof to be
attached to changed behavior.

See [Quality validation](../runbooks/quality-validation.md) for exact capture commands and
[Vaultify quality ledger](./quality-ledger.md) for promotion rules.
