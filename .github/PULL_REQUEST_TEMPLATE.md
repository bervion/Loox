## Outcome

<!-- What user or engineering outcome does this PR deliver? -->

Task: `TASK-YYYY-NNNN`

## Declared impact

<!-- Update .goclaw/pr-impact.yaml and use stable IDs from the quality ledger. -->

- Surfaces:
- States:
- Transitions:
- Risks:
- No-surface-impact reason, if applicable:

## Evidence

- Test commands and result bundles:
- Visual/accessibility matrix artifacts:
- Independent verifier:
- Evidence redaction reviewed: `yes/no`

## Contracts

- [ ] I updated `.goclaw/pr-impact.yaml`; `python3 scripts/quality/validate.py --all` passes.
- [ ] Tests exercise production behavior and do not disable, weaken or replace the oracle.
- [ ] Evidence uses synthetic data and contains no secrets or user vault content.
- [ ] User-facing copy is complete in EN and VI where applicable.
- [ ] UI changes meet design-token, accessibility and longest-VI-label requirements.
- [ ] Security, entitlement, sharing and analytics invariants remain fail-closed.
- [ ] Rollback is documented and does not require destructive user-data changes.
- [ ] Final approval, merge and release remain with `bervion`.
