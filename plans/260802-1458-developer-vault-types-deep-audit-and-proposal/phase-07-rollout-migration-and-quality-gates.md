---
title: "Phase 7: Rollout Migration and Quality Gates"
status: todo
---

# Phase 7: Rollout, Migration, and Quality Gates

## Outcome

Apply these gates to Release A, B, and C rather than treating quality as a final phase. Ship with an
explicit writer floor, observable non-sensitive failures, recovery paths, and adversarial verification
across iPhone/iPad/Mac, AutoFill extensions, Safari extension, backup, and CloudKit.

## Release Strategy

1. Release A1: Phase 1 current hardening with no resolver dependency. Release A2: Phase 2 semantics,
   projections, writer floor, and compatibility spikes. Migrate no artifacts yet.
2. Release B: Phase 3 local lifecycle + portable backup/stable IDs, Phase 4 UX, and Phase 5 SSH/API/Git.
   Artifact CloudKit writes remain disabled until the live convergence gate passes.
3. Release C: Artifact `CKAsset` convergence plus Phase 6 Apple pack. Secure File is a later decision
   only after artifact metrics and quota behavior are clean.

Local/build flags gate type discovery/import/action surfaces, not decoding. They are fix-forward controls,
not remote kill switches; adding signed remote configuration would require a separate threat model.
Once the app can read a semantic type or artifact record, decoding/recovery remains permanently enabled.

## Requirements

- [ ] Cross-version fixtures cover old app, current app, and synthetic future app payloads.
- [ ] Compatibility is tested against the actual prior release codec/binary behavior, not only a new legacy-mode decoder.
- [ ] Lazy semantic migration is idempotent, resumable, and retains original ciphertext on failure.
- [ ] Artifact migration and CloudKit schema rollout are separately gated and recoverable.
- [ ] Privacy-safe diagnostics report counts/error classes only, never values or identifying metadata.
- [ ] Documentation, codebase summary, deployment notes, threat model, mandatory EN/VI copy, and existing
  JA catalog continuity stay synchronized.

## File Inventory

- Add migration coordinator, checkpoints, protocol/minimum-writer gate, quarantine/retry UI, and recovery export if safe.
- Add feature flags and non-sensitive operational counters.
- Expand unit/integration/UI suites for app, AutoFill, Safari, CloudKit, sharing, and backup.
- Update `.github/workflows/ci.yml` for pure mapping/merge/parser/UI gates that run without CloudKit signing.
- Update `README.md`, `docs/codebase-summary.md`, design/feature maps, threat model, and deployment guide.
- Add release checklist and CloudKit production-schema runbook.

## Quality Gates

- Data: 100% legacy fixture survival, supported-schema unknown-ID round-trip, unsupported-schema raw
  recovery preservation, and zero silent omissions.
- Security: STRIDE/OWASP-style review, secret surface matrix, share capability review, temp/clipboard audit.
- Crypto/file: known-answer tests, fuzz malformed parsers, AAD/ciphertext swap rejection, crash recovery.
- Integration: explicit allowlist tests for AutoFill and Safari; browser bridge remains unchanged.
- Sync/backup: offline conflict, cursor upgrade/full-refetch, tombstone, optional clear, quota/full-disk,
  partial upload, stable ID/link recovery, and restore atomicity.
- Design: light/dark, mandatory EN/VI plus existing JA continuity, largest Dynamic Type, VoiceOver,
  Reduce Motion/Transparency, increased contrast,
  44pt targets, smallest/largest supported iPhone.
- Performance: unlock, 1,000-item list/search, maximum artifact import/export, bulk restore.

## Implementation Steps

1. Build fixture corpus and compatibility tests before turning on discovery for any new type.
2. Run migration in bounded batches after unlock; checkpoint success and keep original data until verified.
   Before artifact-backed creation, enforce a sync protocol/minimum-writer gate and define the behavior of
   long-offline older devices so they cannot overwrite opaque semantics or resurrect deleted artifacts.
3. Deploy CloudKit artifact schema ahead of app enablement using the Phase 3 runbook. CI covers pure
   mappings/merge/failure injection. A signed staging/TestFlight two-device gate covers live CKContainer:
   name owner, devices/accounts/container, fixture, evidence artifact, and explicit pass/fail before tag.
4. Roll out by release/feature gate. Diagnostics use only coarse `developer_credential` /
   `developer_asset` families, rounded count/latency buckets, and predeclared error enums under analytics
   consent. Never send raw type/role/provider/environment/algorithm/Team ID/bundle ID/host/filename/hash,
   exact size, parser text, or unsanitized Security/CloudKit/NSError descriptions.
5. Provide safe recovery for unsupported/corrupt items and unavailable legacy attachment bytes.
6. Run four hostile reviews: architecture/compatibility, security/privacy, UX/accessibility, and delivery/operations.
7. Re-read every phase after review, reconcile terms/IDs/dependencies, and freeze the release checklist.
8. Define fix-forward owner, SLA, triggers, and discovery/write-disable procedure for each release; a
   shipped binary is never assumed safely downgradable.

## Rollback Rules

- Disable creation/import/actions, never disable decode/recovery.
- Never downgrade/rewrite an unknown kind to `.custom` or `.login`.
- Never delete legacy attachment ciphertext until Artifact v2 adoption and backup verification succeed.
- On migration failure, retain original record/ciphertext and surface retry/recovery; do not partially save.

## Success Criteria

- [ ] Release gates have named owners, evidence links, and explicit pass/fail criteria.
- [ ] No P0/P1 confirmed red-team finding remains unresolved at enablement.
- [ ] CloudKit/backup restore tests pass with representative artifacts on two devices.
- [ ] Documentation and localized UX match the shipped capability without overpromising Git/SSH integration.
