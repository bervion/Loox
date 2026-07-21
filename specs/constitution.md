# Vaultify product constitution

This file defines the non-negotiable product constraints that every feature, fix,
test and release must preserve. The detailed engineering rules remain in
`AGENTS.md`, `CLAUDE.md`, `docs/design-guidelines.md` and
`docs/design-dna-standard.md`; this constitution gives the quality ledger a
stable acceptance contract.

1. Vault contents remain private by design. Tests and evidence use synthetic data
   and must never capture real vault values, recovery material, authentication
   tokens or signing credentials.
2. Security-sensitive behavior is fail-closed. A test seam may replace an external
   boundary, but it must not bypass authorization, encryption, entitlement or trust
   decisions in production code.
3. All user-facing app copy ships in English and Vietnamese. Safari extension copy
   ships in both locale bundles.
4. User-visible interfaces follow the token-driven Vaultify design system,
   accessibility contract and iOS 17.3 API floor.
5. Approval Mode and vault-item iCloud sync are independent control planes.
6. Generated Xcode projects are disposable. `Project.swift` and source files are the
   source of truth.
7. Claims require reproducible evidence. A `known` ledger record is inventory, not a
   passing test. Only an independent verifier may promote it to `verified`.
8. Tests must exercise production behavior. Disabled tests, constant assertions,
   hidden failures and edits that weaken the oracle are not acceptable evidence.
9. Only `bervion` may give final approval, merge or release. Agent reviews are
   advisory evidence and never substitute for owner authorization.
10. The repository remains portable: project-specific metadata uses relative paths,
    declared adapters and no machine secrets or absolute checkout paths.

When contracts conflict, the most privacy-preserving and fail-closed interpretation
wins until `bervion` approves a documented decision.
